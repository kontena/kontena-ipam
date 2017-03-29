describe Commands::Cleanup do
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

    context "When scanning Docker with no active containers" do
      subject do
        described_class.parse([''])
      end

      before do
        expect(subject).to receive(:docker_scan).and_yield('test1', [])
      end

      it "Removes all unused addresses owned by this node" do
        expect{subject.execute}.to_not raise_error

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
          '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24', 'node' => '1' },
          '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
        })
      end
    end

    context "With one active Docker container" do
      subject do
        described_class.parse([''])
      end

      before do
        expect(subject).to receive(:docker_scan).and_yield('test1', [
          IPAddr.new('10.80.1.111/24'),
        ])
      end

      it "Only removes unused addresses owned by this node" do
        expect{subject.execute}.to_not raise_error

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
          '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24', 'node' => '1' },
          '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
          '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' },
        })
      end
    end

    context "With one concurrent address allocation" do
      subject do
        described_class.parse(['--quiesce-sleep=10'])
      end

      before do
        expect(subject).to receive(:sleep) {
          # simulate a concurrent address request during the sleep period, which does not yet show up in the scan
          etcd.set '/kontena/ipam/addresses/test1/10.80.1.112', value: { 'address' => '10.80.1.112/24', 'node' => '1' }.to_json
        }

        expect(subject).to receive(:docker_scan).and_yield('test1', [
          IPAddr.new('10.80.1.111/24'),
        ])
      end

      it "Only removes unused addresses owned by this node" do
        expect{subject.execute}.to_not raise_error

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
          '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24', 'node' => '1' },
          '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
          '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' },
          '/kontena/ipam/addresses/test1/10.80.1.112' => { 'address' => '10.80.1.112/24', 'node' => '1' },
        })
      end
    end

    context "With one pending address allocation" do
      subject do
        described_class.parse(['--quiesce-sleep=10'])
      end

      before do
        # simulate an in-progress address request during the cleanup operation
        etcd.set '/kontena/ipam/addresses/test1/10.80.1.112', value: { 'address' => '10.80.1.112/24', 'node' => '1' }.to_json

        expect(subject).to receive(:sleep) {
          # the in-progress address request completes
        }

        expect(subject).to receive(:docker_scan).and_yield('test1', [
          IPAddr.new('10.80.1.111/24'),
          IPAddr.new('10.80.1.112/24'),
        ])
      end

      it "Only removes unused addresses owned by this node" do
        expect{subject.execute}.to_not raise_error

        expect(etcd_server).to be_modified
        expect(etcd_server.nodes).to eq({
          '/kontena/ipam/subnets/10.80.1.0' => { 'address' => '10.80.1.0/24' },
          '/kontena/ipam/pools/test1' => { 'subnet' => '10.80.1.0/24', 'gateway' => '10.80.1.1/24' },
          '/kontena/ipam/addresses/test1/10.80.1.1' => { 'address' => '10.80.1.1/24', 'node' => '1' },
          '/kontena/ipam/addresses/test1/10.80.1.200' => { 'address' => '10.80.1.200/24', 'node' => '2' },
          '/kontena/ipam/addresses/test1/10.80.1.111' => { 'address' => '10.80.1.111/24', 'node' => '1' },
          '/kontena/ipam/addresses/test1/10.80.1.112' => { 'address' => '10.80.1.112/24', 'node' => '1' },
        })
      end
    end

  end
end
