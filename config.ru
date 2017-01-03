require_relative 'plugin.rb'
require_relative 'app/logging.rb'

if ENV['LOG_LEVEL']
  log_level = ENV['LOG_LEVEL'].to_i
else
  log_level = Logger::INFO
end
Logging.initialize_logger(STDOUT, log_level)

IpamPlugin.policy = Policy.new(ENV)



run IpamPlugin
