#!/usr/bin/env ruby

require 'ipaddr'
require 'docker'

require_relative 'app/boot'
require_relative 'app/policy'
require_relative 'app/logging'

if ENV['LOG_LEVEL']
  log_level = ENV['LOG_LEVEL'].to_i
else
  log_level = Logger::INFO
end
Logging.initialize_logger(STDOUT, log_level)


EtcdModel.etcd = EtcdClient.new(ENV)

cleaner = AddressCleanup.new

cleaner.cleanup
