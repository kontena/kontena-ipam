describe Etcd::FakeServer, :etcd => true do
  context 'for a simple tree' do
    before do
      etcd_server.load!(
        '/kontena/ipam/test/foo' => 'foo',
        '/kontena/ipam/test/bar' => 'bar',
      )
    end

    describe '#list' do
      it 'returns the initially loaded keys' do
        expect(etcd_server.list).to eq [
          '/kontena/ipam/',
          '/kontena/ipam/test/',
          '/kontena/ipam/test/bar',
          '/kontena/ipam/test/foo',
        ].to_set
      end
    end

    describe '#get' do
      it 'gets a node' do
          expect(etcd.get('/kontena/ipam/test/foo').value).to eq 'foo'
          expect(etcd.get('/kontena/ipam/test/bar').value).to eq 'bar'
      end

      it 'gets a directory' do
        expect(etcd.get('/kontena/ipam/test').directory?).to be true
        expect(etcd.get('/kontena/ipam/test').children.map{|node| node.key }.sort).to eq [
          '/kontena/ipam/test/bar',
          '/kontena/ipam/test/foo',
        ]
      end
    end

    describe '#set' do
      it 'creates a new node' do
        etcd.set('/kontena/ipam/test/quux', value: 'quux')

        expect(etcd.get('/kontena/ipam/test/quux').value).to eq 'quux'
      end

      it 'adds a new node to the parent directory' do
        etcd.set('/kontena/ipam/test/quux', value: 'quux')

        expect(etcd.get('/kontena/ipam/test/').children.map{|node| node.key }.sort).to eq [
          '/kontena/ipam/test/bar',
          '/kontena/ipam/test/foo',
          '/kontena/ipam/test/quux',
        ]
      end
    end

    describe '#delete' do
      it 'does not get a deleted node' do
        etcd.delete('/kontena/ipam/test/foo')
        expect{etcd.get('/kontena/ipam/test/foo')}.to raise_error(Etcd::KeyNotFound)
      end

      it 'does not list a deleted node' do
        etcd.delete('/kontena/ipam/test/foo')
        expect(etcd.get('/kontena/ipam/test').children.map{|node| node.key }.sort).to eq [
          '/kontena/ipam/test/bar',
        ]
      end
    end
  end

  context "for a nested tree" do
    before do
      etcd_server.load!(
        '/kontena/ipam/test/test1/children/childA' => { 'field' => "value 1A" },
        '/kontena/ipam/test/test1/children/childB' => { 'field' => "value 1B" },
        '/kontena/ipam/test/test2/children/childA' => { 'field' => "value 2A" },
        '/kontena/ipam/test/test2/children/childB' => { 'field' => "value 2B" },
      )
    end

    it "lists the nodes" do
      expect(etcd.get('/kontena/ipam/test/').children.map{|node| node.key }.sort).to eq [
        '/kontena/ipam/test/test1',
        '/kontena/ipam/test/test2',
      ]
    end
  end
end
