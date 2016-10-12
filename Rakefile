require './rubocop_application.rb'
require './hello_application.rb'
require 'resque'
require 'resque/server'
require 'rack-lineprof'

require 'pathname'
Dir[Pathname.new('./').realpath.join('jobs/*.rb')].sort.each { |f| require f }

require 'resque/tasks'

