require 'rack'
require 'rack/server'
require 'sinatra/base'
require 'json'
require 'etcd'
require 'mutations'
require 'logger'
require 'ipaddr'

require_relative '../lib/ipaddr_helpers'
require_relative '../lib/etcd/keys'

require_relative 'logging'
require_relative 'policy'
require_relative 'models/address_pool'
require_relative 'mutations/address_pools/request'
require_relative 'mutations/address_pools/release'
require_relative 'mutations/addresses/request'
require_relative 'mutations/addresses/release'

$stdout.sync = true
$etcd = Etcd.client(host: 'localhost', port: 2379)
