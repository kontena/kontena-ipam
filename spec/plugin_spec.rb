require 'rack/test'

describe IpamPlugin do
  include Rack::Test::Methods

  let :policy do
    Policy.new(
      'KONTENA_IPAM_SUPERNET' => '10.80.0.0/12',
      'KONTENA_IPAM_SUBNET_LENGTH' => '24',
    )
  end

  before :each do
    IpamPlugin.policy = policy

    allow_any_instance_of(NodeHelper).to receive(:node).and_return('somehost')
  end

  let :app do
    subject
  end

  def api_post(url, params = {})
    if params.nil?
      post url
    else
      post url, params.to_json, { 'CONTENT_TYPE' => 'application/json' }
    end

    if last_response.content_type == 'application/json'
      JSON.parse(last_response.body)
    else
      last_response.body
    end
  end

  describe '/Plugin.Activate', :etcd => true do
    it 'implements IpamDriver' do
      data = api_post '/Plugin.Activate', nil

      expect(data).to eq({ 'Implements' => ['IpamDriver'] })

      expect(etcd_server).to be_modified
      expect(etcd_server.list).to eq [
        '/kontena/ipam/',
        '/kontena/ipam/addresses/',
        '/kontena/ipam/pools/',
        '/kontena/ipam/subnets/',
      ].to_set
    end
  end

  describe '/IpamDriver.GetCapabilities' do
    it 'does not require request replay' do
      data = api_post '/IpamDriver.GetCapabilities', nil

      expect(last_response).to be_ok
      expect(data['RequiresMACAddress']).to be_falsey
    end
  end

  describe '/IpamDriver.RequestPool' do
    it 'returns 400 on invalid JSON' do
      data = api_post '/Plugin.Activate', 'invalid'

      expect(last_response.status).to eq(400), last_response.errors

      expect(data).to match(/^JSON parse error: \d*: unexpected token at '\"invalid\"'$/)
    end

    it 'returns 400 on missing network option' do
      data = api_post '/IpamDriver.RequestPool', {}

      expect(last_response.status).to eq(400), last_response.errors

      expect(data).to eq('Error' => "Network can't be nil")
    end

    it 'returns 400 on invalid pool' do
      data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test'}, 'Pool' => 'xxx' }

      expect(last_response.status).to eq(400), last_response.errors

      expect(data).to eq('Error' => "Subnet is invalid")
    end

    context 'with etcd being empty', :etcd => true do
      it 'creates a new dynamic pool with only the required parameters' do
        data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test'} }

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq('PoolID' => 'test', 'Pool' => '10.80.0.0/24', 'Data' => {'com.docker.network.gateway' => '10.80.0.1/24'})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          "/kontena/ipam/addresses/test/10.80.0.1" => {"address"=>"10.80.0.1/24", "node"=>"somehost"},
          '/kontena/ipam/pool-nodes/test/somehost' => {},
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
        })
      end

      it 'creates a new dynamic pool with empty parameter values' do
        data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test'}, 'Pool' => '', 'SubPool' => ''}

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq('PoolID' => 'test', 'Pool' => '10.80.0.0/24', 'Data' => {'com.docker.network.gateway' => '10.80.0.1/24'})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          "/kontena/ipam/addresses/test/10.80.0.1" => {"address"=>"10.80.0.1/24", "node"=>"somehost"},
          '/kontena/ipam/pool-nodes/test/somehost' => {},
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
        })
      end

      it 'creates a new static pool using the given pool' do
        data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'kontena'}, 'Pool' => '10.81.0.0/16'}

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq('PoolID' => 'kontena', 'Pool' => '10.81.0.0/16', 'Data' => {'com.docker.network.gateway' => '10.81.0.1/16'})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          "/kontena/ipam/addresses/kontena/10.81.0.1" => {"address"=>"10.81.0.1/16", "node"=>"somehost"},
          '/kontena/ipam/pool-nodes/kontena/somehost' => {},
          '/kontena/ipam/pools/kontena' => { 'subnet' => '10.81.0.0/16', 'gateway' =>  '10.81.0.1/16'},
          '/kontena/ipam/subnets/10.81.0.0' => { 'address' => '10.81.0.0/16' },
        })
      end

      it 'creates a new static pool using the given iprange' do
        data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'kontena'}, 'Pool' => '10.81.0.0/16', 'SubPool' => '10.81.127.0/17'}

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq('PoolID' => 'kontena', 'Pool' => '10.81.0.0/16', 'Data' => {'com.docker.network.gateway' => '10.81.0.1/16'})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          "/kontena/ipam/addresses/kontena/10.81.0.1" => {"address"=>"10.81.0.1/16", "node"=>"somehost"},
          '/kontena/ipam/pool-nodes/kontena/somehost' => {},
          '/kontena/ipam/pools/kontena' => { 'subnet' => '10.81.0.0/16', 'iprange' => '10.81.127.0/17', 'gateway' => '10.81.0.1/16' },
          '/kontena/ipam/subnets/10.81.0.0' => { 'address' => '10.81.0.0/16' },
        })
      end
    end

    context 'with etcd having an existing test network', :etcd => true do
      before do
        etcd_server.load!(
          '/kontena/ipam/pool-nodes/test1/someotherhost' => {},
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
        )
      end

      it 'gets the existing pool' do
        data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test1'} }

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq('PoolID' => 'test1', 'Pool' => '10.80.0.0/24', 'Data' => {'com.docker.network.gateway' => '10.80.0.1/24'})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/pool-nodes/test1/someotherhost' => {},
          '/kontena/ipam/pool-nodes/test1/somehost' => {},
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
        })
      end

      it 'allocates dynamic addresses to avoid reservations' do
        data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test2'} }

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq('PoolID' => 'test2', 'Pool' => '10.80.1.0/24', 'Data' => {'com.docker.network.gateway' => '10.80.1.1/24'})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/pool-nodes/test1/someotherhost' => {},
          '/kontena/ipam/pool-nodes/test2/somehost' => {},
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/pools/test2' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
          "/kontena/ipam/addresses/test2/10.80.1.1" => {"address"=>"10.80.1.1/24", "node"=>"somehost"},
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
        })
      end

      it 'fails on a configuration conflict' do
        data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test1'}, 'Pool' => '10.80.1.0/24' }

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "pool test1 exists with subnet 10.80.0.0, requested 10.80.1.0")

        expect(etcd_server).to_not be_modified
      end

      it 'fails on a subnet conflict' do
        data = api_post '/IpamDriver.RequestPool', { 'Options' => { 'network' => 'test2'}, 'Pool' => '10.64.0.0/10' }

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "10.64.0.0 conflict: Conflict with network 10.80.0.0/24")

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/pool-nodes/test1/someotherhost' => {},
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
        })
        expect(etcd_server.logs).to eq [
          [:create, '/kontena/ipam/subnets/10.64.0.0'],
          [:delete, '/kontena/ipam/subnets/10.64.0.0',]
        ]
      end
    end
  end

  describe '/IpamDriver.RequestAddress' do
    context 'with etcd being empty', :etcd => true do
      it 'fails for a nonexistant pool' do
        data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test'}

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "Pool not found: test")

        expect(etcd_server).to_not be_modified
      end
    end

    context 'with etcd having an existing empty network', :etcd => true do
      before do
        etcd_server.load!(
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/addresses/test/' => nil
        )
      end

      it 'allocates a dynamic address' do
        data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test' }

        expect(last_response).to be_ok, last_response.errors
        expect(data.keys).to eq ['Address', 'Data']

        addr = IPAddr.new(data['Address'])
        expect(addr.network).to eq(IPAddr.new('10.80.0.0/24'))

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          "/kontena/ipam/addresses/test/#{addr.to_s}" => { 'address' => addr.to_cidr, 'node' => 'somehost'},
        })
      end

      it 'allocates a static adress' do
        data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test', 'Address' => '10.80.0.1'}

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq('Address' => '10.80.0.1/24', 'Data' => {})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/addresses/test/10.80.0.1' => { 'address' => '10.80.0.1/24', 'node' => 'somehost' },
        })
      end
    end

    context 'with etcd having an existing network with allocated addresses', :etcd => true do
      before do
        etcd_server.load!(
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/addresses/test/10.80.0.1' => { 'address' => '10.80.0.1/24', 'node' => 'somehost' },
          '/kontena/ipam/addresses/test/10.80.0.100' => { 'address' => '10.80.0.100/24', 'node' => 'somehost' },
        )
      end

      it 'conflicts on an existing static adress' do
        data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test', 'Address' => '10.80.0.1'}

        expect(last_response.status).to eq(400), last_response.errors
        expect(data['Error']).to match(%r{Allocation conflict for address=10.80.0.1: Create conflict with /kontena/ipam/addresses/test/10.80.0.1@\d+: Key already exists})

        expect(etcd_server).to_not be_modified, etcd_server.logs.inspect
      end

      it 'allocates a dynamic adress' do
        data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test' }

        expect(last_response).to be_ok, last_response.errors
        expect(data.keys).to eq ['Address', 'Data']

        addr = IPAddr.new(data['Address'])
        expect(addr.network).to eq(IPAddr.new('10.80.0.0/24'))

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/addresses/test/10.80.0.1' => { 'address' => '10.80.0.1/24', 'node' => 'somehost' },
          '/kontena/ipam/addresses/test/10.80.0.100' => { 'address' => '10.80.0.100/24', 'node' => 'somehost' },
          "/kontena/ipam/addresses/test/#{addr.to_s}" => { 'address' => addr.to_cidr, 'node' => 'somehost' },
        })
      end

      it 'allocates a static adress' do
        data = api_post '/IpamDriver.RequestAddress', { 'PoolID' => 'test', 'Address' => '10.80.0.2'}

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq('Address' => '10.80.0.2/24', 'Data' => {})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/addresses/test/10.80.0.1' => { 'address' => '10.80.0.1/24', 'node' => 'somehost' },
          '/kontena/ipam/addresses/test/10.80.0.2' => { 'address' => '10.80.0.2/24', 'node' => 'somehost' },
          '/kontena/ipam/addresses/test/10.80.0.100' => { 'address' => '10.80.0.100/24', 'node' => 'somehost' },
        })
      end
    end
  end

  describe '/IpamDriver.ReleaseAddress' do
    context 'with etcd having an existing network with allocated addresses', :etcd => true do
      before do
        etcd_server.load!(
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/addresses/test/10.80.0.1' => { 'address' => '10.80.0.1/24' },
          '/kontena/ipam/addresses/test/10.80.0.100' => { 'address' => '10.80.0.100/24' },
        )
      end

      it 'rejects a missing pool param' do
        data = api_post '/IpamDriver.ReleaseAddress', { 'Address' => '10.80.2.100'}

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "Pool can't be nil")

        expect(etcd_server).to_not be_modified
      end

      it 'rejects a missing address param' do
        data = api_post '/IpamDriver.ReleaseAddress', { 'PoolID' => 'test' }

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "Address can't be nil")

        expect(etcd_server).to_not be_modified
      end

      it 'rejects an invalid address' do
        data = api_post '/IpamDriver.ReleaseAddress', { 'PoolID' => 'test2', 'Address' => '10.80.2.265'}

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "Address is invalid")

        expect(etcd_server).to_not be_modified
      end

      it 'rejects for a nonexistant pool' do
        data = api_post '/IpamDriver.ReleaseAddress', { 'PoolID' => 'test2', 'Address' => '10.80.2.100'}

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "AddressPool not found: test2")

        expect(etcd_server).to_not be_modified
      end

      it 'rejects an address outside of the pool' do
        data = api_post '/IpamDriver.ReleaseAddress', { 'PoolID' => 'test', 'Address' => '10.80.2.100'}

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "Address 10.80.2.100 outside of pool subnet 10.80.0.0")

        expect(etcd_server).to_not be_modified
      end

      it 'ignores release for a nonexistant address' do
        data = api_post '/IpamDriver.ReleaseAddress', { 'PoolID' => 'test', 'Address' => '10.80.0.2'}

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq({})

        expect(etcd_server).to_not be_modified
      end

      it 'releases one of the addresses' do
        data = api_post '/IpamDriver.ReleaseAddress', { 'PoolID' => 'test', 'Address' => '10.80.0.100'}

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq({})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.0.0' => { 'address' => '10.80.0.0/24' },
          '/kontena/ipam/pools/test' => { 'subnet' => '10.80.0.0/24', 'gateway' => '10.80.0.1/24' },
          '/kontena/ipam/addresses/test/10.80.0.1' => { 'address' => '10.80.0.1/24' },
        })
      end

      it 'release of gateway has no effect' do
        data = api_post '/IpamDriver.ReleaseAddress', { 'PoolID' => 'test', 'Address' => '10.80.0.1'}

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq({})

        expect(etcd_server).to_not be_modified
      end
    end
  end

  describe '/IpamDriver.ReleasePool' do
    context 'with etcd having an existing network with allocated addresses', :etcd => true do
      before do
        etcd_server.load!(
          '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
          '/kontena/ipam/subnets/10.80.2.0' => { 'address' => '10.80.2.0/24' },
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24' },
          '/kontena/ipam/pools/test2' => { 'subnet' => '10.80.2.0/24' },
          '/kontena/ipam/pool-nodes/test1/somehost' => {},
          '/kontena/ipam/pool-nodes/test1/someotherhost' => {},
          '/kontena/ipam/pool-nodes/test2/somehost' => {},
          '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24' },
          '/kontena/ipam/addresses/test1/10.80.1.100' => { 'address' => '10.80.1.100/24' },
          '/kontena/ipam/addresses/test2/10.80.2.1' => { 'address' => '10.80.2.1/24' },
        )
      end

      it 'rejects for a nonexistant pool' do
        data = api_post '/IpamDriver.ReleasePool', { 'PoolID' => 'test' }

        expect(last_response.status).to eq(400), last_response.errors
        expect(data).to eq('Error' => "AddressPool not found: test")

        expect(etcd_server).to_not be_modified
      end

      it 'releases the pool but leaves it in use on a different node' do
        data = api_post '/IpamDriver.ReleasePool', { 'PoolID' => 'test1' }

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq({})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
          '/kontena/ipam/subnets/10.80.2.0' => { 'address' => '10.80.2.0/24' },
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24' },
          '/kontena/ipam/pools/test2' => { 'subnet' => '10.80.2.0/24' },
          '/kontena/ipam/pool-nodes/test1/someotherhost' => {},
          '/kontena/ipam/pool-nodes/test2/somehost' => {},
          '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24' },
          '/kontena/ipam/addresses/test1/10.80.1.100' => { 'address' => '10.80.1.100/24' },
          '/kontena/ipam/addresses/test2/10.80.2.1' => { 'address' => '10.80.2.1/24' },
        })
      end

      it 'releases the pool and deletes it if not used on another node' do
        data = api_post '/IpamDriver.ReleasePool', { 'PoolID' => 'test2' }

        expect(last_response).to be_ok, last_response.errors
        expect(data).to eq({})

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24' },
          '/kontena/ipam/pool-nodes/test1/somehost' => {},
          '/kontena/ipam/pool-nodes/test1/someotherhost' => {},
          '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24' },
          '/kontena/ipam/addresses/test1/10.80.1.100' => { 'address' => '10.80.1.100/24' },
        })
      end
    end
  end
end
