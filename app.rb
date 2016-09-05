require 'dotenv'
require 'sinatra/base'
require 'json'
require 'rspotify'
require 'rspotify/oauth'
require 'sinatra/sequel'

class Slackify < Sinatra::Base
  enable  :sessions, :logging
  # set :session_secret, ENV['SESSION_SECRET']
  # use Rack::Session::Cookie, :key => 'rack.session',
  #                          # :domain => 'foo.com',
  #                          # :path => '/',
  #                          # :expire_after => 2592000,
  #                          :secret => ENV['SESSION_SECRET']
  Dotenv.load
  register Sinatra::SequelExtension
  Sequel::Model.plugin :timestamps, :update_on_create => true

  # wrap this so services like Heroku work out of the box
  if ENV['DATABASE_URL'].nil?
    set :database, "postgres://#{ENV['POSTGRES_USER']}:#{ENV['POSTGRES_PASSWORD']}@#{ENV['POSTGRES_HOST']}/#{ENV['POSTGRES_DB']}"
  else
    set :database, ENV['DATABASE_URL']
  end

  require_relative './models/account'
  require_relative './models/collector'
  require_relative './models/login'

  ## Migrations
  migration "create the accounts, logins & collectors" do
    database.create_table :accounts do
      primary_key :id
      String      :display_name
      String      :email
      String      :spotify_id
      DateTime   :created_at, :null => false
      DateTime   :updated_at, :null => false
    end

    database.create_table :logins do
      primary_key :id
      foreign_key :account_id, :accounts
      String      :provider
      String      :token
      String      :refresh_token
      DateTime    :expires_at
      Boolean     :expires
      DateTime   :created_at, :null => false
      DateTime   :updated_at, :null => false
    end

    database.create_table :collectors do
      primary_key :id
      foreign_key :account_id, :accounts
      foreign_key :login_id, :logins
      String      :playlist_name
      String      :validation_token
      String      :playlist_owner_spotify_id
      String      :playlist_spotify_id
      DateTime   :created_at
      DateTime   :updated_at
    end
  end
  ## END of migrations

  configure do
    enable :sessions
  end

  use OmniAuth::Builder do
    provider :spotify, ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'], scope: 'user-read-email playlist-modify-public playlist-read-collaborative playlist-modify-private' # user-library-read user-library-modify
  end


  get '/' do
    @account = current_account
    erb :index
  end

  post '/collectors' do
    (playlist_owner_spotify_id, playlist_spotify_id) = playlist_tuples_in(params['playlist_uri'])

    Collector.find_or_create(
        account: current_account, 
        login: current_account.logins.first,
        playlist_name: get_playlist(playlist_owner_spotify_id, playlist_spotify_id).name,
        playlist_owner_spotify_id: playlist_owner_spotify_id,
        playlist_spotify_id: playlist_spotify_id
      ) do |collector|
        collector.validation_token = SecureRandom.urlsafe_base64(32)
      end

    redirect '/'
  end

  get '/auth/:provider/callback' do
    error 403 if params[:provider] != 'spotify'

    # persist the login
    auth_data = request.env['omniauth.auth']

    account = Account.find_or_create(email: "test") do |account|
      account.display_name = auth_data['info']['display_name']
      account.spotify_id = auth_data['info']['id']
    end

    session[:account_id] = account.id

    login = Login.find_or_create(account: account, provider: params[:provider])

    login.token = auth_data['credentials']['token'],
    login.refresh_token = auth_data['credentials']['refresh_token'],
    login.expires_at = Time.at(auth_data['credentials']['expires_at']),
    login.expires = true
    login.save

    # creating the user object primes the global credentials cache
    @user = RSpotify::User.new(request.env['omniauth.auth'])

    redirect '/'
  end

  get '/auth/failure' do
    <<-HTML
      <h1>Something went wrong 😔</h1>
      <a href="/auth/spotify">Link Spotify</a>
    HTML
  end


  post '/webhooks/slack' do
    request.body.rewind
    data = JSON.parse request.body.read

    collector = Collector.where(validation_token: data['token']).first
    error 403 if collector.nil?

    RSpotify.authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])
    
    tracks = extract_song_ids_from(data['text'])
      .map{|song_id| RSpotify::Track.find(song_id)
          .tap{|track| puts "Found #{track.name} by #{track.artists.map(&:name).join(', ')}"}}
      .reject{|track| track.nil?}

    add_to_spotify_playlist(collector, tracks)

    status 200
  end


  def get_playlist(playlist_owner, id)
    url = "users/#{playlist_owner}/"
    url << (id == 'starred' ? id : "playlists/#{id}")

    RSpotify.authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])
    
    response = RSpotify::User.oauth_get(playlist_owner, url)
    return response if RSpotify.raw_response
    RSpotify::Playlist.new response
  end

  def extract_song_ids_from(text)
    text.scan(/(?:https:\/\/open.spotify.com\/track\/|spotify:track:)([a-zA-Z0-9]+)/).flatten
  end

  def playlist_tuples_in(text)
    # FIXME: cope with URIs too
    text.scan(/https:\/\/open.spotify.com\/user\/([a-zA-Z0-9]+)\/playlist\/([a-zA-Z0-9]+)/).flatten
  end

  def add_to_spotify_playlist(collector, tracks)
    RSpotify.authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])
    RSpotify::User.new(id: collector.login.account.spotify_id, credentials: collector.login)

    playlist = get_playlist(collector.playlist_owner_spotify_id, collector.playlist_spotify_id)
    playlist.add_tracks!(tracks)

    puts "Added #{tracks.map(&:name).join(', ')} to playlist '#{playlist.name}'"
  end

  def current_account
    Account[session[:account_id]]
  end
end

if __FILE__ == $0
  Slackify.run!
end
