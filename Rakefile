require 'rake/sprocketstask'
require 'uglifier'

require './app.rb'

Rake::SprocketsTask.new do |t|
  t.environment = Slackify.assets
  t.output = File.join(Slackify.public_folder, 'assets')
  t.assets = ['app.js', 'app.css', '*.woff', '*.woff2', '*.ttf']
  t.environment.js_compressor = Uglifier.new(:mangle => true)
end.define

task 'assets:precompile' => :assets