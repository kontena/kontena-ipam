describe AddressPool do
  before do
    allow_any_instance_of(NodeHelper).to receive(:node).and_return('somehost')
  end

  it 'creates objects in etcd', :etcd => true do
    expect(described_class.create('kontena', subnet: IPAddr.new("10.81.0.0/16"))).to eq AddressPool.new('kontena', subnet: IPAddr.new("10.81.0.0/16"), gateway: IPAddr.new('10.81.0.1/16'))

    expect(etcd_server.nodes).to eq(
      '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
      '/kontena/ipam/pools/kontena' => {"subnet" => "10.81.0.0/16", "gateway" => "10.81.0.1/16"},
      '/kontena/ipam/addresses/kontena/10.81.0.1' => {"address" => "10.81.0.1/16", "node" => "somehost"},
    )
  end

  it 'lists objects in etcd', :etcd => true do
    etcd_server.load!(
      '/kontena/ipam/pools/kontena' => {"subnet" => "10.81.0.0/16"},
    )

    expect(described_class.list).to eq [
      AddressPool.new("kontena", subnet: IPAddr.new("10.81.0.0/16")),
    ]
  end

  it 'gets objects in etcd', :etcd => true do
    etcd_server.load!(
      '/kontena/ipam/pools/kontena' => {"subnet" => "10.81.0.0/16"}
    )

    expect(described_class.get('kontena')).to eq(
      AddressPool.new("kontena", subnet: IPAddr.new("10.81.0.0/16")),
    )
  end

  describe '#create_or_get' do
    it 'stores new object to etcd', :etcd => true do
      expect(described_class.create_or_get('kontena', subnet: IPAddr.new("10.81.0.0/16"))).to eq AddressPool.new('kontena', subnet: IPAddr.new("10.81.0.0/16"), gateway: IPAddr.new('10.81.0.1/16'))

      expect(etcd_server).to be_modified
      expect(etcd_server.nodes).to eq(
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
        '/kontena/ipam/pools/kontena' => {"subnet" => "10.81.0.0/16", "gateway" => "10.81.0.1/16"},
        '/kontena/ipam/addresses/kontena/10.81.0.1' => {"address" => "10.81.0.1/16", "node" => "somehost"},
      )
    end

    it 'loads existing object from etcd', :etcd => true do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.80.0.0' => {"address" => "10.80.0.0/16"},
        '/kontena/ipam/pools/kontena' => {"subnet" => "10.80.0.0/16", "gateway" => "10.80.0.1/16"},
        '/kontena/ipam/addresses/kontena/10.80.0.1' => {"address" => "10.80.0.1/16"},
      )

      # yes, it returns with a different subnet
      expect(described_class.create_or_get('kontena', subnet: IPAddr.new("10.81.0.0/16"))).to eq AddressPool.new('kontena', subnet: IPAddr.new("10.80.0.0/16"), gateway: IPAddr.new('10.80.0.1/16'))

      # TODO: the requested subnet gets leaked
      expect(etcd_server).to be_modified
      expect(etcd_server.logs).to eq [
        [:create, '/kontena/ipam/subnets/10.81.0.0'],
      ]
      expect(etcd_server.nodes).to eq(
        '/kontena/ipam/subnets/10.80.0.0' => {"address" => "10.80.0.0/16"},
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
        '/kontena/ipam/pools/kontena' => {"subnet" => "10.80.0.0/16", "gateway" => "10.80.0.1/16"},
        '/kontena/ipam/addresses/kontena/10.80.0.1' => {"address" => "10.80.0.1/16"},
      )
    end
  end

  it 'lists reserved subnets from etcd', :etcd => true do
    etcd_server.load!(
      '/kontena/ipam/subnets/10.80.0.0' => {"address" => "10.80.0.0/24"},
      '/kontena/ipam/subnets/10.80.1.0' => {"address" => "10.80.1.0/24"},
      '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
    )

    expect(described_class.reserved_subnets.addrs).to eq [
      IPAddr.new("10.80.0.0/24"),
      IPAddr.new("10.80.1.0/24"),
      IPAddr.new("10.81.0.0/16"),
    ]
  end

  context 'for an AddressPool', :etcd => true do
    before do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
        '/kontena/ipam/pools/kontena' => {"subnet" => "10.81.0.0/16", "iprange" => '10.81.128.0/17', "gateway" => "10.81.0.1/16"},
        '/kontena/ipam/addresses/kontena/' => nil,
        '/kontena/ipam/pool-nodes/kontena/' => nil,
      )
    end

    let :subject do
      AddressPool.get('kontena')
    end

    describe '#request!' do
      it 'requests a PoolNode' do
        subject.request!

        expect(etcd_server).to be_modified
        expect(etcd_server.logs).to eq [
          [:create, '/kontena/ipam/pool-nodes/kontena/somehost'],
        ]
      end
    end

    describe '#orphaned?' do
      it 'is orphaned if there are no PoolNodes' do
        expect(subject).to be_orphaned
      end

      it 'is not orphaned if there are PoolNodes' do
        etcd_server.load!(
          '/kontena/ipam/pool-nodes/kontena/otherhost' => {},
        )

        expect(subject).to_not be_orphaned

        expect(etcd_server).to_not be_modified
      end
    end

    describe '#release!' do
      it 'releases the PoolNode' do
        etcd_server.load!(
          '/kontena/ipam/pool-nodes/kontena/somehost' => {},
        )

        subject.release!

        expect(etcd_server).to be_modified
        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/ipam/pool-nodes/kontena/somehost'],
        ]
      end
    end

    it 'creates an address' do
      addr = subject.create_address(IPAddr.new('10.81.0.1'))

      expect(addr).to eq Address.new('kontena', '10.81.0.1', node: 'somehost', address: IPAddr.new('10.81.0.1/16'))
      expect(addr.address.to_cidr).to eq '10.81.0.1/16'

      expect(etcd_server).to be_modified
      expect(etcd_server.logs).to eq [
        [:create, '/kontena/ipam/addresses/kontena/10.81.0.1'],
      ]
      expect(etcd_server.nodes).to eq(
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
        '/kontena/ipam/pools/kontena' => {"subnet" => "10.81.0.0/16", "iprange" => '10.81.128.0/17', "gateway" => "10.81.0.1/16"},
        '/kontena/ipam/addresses/kontena/10.81.0.1' => {"address" => "10.81.0.1/16", "node" => "somehost"},
      )
    end

    it 'gets an address from etcd' do
      etcd_server.load!(
        '/kontena/ipam/addresses/kontena/10.81.0.1' => {"address" => "10.81.0.1/16", "node" => "somehost"},
      )

      addr = subject.get_address(IPAddr.new('10.81.0.1'))

      expect(addr).to eq Address.new('kontena', '10.81.0.1', address: IPAddr.new('10.81.0.1/16'), node: "somehost")
      expect(addr.address).to eq IPAddr.new('10.81.0.1/16')
      expect(addr.address.to_cidr).to eq '10.81.0.1/16'

      expect(etcd_server).to_not be_modified

    end

    it 'gets an missing address from etcd' do
      addr = subject.get_address(IPAddr.new('10.81.0.1'))

      expect(addr).to be_nil

      expect(etcd_server).to_not be_modified
    end

    it 'lists addresses from etcd' do
      etcd_server.load!(
        '/kontena/ipam/addresses/kontena/10.81.0.1' => {"address" => "10.81.0.1/16", "node" => "somehost"},
      )

      addrs = subject.list_addresses

      expect(addrs).to eq [
        Address.new('kontena', '10.81.0.1', address: IPAddr.new('10.81.0.1/16'), node: "somehost"),
      ]
      expect(addrs.first.address.to_cidr).to eq '10.81.0.1/16'

      expect(etcd_server).to_not be_modified
    end

    it 'lists reserved addresses from etcd' do
      etcd_server.load!(
        '/kontena/ipam/addresses/kontena/10.81.0.1' => {"address" => "10.81.0.1/16", "node" => "somehost"},
      )

      ipset = subject.reserved_addresses
      expect(ipset.addrs).to eq [
        IPAddr.new('10.81.0.1')
      ]

      expect(etcd_server).to_not be_modified
    end

    describe '#delete' do
      it 'raises conflict if pool is in use' do
        etcd_server.load!(
          '/kontena/ipam/pool-nodes/kontena/somehost' => {},
        )

        expect{subject.delete!}.to raise_error(PoolNode::Conflict)

        expect(etcd_server).to_not be_modified
      end

      it 'deletes orpaned pool in etcd' do
        subject.delete!

        expect(etcd_server).to be_modified
        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/ipam/pool-nodes/kontena/'],
          [:delete, '/kontena/ipam/pools/kontena'],
          [:delete, '/kontena/ipam/addresses/kontena/'],
          [:delete, '/kontena/ipam/subnets/10.81.0.0'],
        ]
      end
    end

    describe '#cleanup' do
      it 'returns false if still in use' do
        etcd_server.load!(
          '/kontena/ipam/pool-nodes/kontena/somehost' => {},
        )

        expect(subject.cleanup).to be_falsey

        expect(etcd_server).to_not be_modified
      end

      it 'returns true if deleted' do
        expect(subject.cleanup).to be_truthy

        expect(etcd_server).to be_modified
        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/ipam/pool-nodes/kontena/'],
          [:delete, '/kontena/ipam/pools/kontena'],
          [:delete, '/kontena/ipam/addresses/kontena/'],
          [:delete, '/kontena/ipam/subnets/10.81.0.0'],
        ]
      end
    end
  end

  context 'for an AddressPool without an iprange', :etcd => true do
    before do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.80.0.0' => {"address" => "10.80.0.0/24"},
        '/kontena/ipam/pools/test0' => {"subnet" => "10.80.0.0/24", "gateway" => "10.80.0.1/24"},
        '/kontena/ipam/addresses/test0/10.80.0.1' => {'address' => "10.80.0.1/24"},
        '/kontena/ipam/pool-nodes/test0/' => nil,
      )
    end

    let :subject do
      AddressPool.get('test0')
    end

    describe '#allocation_range' do
      it 'allocates from the entire subnet' do
        expect(subject.allocation_range.first).to eq IPAddr.new('10.80.0.0/24')
        expect(subject.allocation_range.last).to eq IPAddr.new('10.80.0.255/24')
      end
    end

    describe '#available_addresses' do
      it 'returns the reduced subnet pool' do
        addresses = subject.available_addresses.to_a

        expect(addresses.first).to eq IPAddr.new('10.80.0.2/24')
        expect(addresses).to eq (IPAddr.new('10.80.0.2/24')..IPAddr.new('10.80.0.254/24')).to_a
        expect(addresses.last).to eq IPAddr.new('10.80.0.254/24')
        expect(addresses.size).to eq(253)

      end

      it 'excludes reserved addresses from the reduced subnet pool' do
        etcd_server.load!(
          '/kontena/ipam/addresses/test0/10.80.0.2' => {"address" => "10.80.0.2/24", 'node' => "somehost"}
        )

        addresses = subject.available_addresses.to_a

        expect(addresses.first).to eq IPAddr.new('10.80.0.3/24')
        expect(addresses).to eq (IPAddr.new('10.80.0.3/24')..IPAddr.new('10.80.0.254/24')).to_a
        expect(addresses.size).to eq(252)
      end
    end
  end

  context 'for an AddressPool with an iprange', :etcd => true do
    before do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
        '/kontena/ipam/pools/kontena' => {"subnet" => "10.81.0.0/16", "iprange" => '10.81.1.0/29', "gateway" => "10.81.0.1/16"},
        '/kontena/ipam/addresses/kontena/' => nil,
        '/kontena/ipam/pool-nodes/kontena/' => nil,
      )
    end

    let :subject do
      AddressPool.get('kontena')
    end

    let :addresses do
      [
        IPAddr.new('10.81.1.0/16'),
        IPAddr.new('10.81.1.1/16'),
        IPAddr.new('10.81.1.2/16'),
        IPAddr.new('10.81.1.3/16'),
        IPAddr.new('10.81.1.4/16'),
        IPAddr.new('10.81.1.5/16'),
        IPAddr.new('10.81.1.6/16'),
        IPAddr.new('10.81.1.7/16'),
      ]
    end

    let :reserved do
      [
        IPAddr.new('10.81.1.2'),
        IPAddr.new('10.81.1.3'),
      ]
    end

    let :available do
      [
        IPAddr.new('10.81.1.0/16'),
        IPAddr.new('10.81.1.1/16'),
        IPAddr.new('10.81.1.4/16'),
        IPAddr.new('10.81.1.5/16'),
        IPAddr.new('10.81.1.6/16'),
        IPAddr.new('10.81.1.7/16'),
      ]
    end

    describe '#allocation_range' do
      it 'allocates from the  full range' do
        expect(subject.allocation_range.first).to eq IPAddr.new('10.81.1.0/29')
        expect(subject.allocation_range.last).to eq IPAddr.new('10.81.1.7/29')
      end
    end

    describe '#available_addresses' do
      it 'returns enumerator' do
        expect(subject.available_addresses).to be_instance_of(Enumerator)
      end

      it 'returns the full iprange pool' do
        addresses = subject.available_addresses.to_a

        expect(addresses.first).to eq IPAddr.new('10.81.1.0/16')
        expect(addresses).to eq (IPAddr.new('10.81.1.0/16')..IPAddr.new('10.81.1.7/16')).to_a
        expect(addresses.last).to eq IPAddr.new('10.81.1.7/16')
        expect(addresses.size).to eq 8
      end

      it 'excludes reserved addresses from the full iprange pool' do
        reserved.each do |addr|
          etcd_server.load! "/kontena/ipam/addresses/kontena/#{addr.to_s}" => { 'address' => addr.to_cidr, 'node' => 'somenode' }
        end

        expect(subject.available_addresses.to_a).to eq available
      end
    end
  end

  context 'for an AddressPool with an iprange at the edge of the subnet', :etcd => true do
    before do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.81.0.0' => {"address" => "10.81.0.0/16"},
        '/kontena/ipam/pools/kontena' => {"subnet" => "10.81.0.0/16", "iprange" => '10.81.0.0/24', "gateway" => "10.81.0.1/16"},
        '/kontena/ipam/addresses/kontena/' => nil,
        '/kontena/ipam/pool-nodes/kontena/' => nil,
      )
    end

    let :subject do
      AddressPool.get('kontena')
    end


    describe '#allocation_range' do
      it 'allocates from the full range' do
        expect(subject.allocation_range.first).to eq IPAddr.new('10.81.0.0/24')
        expect(subject.allocation_range.last).to eq IPAddr.new('10.81.0.255/24')
      end
    end

    describe '#available_addresses' do
      it 'returns the reduced iprange' do
        addresses = subject.available_addresses.to_a

        expect(addresses.first).to eq IPAddr.new('10.81.0.1/16')
        expect(addresses).to eq (IPAddr.new('10.81.0.1/16')..IPAddr.new('10.81.0.255/16')).to_a
        expect(addresses.last).to eq IPAddr.new('10.81.0.255/16')
        expect(addresses.size).to eq 255
      end
    end
  end

end
