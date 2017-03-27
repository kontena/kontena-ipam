describe Addresses::Release do
  before do
    allow_any_instance_of(IPAddr).to receive(:ping?).and_return(false)
  end

  describe '#validate' do
    it 'rejects a missing pool_id' do
      subject = described_class.new()

      outcome = subject.validation_outcome

      expect(outcome).to_not be_success
      expect(outcome.errors.symbolic[:pool_id]).to eq :required
    end

    it 'rejects an missing address' do
      subject = described_class.new(pool_id: 'kontena')

      outcome = subject.validation_outcome

      expect(outcome).to_not be_success
      expect(outcome.errors.symbolic[:address]).to eq :required
    end

    it 'rejects an invalid address' do
      subject = described_class.new(pool_id: 'kontena', address: 'xxx')

      outcome = subject.validation_outcome

      expect(outcome).to_not be_success
      expect(outcome.errors.symbolic[:address]).to eq :invalid
    end

    it 'rejects an unknown pool_id' do
      expect(AddressPool).to receive(:get).with('kontena').and_return(nil)

      subject = described_class.new(pool_id: 'kontena', address: '10.80.0.1')

      outcome = subject.validation_outcome

      expect(outcome).to_not be_success
      expect(outcome.errors.symbolic[:pool_id]).to eq(:not_found), subject.validation_outcome.errors.inspect
    end

    it 'rejects an alien address' do
      expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16')))

      subject = described_class.new(pool_id: 'kontena', address: '10.81.0.1')

      outcome = subject.validation_outcome

      expect(outcome).to_not be_success
      expect(outcome.errors.symbolic[:address]).to eq :out_of_pool
    end

    it 'accepts an existing pool and valid ddress' do
      expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16')))

      subject = described_class.new(pool_id: 'kontena', address: '10.80.0.1')

      outcome = subject.validation_outcome

      expect(outcome).to be_success, subject.validation_outcome.errors.inspect
    end
  end

  describe '#execute' do
    context 'releasing a pool address' do
      let :pool do
        AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16'), gateway: IPAddr.new('10.80.0.1/16'))
      end

      let :address do
        Address.new('kontena', '10.80.0.2', address: pool.subnet.subnet_addr('10.80.0.2'))
      end

      let :subject do
        described_class.new(pool_id: 'kontena', address: '10.80.0.2')
      end

      let :gateway do
        Address.new('kontena', '10.80.0.1', address: pool.subnet.subnet_addr('10.80.0.1'))
      end

      before do
        expect(AddressPool).to receive(:get).with('kontena').and_return(pool)
      end

      it 'deletes the etcd node' do
        expect(pool).to receive(:get_address).with(IPAddr.new('10.80.0.2')).and_return(address)
        expect(address).to receive(:delete!)

        outcome = subject.run

        expect(outcome).to be_success
      end

      it 'does not delete gateway address' do
        expect(pool).to receive(:get_address).with(IPAddr.new('10.80.0.1')).and_return(gateway)
        expect(gateway).not_to receive(:delete!)

        subject = described_class.new(pool_id: 'kontena', address: '10.80.0.1')
        outcome = subject.run

        expect(outcome).to be_success
      end

      it 'does not delete address which still responds to ping' do
        expect(pool).to receive(:get_address).with(IPAddr.new('10.80.0.2')).and_return(address)
        expect(address.address).to receive(:ping?).and_return(true)
        expect(address).not_to receive(:delete!)

        outcome = subject.run

        expect(outcome).to be_success
      end
    end
  end
end
