require 'rack'
require 'rack/server'
require 'sinatra/base'
require 'json'
require 'etcd'
require 'mutations'

require_relative 'models/address_pool'
require_relative 'mutations/address_pools/request'
require_relative 'mutations/addresses/request'

$stdout.sync = true
$etcd = Etcd.client(host: 'localhost', port: 2379)
