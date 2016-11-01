describe AddressPools::Request do
  let :policy do
    instance_double(Policy,
      supernet: IPAddr.new('10.80.0.0/16'),
    )
  end

  before do
    allow(policy).to receive(:is_a?).with(Hash).and_return(false)
    allow(policy).to receive(:is_a?).with(Array).and_return(false)
    allow(policy).to receive(:is_a?).with(Policy).and_return(true)

    allow_any_instance_of(NodeHelper).to receive(:node).and_return('somehost')
  end

  describe '#validate' do
    it 'rejects a missing network' do
      subject = described_class.new(policy: policy)

      expect(subject).to have_errors
    end

    it 'accepts a network' do
      subject = described_class.new(policy: policy, network: 'kontena')

      expect(subject).not_to have_errors, subject.validation_outcome.errors.inspect
    end

    it 'rejects an invalid subnet' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: 'asdf')

      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:subnet]).to eq :invalid
    end

    it 'accepts a valid subnet' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16')

      expect(subject).not_to have_errors, subject.validation_outcome.errors.inspect
    end

    it 'rejects an invalid iprange' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: 'asdf')

      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:iprange]).to eq :invalid
    end

    it 'accepts a valid iprange' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.128.0/17')

      expect(subject).not_to have_errors, subject.validation_outcome.errors.inspect
    end

    it 'rejects ipv6 pool request' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.128.0/17', ipv6: true)
      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:ipv6]).to eq :not_supported
    end

    it 'default to false ipv6 when ipv6 flag nil' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.128.0/17', ipv6: nil)
      expect(subject).not_to have_errors
    end
  end

  describe '#reserved_subnets' do
    let :subject do
      described_class.new(policy: policy, network: 'kontena')
    end

    it 'rejects an incorrect iprange' do
      subject = described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.80.0.0/24')

      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:iprange]).to eq :out_of_pool
    end
  end

  describe '#execute' do
    context 'allocating a dynamic pool' do
      let :subject do
        described_class.new(policy: policy, network: 'kontena')
      end

      it 'returns address pool if it already reserved in etcd' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16')))
        expect(PoolNode).to receive(:create_or_get).with('kontena', 'somehost').and_return(PoolNode.new('kontena', 'somehost'))

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
      end

      it 'returns address pool if it already exists in etcd' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16')))
        expect(PoolNode).to receive(:create_or_get).with('kontena', 'somehost').and_return(PoolNode.new('kontena', 'somehost'))

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
      end

      it 'returns new address pool' do
        ipset = IPSet.new([])
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(Subnet).to receive(:all).with(no_args).and_return(ipset)
        expect(policy).to receive(:allocatable_subnets).with(ipset).and_return([IPAddr.new('10.80.0.0/24')])
        expect(AddressPool).to receive(:create_or_get).with('kontena', subnet: IPAddr.new('10.80.0.0/24')).and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/24')))
        expect(PoolNode).to receive(:create_or_get).with('kontena', 'somehost').and_return(PoolNode.new('kontena', 'somehost'))

        outcome = subject.run

        expect(outcome).to be_success, outcome.errors.inspect
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/24'))
      end

      it 'returns a different address pool if some other network already exists in etcd' do
        ipset = IPSet.new([
          IPAddr.new('10.80.0.0/24'),
        ])
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(Subnet).to receive(:all).with(no_args).and_return(ipset)
        expect(policy).to receive(:allocatable_subnets).with(ipset).and_return([IPAddr.new('10.80.1.0/24')])
        expect(AddressPool).to receive(:create_or_get).with('kontena', subnet: IPAddr.new('10.80.1.0/24')).and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.1.0/24')))
        expect(PoolNode).to receive(:create_or_get).with('kontena', 'somehost').and_return(PoolNode.new('kontena', 'somehost'))

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.80.1.0/24'))
      end

      it 'fails if the supernet is exhausted' do
        ipset = IPSet.new((80..95).map { |i| IPAddr.new("10.#{i}.0.0/16") })
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(Subnet).to receive(:all).with(no_args).and_return(ipset)
        expect(policy).to receive(:allocatable_subnets).with(ipset).and_return([])

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:subnet]).to eq :full
      end
    end

    context 'allocating a static pool' do
      let :subject do
        described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16')
      end

      it 'returns address pool if it already exists in etcd' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16')))
        expect(PoolNode).to receive(:create_or_get).with('kontena', 'somehost').and_return(PoolNode.new('kontena', 'somehost'))

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
      end

      it 'fails if the network already exists with a different subnet' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16')))

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:pool]).to eq :invalid
      end

      it 'fails if a network already exists with the same subnet' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(Subnet).to receive(:create).with(IPAddr.new('10.81.0.0/16')).and_raise(Subnet::Conflict)

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:subnet]).to eq :conflict
      end

      it 'fails if a network already exists with an overlapping subnet' do
        subnet = Subnet.new('10.81.0.0', address: IPAddr.new('10.81.0.0/16'))

        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(Subnet).to receive(:create).with(IPAddr.new('10.81.0.0/16')).and_return(subnet)
        expect(Subnet).to receive(:all).with(no_args).and_return(IPSet.new([
          IPAddr.new('10.80.0.0/15'),
          IPAddr.new('10.81.0.0/16')
        ]))
        expect(subnet).to receive(:delete!)

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:subnet]).to eq :conflict
      end

      it 'fails if a network already exists with an underlapping subnet' do
        subnet = Subnet.new('10.81.0.0', address: IPAddr.new('10.81.0.0/16'))

        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(Subnet).to receive(:create).with(IPAddr.new('10.81.0.0/16')).and_return(subnet)
        expect(Subnet).to receive(:all).with(no_args).and_return(IPSet.new([
          IPAddr.new('10.81.0.0/16'),
          IPAddr.new('10.81.10.0/24'),
        ]))
        expect(subnet).to receive(:delete!)

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:subnet]).to eq :conflict
      end

      it 'returns address pool if some other network exists in etcd' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(AddressPool).to receive(:create_or_get).with('kontena', subnet: IPAddr.new('10.81.0.0/16'), iprange: nil).and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16')))
        expect(PoolNode).to receive(:create_or_get).with('kontena', 'somehost').and_return(PoolNode.new('kontena', 'somehost'))

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
      end
    end

    context 'allocating a static pool with an iprange' do
      let :subject do
        described_class.new(policy: policy, network: 'kontena', subnet: '10.81.0.0/16', iprange: '10.81.128.0/17')
      end

      let :pool do
        AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'), iprange: IPAddr.new('10.81.128.0/17'))
      end

      it 'creates the address pool with the ipragnge' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(nil)
        expect(AddressPool).to receive(:create_or_get).with('kontena', subnet: IPAddr.new('10.81.0.0/16'), iprange: IPAddr.new('10.81.128.0/17')).and_return(pool)
        expect(PoolNode).to receive(:create_or_get).with('kontena', 'somehost').and_return(PoolNode.new('kontena', 'somehost'))

        outcome = subject.run

        expect(outcome).to be_success
        expect(outcome.result).to eq pool
      end

      it 'fails if the network already exists with a different iprange' do
        expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'), iprange: IPAddr.new('10.80.0.0/17')))

        outcome = subject.run

        expect(outcome).to_not be_success
        expect(outcome.errors.symbolic[:pool]).to eq :invalid
      end
    end
  end
end
