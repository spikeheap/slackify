require './app.rb'

unless ENV['RACK_ENV'] == 'production'
  map '/assets' do
    run Slackify.assets
  end
end

run Slackify
