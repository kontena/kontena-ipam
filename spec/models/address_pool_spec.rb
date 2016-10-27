describe AddressPool do
  let :etcd do
    instance_double(EtcdClient)
  end

  before do
    EtcdModel.etcd = etcd
  end

  it 'creates objects in etcd' do
    expect(etcd).to receive(:set).with('/kontena/ipam/subnets/10.81.0.0', prevExist: false, value: '{"address":"10.81.0.0/16"}')
    expect(etcd).to receive(:get).with('/kontena/ipam/subnets/').and_return(instance_double(Etcd::Response, directory?: true, children: [
      instance_double(Etcd::Node, key: '/kontena/ipam/subnets/10.81.0.0', directory?: false, value: '{"address": "10.81.0.0/16"}'),
    ]))
    expect(etcd).to receive(:set).with('/kontena/ipam/pools/kontena', prevExist: false, value: '{"subnet":"10.81.0.0/16","gateway":"10.81.0.1/16"}')
    expect(etcd).to receive(:set).with('/kontena/ipam/addresses/kontena/', dir: true, prevExist: false)
    expect(etcd).to receive(:set).with('/kontena/ipam/addresses/kontena/10.81.0.1', prevExist: false, value: '{"address":"10.81.0.1/16"}')

    expect(described_class.create('kontena', subnet: IPAddr.new("10.81.0.0/16"))).to eq AddressPool.new('kontena', subnet: IPAddr.new("10.81.0.0/16"), gateway: IPAddr.new('10.81.0.1/16'))
  end

  it 'lists objects in etcd' do
    expect(etcd).to receive(:get).with('/kontena/ipam/pools/').and_return(instance_double(Etcd::Response, directory?: true, children: [
        instance_double(Etcd::Node, key: '/kontena/ipam/pools/kontena', directory?: false, value: '{"subnet": "10.81.0.0/16"}'),
    ]))

    expect(described_class.list).to eq [
      AddressPool.new("kontena", subnet: IPAddr.new("10.81.0.0/16")),
    ]
  end

  it 'gets objects in etcd' do
    expect(etcd).to receive(:get).with('/kontena/ipam/pools/kontena').and_return(
        instance_double(Etcd::Node, key: '/kontena/ipam/pools/kontena', directory?: false, value: '{"subnet": "10.81.0.0/16"}'),
    )

    expect(described_class.get('kontena')).to eq(
      AddressPool.new("kontena", subnet: IPAddr.new("10.81.0.0/16")),
    )
  end

  describe '#create_or_get' do
    it 'stores new object to etcd' do
      expect(etcd).to receive(:set).with('/kontena/ipam/subnets/10.81.0.0', prevExist: false, value: '{"address":"10.81.0.0/16"}')
      expect(etcd).to receive(:get).with('/kontena/ipam/subnets/').and_return(instance_double(Etcd::Response, directory?: true, children: [
        instance_double(Etcd::Node, key: '/kontena/ipam/subnets/10.81.0.0', directory?: false, value: '{"address": "10.81.0.0/16"}'),
      ]))
      expect(etcd).to receive(:set).with('/kontena/ipam/pools/kontena', prevExist: false, value: '{"subnet":"10.81.0.0/16","gateway":"10.81.0.1/16"}')
      expect(etcd).to receive(:set).with('/kontena/ipam/addresses/kontena/', dir: true, prevExist: false)
      expect(etcd).to receive(:set).with('/kontena/ipam/addresses/kontena/10.81.0.1', prevExist: false, value: '{"address":"10.81.0.1/16"}')

      expect(described_class.create_or_get('kontena', subnet: IPAddr.new("10.81.0.0/16"))).to eq AddressPool.new('kontena', subnet: IPAddr.new("10.81.0.0/16"), gateway: IPAddr.new('10.81.0.1/16'))
    end

    it 'loads existing object from etcd' do
      expect(etcd).to receive(:set).with('/kontena/ipam/subnets/10.81.0.0', prevExist: false, value: '{"address":"10.81.0.0/16"}')
      expect(etcd).to receive(:get).with('/kontena/ipam/subnets/').and_return(instance_double(Etcd::Response, directory?: true, children: [
        instance_double(Etcd::Node, key: '/kontena/ipam/subnets/10.80.0.0', directory?: false, value: '{"address": "10.80.0.0/16"}'),
        instance_double(Etcd::Node, key: '/kontena/ipam/subnets/10.81.0.0', directory?: false, value: '{"address": "10.81.0.0/16"}'),
      ]))

      expect(etcd).to receive(:set).with('/kontena/ipam/pools/kontena', prevExist: false, value: '{"subnet":"10.81.0.0/16","gateway":"10.81.0.1/16"}').and_raise(Etcd::NodeExist)
      expect(etcd).to receive(:get).with('/kontena/ipam/pools/kontena').and_return(
          instance_double(Etcd::Node, key: '/kontena/ipam/pools/kontena', directory?: false, value: '{"subnet": "10.80.0.0/16","gateway":"10.81.0.1/16"}'),
      )

      # yes, it returns with a different subnet
      expect(described_class.create_or_get('kontena', subnet: IPAddr.new("10.81.0.0/16"))).to eq AddressPool.new('kontena', subnet: IPAddr.new("10.80.0.0/16"), gateway: IPAddr.new('10.81.0.1/16'))
    end
  end

  it 'lists reserved subnets from etcd' do
    expect(etcd).to receive(:get).with('/kontena/ipam/subnets/').and_return(instance_double(Etcd::Response, directory?: true, children: [
      instance_double(Etcd::Node, key: '/kontena/ipam/subnets/10.0.0.0', directory?: false, value: '{"address": "10.80.0.0/24"}'),
      instance_double(Etcd::Node, key: '/kontena/ipam/subnets/10.0.1.0', directory?: false, value: '{"address": "10.80.1.0/24"}'),
      instance_double(Etcd::Node, key: '/kontena/ipam/subnets/10.81.0.0', directory?: false, value: '{"address": "10.81.0.0/16"}'),
    ]))

    expect(described_class.reserved_subnets.addrs).to eq [
      IPAddr.new("10.80.0.0/24"),
      IPAddr.new("10.80.1.0/24"),
      IPAddr.new("10.81.0.0/16"),
    ]
  end

  context 'for a AddressPool' do
    let :subject do
      described_class.new('kontena', subnet: IPAddr.new('10.81.0.0/16'), iprange: '10.81.128.0/17', gateway: IPAddr.new('10.81.0.1/16'))
    end

    it 'creates an address' do
      expect(etcd).to receive(:set).with('/kontena/ipam/addresses/kontena/10.81.0.1', prevExist: false, value: '{"address":"10.81.0.1/16"}')

      addr = subject.create_address(IPAddr.new('10.81.0.1'))

      expect(addr).to eq Address.new('kontena', '10.81.0.1', address: IPAddr.new('10.81.0.1/16'))
      expect(addr.address.to_cidr).to eq '10.81.0.1/16'
    end

    it 'gets an address from etcd' do
      expect(etcd).to receive(:get).with('/kontena/ipam/addresses/kontena/10.81.0.1').and_return(
        instance_double(Etcd::Node, key: '/kontena/ipam/addresses/kontena/10.81.0.1', directory?: false, value: '{"address": "10.81.0.1/16"}'),
      )

      addr = subject.get_address(IPAddr.new('10.81.0.1'))

      expect(addr).to eq Address.new('kontena', '10.81.0.1', address: IPAddr.new('10.81.0.1/16'))
      expect(addr.address).to eq IPAddr.new('10.81.0.1/16')
      expect(addr.address.to_cidr).to eq '10.81.0.1/16'
    end

    it 'gets an missing address from etcd' do
      expect(etcd).to receive(:get).with('/kontena/ipam/addresses/kontena/10.81.0.1').and_raise(Etcd::KeyNotFound)

      addr = subject.get_address(IPAddr.new('10.81.0.1'))

      expect(addr).to be_nil
    end

    it 'lists addresses from etcd' do
      expect(etcd).to receive(:get).with('/kontena/ipam/addresses/kontena/').and_return(instance_double(Etcd::Response, directory?: true, children: [
        instance_double(Etcd::Node, key: '/kontena/ipam/addresses/kontena/10.81.0.1', directory?: false, value: '{"address": "10.81.0.1/16"}'),
      ]))

      addrs = subject.list_addresses

      expect(addrs).to eq [
        Address.new('kontena', '10.81.0.1', address: IPAddr.new('10.81.0.1/16')),
      ]
      expect(addrs.first.address.to_cidr).to eq '10.81.0.1/16'
    end

    it 'lists reserved addresses from etcd' do
      expect(etcd).to receive(:get).with('/kontena/ipam/addresses/kontena/').and_return(instance_double(Etcd::Response, directory?: true, children: [
        instance_double(Etcd::Node, key: '/kontena/ipam/addresses/kontena/10.81.0.1', directory?: false, value: '{"address": "10.81.0.1/16"}'),
      ]))

      ipset = subject.reserved_addresses
      expect(ipset.addrs).to eq [
        IPAddr.new('10.81.0.1')
      ]
    end

    it 'deletes objects in etcd' do
      expect(etcd).to receive(:delete).with('/kontena/ipam/pools/kontena')
      expect(etcd).to receive(:delete).with('/kontena/ipam/addresses/kontena/', recursive: true)
      expect(etcd).to receive(:delete).with('/kontena/ipam/subnets/10.81.0.0', recursive: false)

      subject.delete!
    end
  end

  context 'for an AddressPool without an iprange' do
    let :subject do
      described_class.new('test', subnet: IPAddr.new('10.80.0.0/24'), gateway: IPAddr.new('10.80.0.1/24'))
    end

    describe '#allocation_range' do
      it 'allocates from the entire subnet' do
        expect(subject.allocation_range.first).to eq IPAddr.new('10.80.0.0/24')
        expect(subject.allocation_range.last).to eq IPAddr.new('10.80.0.255/24')
      end
    end

    describe '#available_addresses' do
      it 'returns the reduced subnet pool' do
        expect(etcd).to receive(:get).with('/kontena/ipam/addresses/test/').and_return(instance_double(Etcd::Response, directory?: true, children: []))

        addresses = subject.available_addresses

        expect(addresses.first).to eq IPAddr.new('10.80.0.1/24')
        expect(addresses).to eq (IPAddr.new('10.80.0.1/24')..IPAddr.new('10.80.0.254/24')).to_a
        expect(addresses.last).to eq IPAddr.new('10.80.0.254/24')
        expect(addresses.size).to eq(254)

      end

      it 'excludes reserved addresses from the reduced subnet pool' do
        expect(etcd).to receive(:get).with('/kontena/ipam/addresses/test/').and_return(instance_double(Etcd::Response, directory?: true, children: [
          instance_double(Etcd::Node, key: '/kontena/ipam/addresses/kontena/10.80.0.1', directory?: false, value: '{"address": "10.80.0.1/24"}'),
        ]))

        addresses = subject.available_addresses

        expect(addresses.first).to eq IPAddr.new('10.80.0.2/24')
        expect(addresses).to eq (IPAddr.new('10.80.0.2/24')..IPAddr.new('10.80.0.254/24')).to_a
        expect(addresses.size).to eq(253)
      end
    end
  end

  context 'for an AddressPool with an iprange' do
    let :subject do
      AddressPool.new('test', subnet: IPAddr.new('10.81.0.0/16'), iprange: IPAddr.new('10.81.1.0/29'))
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
      it 'returns the full iprange pool' do
        expect(etcd).to receive(:get).with('/kontena/ipam/addresses/test/').and_return(instance_double(Etcd::Response, directory?: true, children: []))

        addresses = subject.available_addresses

        expect(addresses.first).to eq IPAddr.new('10.81.1.0/16')
        expect(addresses).to eq (IPAddr.new('10.81.1.0/16')..IPAddr.new('10.81.1.7/16')).to_a
        expect(addresses.last).to eq IPAddr.new('10.81.1.7/16')
        expect(addresses.size).to eq 8
      end

      it 'excludes reserved addresses from the full iprange pool' do
        expect(etcd).to receive(:get).with('/kontena/ipam/addresses/test/').and_return(instance_double(Etcd::Response, directory?: true, children: reserved.map{|a|
          instance_double(Etcd::Node, key: "/kontena/ipam/addresses/test/#{a.to_s}", directory?: false, value: {'address' => a}.to_json)
        }))

        expect(subject.available_addresses).to eq available
      end
    end
  end

  context 'for an AddressPool with an iprange at the edge of the subnet' do
    let :subject do
      AddressPool.new('test', subnet: IPAddr.new('10.81.0.0/16'), iprange: IPAddr.new('10.81.0.0/24'))
    end

    describe '#allocation_range' do
      it 'allocates from the full range' do
        expect(subject.allocation_range.first).to eq IPAddr.new('10.81.0.0/24')
        expect(subject.allocation_range.last).to eq IPAddr.new('10.81.0.255/24')
      end
    end

    describe '#available_addresses' do
      it 'returns the reduced iprange' do
        expect(etcd).to receive(:get).with('/kontena/ipam/addresses/test/').and_return(instance_double(Etcd::Response, directory?: true, children: []))

        addresses = subject.available_addresses

        expect(addresses.first).to eq IPAddr.new('10.81.0.1/16')
        expect(addresses).to eq (IPAddr.new('10.81.0.1/16')..IPAddr.new('10.81.0.255/16')).to_a
        expect(addresses.last).to eq IPAddr.new('10.81.0.255/16')
        expect(addresses.size).to eq 255
      end
    end
  end

end
