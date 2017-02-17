require './rubocop_application.rb'
require './hello_application.rb'
require './bundle_update_application.rb'
require 'resque'
require 'resque/server'
require 'rack-lineprof'

require 'pathname'
Dir[Pathname.new('./').realpath.join('jobs/*.rb')].sort.each { |f| require f }

#Sidekiq.configure_client do |config|
#  config.redis = { url: 'redis://localhost:6379', namespace: 'sidekiq' }
#end

Resque.redis = 'redis://localhost:6379'
Resque.redis.namespace = "resque-hook"

#use Rack::Lineprof

run Rack::URLMap.new(
  '/'              => RubocopApplication.new,
  '/bundle_update' => BundleUpdateApplication.new,
  '/resque'        => Resque::Server.new,
  '/hello'         => HelloApplication.new,
  '/favicon.ico'   => HelloApplication.new
)

