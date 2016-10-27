describe AddressPools::Cleanup do
  before do
    allow_any_instance_of(NodeHelper).to receive(:node).and_return('somehost')
  end

  describe '#execute' do
    context 'no adresspool' do

    end

    context 'for a single pool not in use' do
      let :pool do
        AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16'))
      end

      before do
        expect(AddressPool).to receive(:list).and_return([pool])
        expect(PoolNode).to receive(:list).with('kontena').and_return([])
      end

      subject do
        described_class.new()
      end

      it 'releases the PoolNode' do
        expect(pool).to receive(:delete!)

        outcome = subject.run

        expect(outcome).to be_success
      end
    end

    context 'for a single pool that is in use' do
      let :pool do
        AddressPool.new('kontena', subnet: IPAddr.new('10.80.0.0/16'))
      end

      before do
        expect(AddressPool).to receive(:list).and_return([pool])
        expect(PoolNode).to receive(:list).with('kontena').and_return([
          PoolNode.new('kontena', 'testhost'),
        ])
      end

      subject do
        described_class.new()
      end

      it 'releases the PoolNode' do
        expect(pool).to_not receive(:delete!)

        outcome = subject.run

        expect(outcome).to be_success
      end
    end
  end
end
