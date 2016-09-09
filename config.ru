require './app.rb'
require 'sprockets'
require 'sprockets-helpers'
require 'bootstrap'
require 'font-awesome-sass'

unless ENV['RACK_ENV'] == 'production'
  map '/assets' do
    environment = Sprockets::Environment.new
    environment.append_path "assets/styles"
    environment.append_path "assets/js"
    environment.js_compressor  = :uglify
    environment.css_compressor = :scss

    run environment
  end
end

run Slackify
