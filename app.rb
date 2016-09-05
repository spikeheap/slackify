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
  provider :spotify, ENV['SPOTIFY_CLIENT_ID'], ENV['SPOTIFY_CLIENT_SECRET'], scope: 'user-read-email playlist-modify-public' # user-library-read user-library-modify
end


get '/' do
  <<-HTML
    <a href="/auth/spotify">Link Spotify</a>
  HTML
end

get '/auth/:name/callback' do
  @@spotify_user = RSpotify::User.new(request.env['omniauth.auth'])
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


def extract_song_ids_from(text)
  text.scan(/(?:https:\/\/open.spotify.com\/track\/|spotify:track:)([a-zA-Z0-9]+)/).flatten
end

def add_to_spotify_playlist(playlist_owner, playlist_id, tracks)
  binding.pry
  playlist = RSpotify::Playlist.find(playlist_owner, playlist_id)
  playlist.add_tracks!(tracks)

  puts "Added #{tracks.map(&:name).join(', ')} to playlist '#{playlist.name}'"
end