require 'rack/test'

describe AddressCleanup do

  include Rack::Test::Methods

  let(:subject) do
    described_class.new('1')
  end


  describe '#local_addresses' do
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

      known_addresses = subject.local_addresses
      expect(known_addresses.size).to eq 1
    end
  end

  describe '#cleanup', :etcd => true do

    before do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
        '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24' },
        '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24' },
        '/kontena/ipam/addresses/test1/10.80.1.100' => { 'address' => '10.80.1.100/24', 'node' => '1' },
        '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
        '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' }
      )
    end

    it 'removes only unused addresses' do
      expect(subject).to receive(:local_addresses).and_return([IPAddr.new('10.80.1.111/24').to_host])

      subject.cleanup

      expect(etcd_server.nodes).to eq({
        '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
        '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24' },
        '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24' },
        '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
        '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' },
      })
    end
  end
end
