#!/usr/bin/env ruby

require 'ipaddr'
require 'docker'

require_relative 'app/boot'
require_relative 'app/policy'

EtcdModel.etcd = EtcdClient.new(ENV)

cleaner = AddressCleanup.new

cleaner.cleanup
