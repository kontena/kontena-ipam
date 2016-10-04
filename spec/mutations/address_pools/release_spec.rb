describe AddressPools::Release do
  describe '#validate' do
    it 'rejects a missing network' do
      subject = described_class.new()

      expect(subject).to have_errors
    end

    it 'accepts an existing network' do
      pool = instance_double(AddressPool, id: 'kontena', subnet: IPAddr.new('10.80.0.0/16'), gateway: IPAddr.new('10.80.0.1/16'))
      expect(AddressPool).to receive(:get).with('kontena').and_return(pool)
      expect(pool).to receive(:list_addresses).and_return([double(pool: pool, id: '10.80.0.1', address: IPAddr.new('10.80.0.1/16'))])
      subject = described_class.new(pool_id: 'kontena')

      expect(subject).not_to have_errors, subject.validation_outcome.errors.inspect
    end

    it 'rejects an unknown network' do
      expect(AddressPool).to receive(:get).with('kontena').and_return(nil)

      subject = described_class.new(pool_id: 'kontena')

      outcome = subject.validation_outcome

      expect(outcome).to_not be_success
      expect(outcome.errors.symbolic[:pool_id]).to eq :notfound
    end

    it 'rejects a network with reserved addresses' do
      pool = instance_double(AddressPool, id: 'kontena', subnet: IPAddr.new('10.80.0.0/16'), gateway: IPAddr.new('10.80.0.1/16'))
      expect(AddressPool).to receive(:get).with('kontena').and_return(pool)
      expect(pool).to receive(:list_addresses)
        .and_return(
          [
            double(pool: pool, id: '10.80.0.1', address: IPAddr.new('10.80.0.1/16')),
            double(pool: pool, id: '10.80.0.2', address: IPAddr.new('10.80.0.2/16'))
          ]
        )

      subject = described_class.new(pool_id: 'kontena')

      outcome = subject.validation_outcome

      expect(outcome).to_not be_success
      expect(outcome.errors.symbolic[:pool_id]).to eq :reserved_addresses
    end
  end

  describe '#execute' do
    context 'releasing a single pool' do
      let :pool do
        AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16'), gateway: IPAddr.new('10.80.0.1/16'))
      end

      before do
        expect(AddressPool).to receive(:get).with('kontena').and_return(pool)
        expect(pool).to receive(:list_addresses).and_return([double(pool: pool, id: '10.80.0.1', address: IPAddr.new('10.80.0.1/16'))])
      end

      it 'deletes the etcd node' do
          subject = described_class.new(pool_id: 'kontena')

          expect(pool).to receive(:delete!)

          outcome = subject.run

          expect(outcome).to be_success
      end
    end
  end
end
