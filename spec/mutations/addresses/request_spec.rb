describe Addresses::Request do
  let :policy do
    double()
  end

  before do
    allow(policy).to receive(:is_a?).with(Hash).and_return(false)
    allow(policy).to receive(:is_a?).with(Array).and_return(false)
    allow(policy).to receive(:is_a?).with(Policy).and_return(true)
  end

  describe '#validate' do
    it 'errors when pool not found' do
      expect(AddressPool).to receive(:get).with('not_found').and_return(nil)

      subject = described_class.new(policy: policy, pool_id: 'not_found')

      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:pool]).to eq :not_found
    end

    it 'errors when an invalid address is given' do
      subject = described_class.new(policy: policy, pool_id: 'foo', address: 'fdfdfds')

      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:address]).to eq :invalid
    end

    it 'errors when address not in pool range' do
      expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16')))

      subject = described_class.new(policy: policy, pool_id: 'kontena', address: '10.99.100.100')

      expect(subject).to have_errors
      expect(subject.validation_outcome.errors.symbolic[:address]).to eq :out_of_pool
    end

    it 'retrives pool when found' do
      expect(AddressPool).to receive(:get).with('found').and_return(AddressPool.new('found', subnet: IPAddr.new('10.81.0.0/16')))

      subject = described_class.new(policy: policy, pool_id: 'found')

      expect(subject).not_to have_errors, subject.validation_outcome.errors.inspect

      expect(subject.instance_variable_get(:@pool)).to eq AddressPool.new('found', subnet: IPAddr.new('10.81.0.0/16'))
    end
  end

  context 'when allocating a static address' do
    let :pool do
      AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
    end

    let :subject do
      expect(AddressPool).to receive(:get).with('kontena').and_return(pool)

      subject = described_class.new(policy: policy, pool_id: 'kontena', address: '10.81.100.100')

      raise subject.validation_outcome.errors.inspect if subject.has_errors?

      subject
    end

    describe '#execute' do
      it 'reserves given address if available' do
        addr = Address.new('kontena', '10.81.100.100', address: pool.subnet.subnet_addr('10.81.100.100'))

        expect(Address).to receive(:create).with('kontena', '10.81.100.100', address: IPAddr.new('10.81.100.100')).and_return(addr)

        outcome = subject.run

        expect(outcome).to be_success, outcome.errors.inspect
        expect(outcome.result).to eq addr
        expect(outcome.result.address.to_cidr).to eq '10.81.100.100/16'
      end

      it 'errors if given address conflicts' do
        expect(Address).to receive(:create).with('kontena', '10.81.100.100', address: IPAddr.new('10.81.100.100')).and_raise(Address::Conflict)

        outcome = subject.run

        expect(outcome).to_not be_success, outcome.errors.inspect
        expect(outcome.errors.symbolic[:address]).to eq :conflict
      end
    end
  end

  context 'when not using iprange' do
    let :pool do
      AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'))
    end

    let :subject do
      expect(AddressPool).to receive(:get).with('kontena').and_return(pool)

      subject = described_class.new(policy: policy, pool_id: 'kontena')

      raise subject.validation_outcome.errors.inspect if subject.has_errors?

      subject
    end

    describe '#available_addresses' do
      it 'returns the full subnet pool' do
        expect(pool).to receive(:reserved_addresses).and_return([])

        addresses = subject.available_addresses

        expect(addresses.first).to eq IPAddr.new('10.81.0.1')
        expect(addresses.last).to eq IPAddr.new('10.81.255.254')
        expect(addresses.size).to eq(2**16 - 2)
      end
    end

    describe '#execute' do
      it 'reserves dynamic address if pool is empty' do
        addr = Address.new('kontena', '10.81.100.100', address: pool.subnet.subnet_addr('10.81.100.100'))
        expect(addr.address.to_cidr).to eq '10.81.100.100/16'

        allow(pool).to receive(:reserved_addresses).and_return([]) # XXX: called twice?
        expect(policy).to receive(:allocate_address).with(subject.available_addresses).and_return(IPAddr.new('10.81.100.100'))
        expect(Address).to receive(:create).with('kontena', '10.81.100.100', address: IPAddr.new('10.81.100.100')).and_return(addr)

        outcome = subject.run

        expect(outcome).to be_success, outcome.errors.inspect
        expect(outcome.result).to eq addr
        expect(outcome.result.address.to_cidr).to eq '10.81.100.100/16'
      end

      it 'errors if the pool is full' do
        expect(pool).to receive(:reserved_addresses).and_return(pool.subnet.list_hosts)
        expect(policy).to receive(:allocate_address).with([]).and_return(nil)

        outcome = subject.run

        expect(outcome).to_not be_success, outcome.errors.inspect
        expect(outcome.errors.symbolic[:address]).to eq :allocate
      end
    end
  end

  context 'when using iprange' do
    let :pool do
      AddressPool.new('kontena', subnet: IPAddr.new('10.81.0.0/16'), iprange: IPAddr.new('10.81.1.0/29'))
    end

    let :addresses do
      [
        IPAddr.new('10.81.1.1'),
        IPAddr.new('10.81.1.2'),
        IPAddr.new('10.81.1.3'),
        IPAddr.new('10.81.1.4'),
        IPAddr.new('10.81.1.5'),
        IPAddr.new('10.81.1.6'),
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
        IPAddr.new('10.81.1.1'),
        IPAddr.new('10.81.1.4'),
        IPAddr.new('10.81.1.5'),
        IPAddr.new('10.81.1.6'),
      ]
    end

    let :subject do
      expect(AddressPool).to receive(:get).with('kontena').and_return(pool)

      subject = described_class.new(policy: policy, pool_id: 'kontena')

      raise subject.validation_outcome.errors.inspect if subject.has_errors?

      subject
    end

    describe '#available_addresses' do
      it 'returns the reduced iprange pool' do
        expect(pool).to receive(:reserved_addresses).and_return([])

        expect(subject.available_addresses).to eq addresses
      end

      it 'excludes all reserved addresses from the pool' do

        expect(pool).to receive(:reserved_addresses).and_return(reserved)

        expect(subject.available_addresses).to eq available
      end
    end

    describe '#execute' do
      it 'reserves dynamic address if pool is empty' do
        addr = Address.new('kontena', '10.81.1.1', address: pool.subnet.subnet_addr('10.81.1.1'))

        expect(pool).to receive(:reserved_addresses).and_return([])
        expect(policy).to receive(:allocate_address).with(addresses).and_return(IPAddr.new('10.81.1.1'))
        expect(Address).to receive(:create).with('kontena', '10.81.1.1', address: IPAddr.new('10.81.1.1')).and_return(addr)

        outcome = subject.run

        expect(outcome).to be_success, outcome.errors.inspect
        expect(outcome.result).to eq addr
        expect(outcome.result.address.to_cidr).to eq '10.81.1.1/16'
      end

      it 'reserves dynamic address if pool has reserved addresses' do
        addr = Address.new('kontena', '10.81.1.1', address: pool.subnet.subnet_addr('10.81.1.1'))

        expect(pool).to receive(:reserved_addresses).and_return(reserved)
        expect(policy).to receive(:allocate_address).with(available).and_return(IPAddr.new('10.81.1.1'))
        expect(Address).to receive(:create).with('kontena', '10.81.1.1', address: IPAddr.new('10.81.1.1')).and_return(addr)

        outcome = subject.run

        expect(outcome).to be_success, outcome.errors.inspect
        expect(outcome.result).to eq addr
        expect(outcome.result.address.to_cidr).to eq '10.81.1.1/16'
      end

      it 'errors if the pool is full' do
        expect(pool).to receive(:reserved_addresses).and_return(addresses)
        expect(policy).to receive(:allocate_address).with([]).and_return(nil)

        outcome = subject.run

        expect(outcome).to_not be_success, outcome.errors.inspect
        expect(outcome.errors.symbolic[:address]).to eq :allocate
      end

      it 'retries allocation on address conflict' do
        addr = Address.new('kontena', '10.81.1.2', address: pool.subnet.subnet_addr('10.81.1.2'))

        expect(pool).to receive(:reserved_addresses).and_return([])
        expect(policy).to receive(:allocate_address).with(addresses).and_return(IPAddr.new('10.81.1.1'))
        expect(Address).to receive(:create).with('kontena', '10.81.1.1', address: IPAddr.new('10.81.1.1')).and_raise(Address::Conflict)

        expect(pool).to receive(:reserved_addresses).and_return([IPAddr.new('10.81.1.1')])
        expect(policy).to receive(:allocate_address).with(addresses - [IPAddr.new('10.81.1.1')]).and_return(IPAddr.new('10.81.1.2'))
        expect(Address).to receive(:create).with('kontena', '10.81.1.2', address: IPAddr.new('10.81.1.2')).and_return(addr)

        outcome = subject.run

        expect(outcome).to be_success, outcome.errors.inspect
        expect(outcome.result).to eq addr
        expect(outcome.result.address.to_cidr).to eq '10.81.1.2/16'
      end

    end

  end
end
