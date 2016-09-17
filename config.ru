require './rubocop_application.rb'
require './hello_application.rb'
require 'sidekiq'
require 'sidekiq/web'
require 'rack-lineprof'

require 'pathname'
Dir[Pathname.new('./').realpath.join('jobs/*.rb')].sort.each { |f| require f }

Sidekiq.configure_client do |config|
  config.redis = { url: 'redis://localhost:6379', namespace: 'sidekiq' }
end

use Rack::Lineprof

run Rack::URLMap.new(
  '/'        => RubocopApplication.new,
  '/sidekiq' => Sidekiq::Web,
  '/hello'   => HelloApplication.new
)

