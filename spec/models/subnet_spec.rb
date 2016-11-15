describe Subnet do
  context "with etcd having three subnets", :etcd => true do
    before do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.80.1.0' => {"address": "10.80.1.0/24"},
        '/kontena/ipam/subnets/10.80.2.0' => {"address": "10.80.2.0/24"},
        '/kontena/ipam/subnets/10.81.0.0' => {"address": "10.81.0.0/16"},
      )
    end

    it 'lists all subnets in etcd', :etcd => true do
      expect(Subnet.all.addrs).to eq [
        IPAddr.new('10.80.1.0/24'),
        IPAddr.new('10.80.2.0/24'),
        IPAddr.new('10.81.0.0/16'),
      ]

      expect(etcd_server).to_not be_modified
    end

    it 'reserves a subnet in etcd', :etcd => true do
      expect(Subnet.reserve(IPAddr.new('10.82.0.0/16'))).to eq Subnet.new('10.82.0.0', address: IPAddr.new('10.82.0.0/16'))

      expect(etcd_server).to be_modified
      expect(etcd_server.logs).to eq [
        [:create, '/kontena/ipam/subnets/10.82.0.0'],
      ]
      expect(etcd_server.nodes).to eq(
        '/kontena/ipam/subnets/10.80.1.0' => {"address" => "10.80.1.0/24"},
        '/kontena/ipam/subnets/10.80.2.0' => {"address" => "10.80.2.0/24"},
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
        '/kontena/ipam/subnets/10.82.0.0' => {"address" => "10.82.0.0/16"},
      )
    end

    it 'raises on conflict', :etcd => true do
      expect{Subnet.reserve(IPAddr.new('10.81.0.0/16'))}.to raise_error(Subnet::Conflict)

      expect(etcd_server).to_not be_modified
    end

    it 'raises on underlap conflict', :etcd => true do
      expect{Subnet.reserve(IPAddr.new('10.80.0.0/16'))}.to raise_error(Subnet::Conflict)

      expect(etcd_server).to be_modified
      expect(etcd_server.logs).to eq [
        [:create, '/kontena/ipam/subnets/10.80.0.0'],
        [:delete, '/kontena/ipam/subnets/10.80.0.0'],
      ]
      expect(etcd_server.nodes).to eq(
        '/kontena/ipam/subnets/10.80.1.0' => {"address" => "10.80.1.0/24"},
        '/kontena/ipam/subnets/10.80.2.0' => {"address" => "10.80.2.0/24"},
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
      )
    end

    it 'raises on overlap conflict' do
      expect{Subnet.reserve(IPAddr.new('10.81.1.0/24'))}.to raise_error(Subnet::Conflict)

      expect(etcd_server).to be_modified
      expect(etcd_server.logs).to eq [
        [:create, '/kontena/ipam/subnets/10.81.1.0'],
        [:delete, '/kontena/ipam/subnets/10.81.1.0'],
      ]
      expect(etcd_server.nodes).to eq(
        '/kontena/ipam/subnets/10.80.1.0' => {"address" => "10.80.1.0/24"},
        '/kontena/ipam/subnets/10.80.2.0' => {"address" => "10.80.2.0/24"},
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
      )
    end
  end

end
