describe AddressPools::Release do
  before do
    allow_any_instance_of(NodeHelper).to receive(:node).and_return('somehost')
  end

  describe '#validate' do
    it 'rejects a missing network' do
      subject = described_class.new()

      expect(subject).to have_errors
    end

    it 'accepts an existing network' do
      expect(AddressPool).to receive(:get).with('kontena').and_return(AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16')))

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
  end

  describe '#execute' do
    context 'releasing a single pool' do
      let :pool do
        AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16'))
      end

      before do
        expect(AddressPool).to receive(:get).with('kontena').and_return(pool)
      end

      it 'releases the PoolNode and skips the pool delete if still in use' do
        subject = described_class.new(pool_id: 'kontena')

        expect(pool).to receive(:release!)
        expect(pool).to receive(:delete!).and_raise(PoolNode::Conflict)

        outcome = subject.run

        expect(outcome).to be_success
      end

      it 'releases the PoolNode and deletes the pool if not in use anymore' do
        subject = described_class.new(pool_id: 'kontena')

        expect(pool).to receive(:release!)
        expect(pool).to receive(:delete!)

        outcome = subject.run

        expect(outcome).to be_success
      end
    end
  end
end
