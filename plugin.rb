require 'ipaddr'

require_relative 'app/boot'
require_relative 'app/policy'

require 'sinatra/base'
require 'sinatra/json'

# Implement the libnetwork IPAM Driver API
#
# @see https://github.com/docker/libnetwork/blob/master/docs/ipam.md
# @see https://github.com/docker/libnetwork/blob/master/ipams/remote/api/api.go
class IpamPlugin < Sinatra::Application
  include Logging
  set :logging, true
  set :show_exceptions, false

  def self.policy= (policy)
    @@policy = policy
  end
  def policy
    @@policy
  end

  def self.ensure_keys
    $etcd.set('/kontena/ipam/pools/', dir: true) rescue nil
    $etcd.set('/kontena/ipam/addresses/', dir: true) rescue nil
  end

  # Return HTTP 400 { "Error": ... } if the Mutations::Command#validate rejects the parameters
  error Mutations::ValidationException do
    error = env['sinatra.error']

    status 400
    json 'Error' => error.message
  end

  # Return HTTP 500 { "Error": ... }
  error do
    error = env['sinatra.error']

    status 500
    json 'Error' => error.message
  end

  # Parse request body as JSON { ... } into the request params
  #
  # @see Sinatra::Base#params
  before do
    body = request.body.read

    return if body.empty?

    begin
      params.merge! JSON.parse(body)
    rescue JSON::JSONError => error
      halt 400, "JSON parse error: #{error.message}"
    end
  end

  post '/Plugin.Activate' do
    $etcd.set('/kontena/ipam/pools/', dir: true) rescue nil
    $etcd.set('/kontena/ipam/addresses/', dir: true) rescue nil

    json(
      'Implements' => ['IpamDriver'],
    )
  end

  post '/IpamDriver.GetCapabilities' do
    json({})
  end

  post '/IpamDriver.GetDefaultAddressSpaces' do
    json(
      "LocalDefaultAddressSpace" => "kontenalocal",
      "GlobalDefaultAddressSpace" => "kontenaglobal"
    )
  end

  post '/IpamDriver.RequestPool' do
    pool = AddressPools::Request.run!(
      policy: policy,
      network: params.dig('Options', 'network'),
      subnet: params['Pool'],
    )

    json(
      'PoolID' => pool.id,
      'Pool' => pool.subnet.to_cidr,
      'Data' => {},
    )
  end

  post '/IpamDriver.RequestAddress' do
    address = Addresses::Request.run!(
      pool_id: params['PoolID'],
      address: params['Address'],
    )

    json(
      'Address' => address,
      'Data'    => {},
    )
  end

  post '/IpamDriver.ReleaseAddress' do
    Addresses::Release.run!(
      pool: params['PoolID'],
      address: params['Address']
    )

    json({})
  end

  post '/IpamDriver.ReleasePool' do
    AddressPools::Release.run!(
      pool_id: params['PoolID']
    )

    json({})
  end
end
