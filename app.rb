require 'dotenv'
require 'sinatra/base'
require 'json'
require 'rspotify'
require 'rspotify/oauth'
require 'omniauth-slack'
require 'sinatra/sequel'
require 'sequel'

# asset pipeline
require 'sprockets'
require 'sprockets-helpers'
require 'uglifier'

# assets
require 'bootstrap'
require 'font-awesome-sass'

require 'pry' if ENV['RACK_ENV'] == 'development'

class Slackify < Sinatra::Base

  Dotenv.load

  # Assets

  set :assets, Sprockets::Environment.new(root)

  configure do
    assets.logger = Logger.new(STDOUT)
    assets.append_path File.join(root, 'assets', 'styles')
    assets.append_path File.join(root, 'assets', 'js')
    assets.js_compressor  = :uglify
    assets.css_compressor = :scss

    Sprockets::Helpers.configure do |config|
      config.environment = assets
      config.digest      = true
    end
  end

  helpers do
    include Sprockets::Helpers
  end
  # End of assets

  enable  :sessions
  set :session_secret, ENV['SESSION_SECRET']

  register Sinatra::SequelExtension
  Sequel::Model.plugin :timestamps, :update_on_create => true

  # wrap this so services like Heroku work out of the box
  if ENV['DATABASE_URL'].nil?
    set :database, "postgres://#{ENV['POSTGRES_USER']}:#{ENV['POSTGRES_PASSWORD']}@#{ENV['POSTGRES_HOST']}/#{ENV['POSTGRES_DB']}"
  else
    set :database, ENV['DATABASE_URL']
  end

  ## Migrations
  Sequel.extension :migration
  Sequel::Migrator.apply(database, './db/migrate/')
  
  # these need to come last. Trust me
  require_relative './models/account'
  require_relative './models/collector'
  require_relative './models/login'
  require_relative './models/slack_team'

  use OmniAuth::Builder do
    provider :slack, ENV['SLACK_CLIENT_ID'], ENV['SLACK_CLIENT_SECRET'], scope: 'channels:history channels:read chat:write:bot'
    provider :spotify, ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'], scope: 'user-read-email playlist-modify-public playlist-read-collaborative playlist-modify-private' # user-library-read user-library-modify
  end

  #
  # Routes
  #

  get '/' do
    @account = current_account

    user = RSpotify::User.new(
      'id' => current_account.spotify_id, 
      'display_name' => current_account.display_name,
      'type' => 'user',
      'credentials' => {
        "token" => current_account.logins.first.token,
        "refresh_token" => current_account.logins.first.refresh_token,
        "expires_at" => current_account.logins.first.expires_at,
        "expires" => current_account.logins.first.expires
      })

    # TODO cache this
    @playlists = get_all_playlists_owned_by(user)
    erb :index
  end

  post '/collectors' do
    error 401 if current_account.nil?

    (playlist_owner_spotify_id, playlist_spotify_id) = playlist_tuples_in(params['playlist_uri'])

    # needed for get_playlist
    RSpotify.authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])
    RSpotify::User.new(
      'id' => current_account.spotify_id, 
      'display_name' => current_account.display_name,
      'type' => 'user',
      'credentials' => {
        "token" => current_account.logins.first.token,
        "refresh_token" => current_account.logins.first.refresh_token,
        "expires_at" => current_account.logins.first.expires_at,
        "expires" => current_account.logins.first.expires
      })

    Collector.find_or_create(
        account: current_account, 
        login: current_account.logins.first,
        playlist_name: get_playlist(playlist_owner_spotify_id, playlist_spotify_id).name,
        playlist_owner_spotify_id: playlist_owner_spotify_id,
        playlist_spotify_id: playlist_spotify_id
      ) do |collector|
        collector.validation_token = params['validation_token']
      end

    redirect '/'
  end

  delete "/collectors/:id" do
    error 403 unless request.xhr?

    collector = Collector[params[:id].to_i]

    error 404 if collector.nil?
    
    collector.delete

    status 200
  end

  delete "/session" do
    session.delete :account_id
    status 200
  end

  get '/auth/spotify/callback' do
    error 403 unless request.env['omniauth.auth']

    # persist the login
    auth_data = request.env['omniauth.auth']

    account = Account.find_or_create(email: auth_data['info']['email']) do |account|
      account.display_name = auth_data['info']['display_name']
      account.spotify_id = auth_data['info']['id']
    end

    login = Login.find_or_create(account: account, provider: params[:provider]) do |login|
      login.token = auth_data['credentials']['token']
      login.refresh_token = auth_data['credentials']['refresh_token']
      login.expires_at = Time.at(auth_data['credentials']['expires_at'])
      login.expires = true   
    end

    session[:account_id] = account.id

    redirect '/'
  end

  get '/auth/slack/callback' do
    auth_data = request.env['omniauth.auth']

    error 401 unless current_account
    error 403 unless auth_data

    login = Login.find_or_create(account: current_account, provider: 'slack') do |login|
      login.token = auth_data['credentials']['token']
    end

    login.slack_team = SlackTeam.new(name: auth_data['info']['team'])
    login.save
    redirect '/'
  end

  get '/auth/failure' do
    erb 'auth/failure'.to_sym
  end

  post '/webhooks/slack' do
    request.body.rewind

    collector = Collector.where(validation_token: params['token']).first
    error 403 if collector.nil?

    tracks = extract_song_ids_from(params['text'])
      .map{|song_id| RSpotify::Track.find(song_id)
          .tap{|track| puts "Found #{track.name} by #{track.artists.map(&:name).join(', ')}"}}
      .reject{|track| track.nil?}

    unless tracks.empty?
      add_to_spotify_playlist(collector, tracks)
    end

    status 200
  end

  #
  # Helpers and logic
  #

  def get_playlist(playlist_owner, id)
    url = "users/#{playlist_owner}/"
    url << (id == 'starred' ? id : "playlists/#{id}")
    puts url

    response = RSpotify::User.oauth_get(playlist_owner, url)
    return response if RSpotify.raw_response
    RSpotify::Playlist.new response
  end

  def extract_song_ids_from(text)
    text.scan(/(?:https:\/\/open.spotify.com\/track\/|spotify:track:)([a-zA-Z0-9]+)/).flatten
  end

  def playlist_tuples_in(text)
    # spotify:user:spikeheap:playlist:4Tvb0FsTCfDhIYohOCZgf9
    # https://open.spotify.com/user/spikeheap/playlist/4Tvb0FsTCfDhIYohOCZgf9
    text.scan(/(?:https:\/\/open.spotify.com\/user\/|spotify:user:)([a-zA-Z0-9]+)[\/:]playlist[\/:]([a-zA-Z0-9]+)/).flatten
  end

  def add_to_spotify_playlist(collector, tracks)
    RSpotify.authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])
    RSpotify::User.new(
      'id' => collector.login.account.spotify_id, 
      'display_name' => collector.login.account.display_name, 
      'credentials' => {
        "token" => collector.login.token,
        "refresh_token" => collector.login.refresh_token,
        "expires_at" => collector.login.expires_at,
        "expires" => collector.login.expires,
      })

    begin
      playlist = get_playlist(collector.playlist_owner_spotify_id, collector.playlist_spotify_id)

      puts "Adding #{tracks.map(&:name).join(', ')} to #{playlist.owner.id}'s playlist '#{playlist.name}'" 
      playlist.add_tracks!(tracks)
      puts "Added #{tracks.map(&:name).join(', ')} to #{playlist.owner.id}'s playlist '#{playlist.name}'"
    rescue => exception
      puts puts "Error adding #{tracks.map(&:name).join(', ')} to playlist #{collector.playlist_owner_spotify_id}/#{collector.playlist_spotify_id}"
      puts exception.message
      puts exception.backtrace
    end
  end

  def get_all_playlists_owned_by(user)
    limit = 50
    offset = 0
    playlists = []
    # keep asking to get all the playlists
    loop do
      result_set = user.playlists(limit: limit, offset: offset)
      playlists += result_set
      offset += limit
      break unless result_set.count == limit
    end

    playlists.select {|playlist| playlist.owner.external_urls['spotify'] == "http://open.spotify.com/user/#{user.id}" || playlist.collaborative }
  end

  helpers do
    def current_account
      Account[session[:account_id]]
    end
  end

  def current_account
    Account[session[:account_id]]
  end
end

if __FILE__ == $0
  Slackify.run!
end
