describe Addresses::Cleanup do
  before do
    allow_any_instance_of(NodeHelper).to receive(:node).and_return('1')
    allow_any_instance_of(PingHelper).to receive(:ping?).and_return(false)
  end

  context "for etcd with multiple reserved addresses", :etcd => true do
    before do
      etcd_server.load!(
        '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
        '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
        '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24', 'node' => '1' },
        '/kontena/ipam/addresses/test1/10.80.1.100' => { 'address' => '10.80.1.100/24', 'node' => '1' },
        '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
        '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' }
      )
    end

    context "With a single address string for the pool" do
      subject do
        described_class.new(
          etcd_index_upto: etcd_server.etcd_index,
          pool_id: 'test1',
          addresses: [
            '10.80.1.111/24',
          ],
        )
      end

      describe '#validate' do
        it 'accepts the arguments' do
          outcome = subject.validation_outcome

          expect(outcome).to be_success, subject.validation_outcome.errors.inspect
        end
      end
    end

    context "With a single address for the pool" do
      subject do
        described_class.new(
          etcd_index_upto: etcd_server.etcd_index,
          pool_id: 'test1',
          addresses: [
            IPAddr.new('10.80.1.111/24').to_host,
          ],
        )
      end

      describe '#validate' do
        it 'accepts the arguments' do
          outcome = subject.validation_outcome

          expect(outcome).to be_success, subject.validation_outcome.errors.inspect
        end
      end

      describe '#execute' do
        it 'removes only unused addresses owned by this node' do
          outcome = subject.run

          expect(outcome).to be_success, outcome.errors.inspect

          expect(etcd_server).to be_modified
          expect(etcd_server.nodes).to eq({
            '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
            '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
            '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24', 'node' => '1' },
            '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
            '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' },
          })
        end

        it 'removes no addresses owned by this node if they respond to ping' do
          expect(subject).to receive(:ping?).with(IPAddr.new('10.80.1.111/24')).and_return(true)
          outcome = subject.run

          expect(outcome).to be_success, outcome.errors.inspect

          expect(etcd_server).not_to be_modified
        end
      end
    end
  end
end
