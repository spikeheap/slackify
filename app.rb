require 'dotenv'
require 'sinatra/base'
require 'json'
require 'rspotify'
require 'rspotify/oauth'
require 'sinatra/sequel'
require 'sequel'

class Slackify < Sinatra::Base

  Dotenv.load

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

  use OmniAuth::Builder do
    provider :spotify, ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'], scope: 'user-read-email playlist-modify-public playlist-read-collaborative playlist-modify-private' # user-library-read user-library-modify
  end

  #
  # Routes
  #

  get '/' do
    @account = current_account
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

  get '/auth/:provider/callback' do
    error 403 if params[:provider] != 'spotify'

    # persist the login
    auth_data = request.env['omniauth.auth']

    account = Account.find_or_create(email: auth_data['info']['email']) do |account|
      account.display_name = auth_data['info']['display_name']
      account.spotify_id = auth_data['info']['id']
    end

    session[:account_id] = account.id

    login = Login.find_or_create(account: account, provider: params[:provider])

    login.token = auth_data['credentials']['token']
    login.refresh_token = auth_data['credentials']['refresh_token']
    login.expires_at = Time.at(auth_data['credentials']['expires_at'])
    login.expires = true
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
    text.scan(/(?:https:\/\/open.spotify.com\/user\/|spotify:user:)([a-zA-Z0-9]+)(?:\/|:)([a-zA-Z0-9]+)/).flatten
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

  def current_account
    Account[session[:account_id]]
  end
end

if __FILE__ == $0
  Slackify.run!
end
