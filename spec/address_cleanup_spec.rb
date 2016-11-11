require 'rack/test'

describe AddressCleanup do

  include Rack::Test::Methods

  let(:subject) do
    expect_any_instance_of(NodeHelper).to receive(:node).and_return('1')
    described_class.new
  end

  describe '#initialize' do
    it 'fallbacks to NodeHelper to get node id' do
      expect_any_instance_of(NodeHelper).to receive(:node).and_return('somenode')

      cleaner = described_class.new
      expect(cleaner.instance_variable_get('@node')).to eq('somenode')
    end
  end

  describe '#local_docker_known_addresses' do
    it 'collects all docker address' do
      expect(Docker::Network).to receive(:all).and_return(
        [
          double(json: {
            "IPAM" => {
              "Driver" => "kontena-ipam"
            },
            "Containers" => { "foo" => {"IPv4Address" => "10.80.0.11/24"}}
            }
          ),
          double(json: {
            "IPAM" => {
              "Driver" => "default"
            },
            "Containers" => { "bar" => {"IPv4Address" => "10.85.0.11/24"}}
            }
          )
        ]
      )

      known_addresses = subject.send(:local_docker_known_addresses)
      expect(known_addresses.size).to eq 1
    end
  end
  
  describe '#cleanup', :etcd => true do

    before do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
        '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
        '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24' },
        '/kontena/ipam/addresses/test1/10.80.1.100' => { 'address' => '10.80.1.100/24', 'node' => '1' },
        '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
        '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' }
      )
    end

    it 'removes only unused addresses' do
      subject.send(:cleanup, [IPAddr.new('10.80.1.111/24').to_host])

      expect(etcd_server.nodes).to eq({
        '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
        '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
        '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24' },
        '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
        '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' },
      })
    end
  end

end
