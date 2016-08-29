require_relative 'app/boot'

class IpamPlugin < Sinatra::Application
  include Logging
  set :logging, true
  set :show_exceptions, false

  def self.ensure_keys
    $etcd.set('/kontena/ipam/pools/', dir: true) rescue nil
    $etcd.set('/kontena/ipam/addresses/', dir: true) rescue nil
  end

  post '/Plugin.Activate' do
    $etcd.set('/kontena/ipam/pools/', dir: true) rescue nil
    $etcd.set('/kontena/ipam/addresses/', dir: true) rescue nil
    JSON.dump(
      'Implements' => ['IpamDriver']
    )
  end

  post '/NetworkDriver.GetCapabilities' do
    JSON.dump(
      'Scope' => 'local'
    )
  end

  post '/IpamDriver.GetDefaultAddressSpaces' do
    JSON.dump(
      "LocalDefaultAddressSpace" => "kontenalocal",
      "GlobalDefaultAddressSpace" => "kontenaglobal"
    )
  end

  post '/IpamDriver.RequestPool' do
    data = JSON.parse(request.body.read)
    params = {}
    params[:id] = data['PoolID'] unless data['PoolID'].to_s.empty?
    params[:pool] = data['Pool'] unless data['Pool'].to_s.empty?
    params[:opts] = data['Options'] || {}
    params[:network] = data.dig('Options', 'network')
    outcome = AddressPools::Request.run(params)
    if outcome.success?
      JSON.dump(
        'PoolID' => outcome.result.id,
        'Pool' => outcome.result.pool,
        'Data' => {}
      )
    else
      response.status = 400
      JSON.dump(outcome.errors.message)
    end
  end

  post '/IpamDriver.RequestAddress' do
    data = JSON.parse(request.body.read)
    outcome = Addresses::Request.run(
      pool_id: data['PoolID']
    )
    if outcome.success?
      JSON.dump(
        "Address" => outcome.result
      )
    else
      response.status = 400
      JSON.dump(outcome.errors.message)
    end
  end

  post '/IpamDriver.ReleaseAddress' do
    data = JSON.parse(request.body.read)
    outcome = Addresses::Release.run(
      pool: data['PoolID'],
      address: data['Address']
    )
    if outcome.success?
      '{}'
    else
      response.status = 400
      JSON.dump(outcome.errors.message)
    end
  end

  post '/IpamDriver.ReleasePool' do
    data = JSON.parse(request.body.read)
    outcome = AddressPools::Release.run(
      id: data['PoolID']
    )
    if outcome.success?
      '{}'
    else
      response.status = 400
      JSON.dump(outcome.errors.message)
    end
  end
end

