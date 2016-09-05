require 'dotenv'
require 'sinatra'
require 'json'
require 'pry'
require 'rspotify'
require 'rspotify/oauth'

Dotenv.load

configure do
  enable :sessions
end

use OmniAuth::Builder do
  provider :spotify, ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'], scope: 'user-read-email playlist-modify-public playlist-read-collaborative playlist-modify-private' # user-library-read user-library-modify
end

# # id and credentials are required to prime RSpotify
# id = request.env['omniauth.auth']['info']['id']
# credentials = request.env['omniauth.auth']['credentials']

# RSpotify::User.new(id: id, credentials: credentials)

# # these might be handy
# # display_name = request.env['omniauth.auth']['info']['display_name']
# # email = request.env['omniauth.auth']['info']['email']


get '/' do
  <<-HTML
    <a href="/auth/spotify">Link Spotify</a>
  HTML
end

get '/auth/:name/callback' do
  # persist the login
  # auth_data = request.env['omniauth.auth']

  # Login.create!(
  #     account: Account.find_or_create_by(email: auth_data['info']['email']),
  #     provider: 'spotify',
  #     token: auth_data['credentials']['token'],
  #     refresh_token: auth_data['credentials']['refresh_token'],
  #     expires_at: auth_data['credentials']['expires_at'],
  #     expires: true
  #   )

  # creating the user object primes the global credentials cache
  RSpotify::User.new(request.env['omniauth.auth'])

  <<-HTML
    <h1>Linked!</h1>
    <a href="/auth/spotify">Do it again</a>
  HTML
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
  puts data
  error 403 unless ENV['SLACK_TOKEN'] && data['token'] == ENV['SLACK_TOKEN']

  RSpotify.authenticate(ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'])

  tracks = extract_song_ids_from(data['text'])
    .map{|song_id| RSpotify::Track.find(song_id)
        .tap{|track| puts "Found #{track.name} by #{track.artists.map(&:name).join(', ')}"}}
    .reject{|track| track.nil?}

  add_to_spotify_playlist(ENV['SPOTIFY_PLAYLIST_USER'], ENV['SPOTIFY_PLAYLIST_ID'], tracks)

  status 200
end


def get_playlist(playlist_owner, id)
  url = "users/#{playlist_owner}/"
  url << (id == 'starred' ? id : "playlists/#{id}")

  response = RSpotify::User.oauth_get(playlist_owner, url)
  return response if RSpotify.raw_response
  RSpotify::Playlist.new response
end

def extract_song_ids_from(text)
  text.scan(/(?:https:\/\/open.spotify.com\/track\/|spotify:track:)([a-zA-Z0-9]+)/).flatten
end

def add_to_spotify_playlist(playlist_owner, playlist_id, tracks)
  playlist = get_playlist(playlist_owner, playlist_id)
  #playlist = RSpotify::Playlist.find(playlist_owner, playlist_id)
  playlist.add_tracks!(tracks)

  puts "Added #{tracks.map(&:name).join(', ')} to playlist '#{playlist.name}'"
end