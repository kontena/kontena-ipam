describe EtcdModel do
  describe EtcdModel::Schema do
    it 'rejects a non-absolute path' do
      expect{described_class.new('test')}.to raise_error ArgumentError
    end

    it 'rejects a directory path' do
      expect{described_class.new('/kontena/ipam/test/:name/')}.to raise_error ArgumentError
    end

    it 'parses a simple path' do
      expect(described_class.new('/kontena/ipam/test/:name').path).to eq ['kontena', 'ipam', 'test', :name]
    end

    it 'parses a simple path with a sub-node' do
      expect(described_class.new('/kontena/ipam/test/:name/foo').path).to eq ['kontena', 'ipam', 'test', :name, 'foo']
    end

    it 'parses a complex path with two symbols' do
      expect(described_class.new('/kontena/ipam/test/:name/foo/:bar').path).to eq ['kontena', 'ipam', 'test', :name, 'foo', :bar]
    end

    context 'for a simple schema' do
      let :subject do
        described_class.new('/kontena/ipam/test/:name')
      end

      it 'renders the path for the class' do
        expect(subject.to_s).to eq '/kontena/ipam/test/:name'
      end

      it 'renders the path prefix for the class' do
        expect(subject.prefix()).to eq '/kontena/ipam/test/'
      end

      it 'renders the complete path prefix for the class' do
        expect(subject.prefix('test1')).to eq '/kontena/ipam/test/test1'
      end

      it 'fails the prefix if given too many arguments' do
        expect{subject.prefix('test1', 'test2')}.to raise_error ArgumentError
      end
    end
  end

  context 'a simple model' do
    class TestEtcd
      include EtcdModel
      include JSONModel

      etcd_path '/kontena/ipam/test/:name'
      json_attr :field, type: String

      attr_accessor :name
      attr_accessor :field
    end

    it 'initializes the etcd key instance variables' do
      expect{TestEtcd.new()}.to raise_error ArgumentError, "Missing key argument for :name"
      expect(TestEtcd.new('test').name).to eq 'test'
      expect{TestEtcd.new('test', 'extra')}.to raise_error ArgumentError, "Extra key arguments"
    end

    it 'initializes the JSON attribute instance variables' do
      expect(TestEtcd.new('test').field).to eq nil
      expect(TestEtcd.new('test', field: "value").field).to eq "value"
      expect{TestEtcd.new('test', notfield: false)}.to raise_error ArgumentError, "Extra JSON attr argument: :notfield"
    end

    it 'initializes the object with etcd key and JSON attrribute instance variables' do
      expect(TestEtcd.new('test', field: "value").name).to eq 'test'
    end

    it 'renders to path for the object' do
      expect(TestEtcd.new('test1').etcd_key).to eq '/kontena/ipam/test/test1'
    end

    context 'with only key values' do
      it 'compares the key' do
        expect(TestEtcd.new('test1') <=> TestEtcd.new('test2')).to eq(-1)
        expect(TestEtcd.new('test1') <=> TestEtcd.new('test1')).to eq(0)
        expect(TestEtcd.new('test2') <=> TestEtcd.new('test1')).to eq(1)
      end

      it 'sorts before values' do
        expect(TestEtcd.new('test1') <=> TestEtcd.new('test1', field: "value 1")).to eq(-1)
      end
    end

    context 'with key and attr values' do
      it 'compares the keys' do
        expect(TestEtcd.new('test1', field: "value") <=> TestEtcd.new('test2', field: "value")).to eq(-1)
        expect(TestEtcd.new('test1', field: "value") <=> TestEtcd.new('test1', field: "value")).to eq(0)
        expect(TestEtcd.new('test2', field: "value") <=> TestEtcd.new('test1', field: "value")).to eq(+1)
      end

      it 'compares the values with matching keys' do
        expect(TestEtcd.new('test1', field: "value 1") <=> TestEtcd.new('test1', field: "value 2")).to eq(-1)
        expect(TestEtcd.new('test1', field: "value 1") <=> TestEtcd.new('test1', field: "value 1")).to eq(0)
        expect(TestEtcd.new('test1', field: "value 2") <=> TestEtcd.new('test1', field: "value 1")).to eq(+1)
      end

      it 'sorts after missing values' do
        expect(TestEtcd.new('test1', field: "value") <=> TestEtcd.new('test1')).to eq(+1)
      end
    end

    describe '#mkdir' do
      it 'creates directory in etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/ipam/test/', dir: true, prevExist: false).and_call_original

        TestEtcd.mkdir()

        expect(etcd_server).to be_modified
        expect(etcd_server.logs).to eq [
          [:create, '/kontena/ipam/test/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/ipam/',
          '/kontena/ipam/test/',
        ])
      end

      it 'skips existing directories', :etcd => true do
        etcd_server.load!(
          '/kontena/ipam/test/' => nil,
        )

        expect(etcd).to receive(:set).with('/kontena/ipam/test/', dir: true, prevExist: false).and_call_original

        TestEtcd.mkdir()

        expect(etcd_server).to_not be_modified
      end

      it 'fails if given a full key', :etcd => true do
        expect{TestEtcd.mkdir('test')}.to raise_error(ArgumentError)

        expect(etcd_server).to_not be_modified
      end
    end

    describe '#get' do
      it 'rejects an empty key' do
        expect{ TestEtcd.get('') }.to raise_error(ArgumentError)
      end

      it 'returns nil if missing from etcd', :etcd => true do
        expect(etcd).to receive(:get).with('/kontena/ipam/test/test1').and_call_original

        expect(TestEtcd.get('test1')).to be_nil

        expect(etcd_server).to_not be_modified
        expect(etcd_server.list).to be_empty
      end

      it 'returns object loaded from etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/ipam/test/test1' => { 'field' => "value" }
        )
        expect(etcd).to receive(:get).with('/kontena/ipam/test/test1').and_call_original

        expect(TestEtcd.get('test1')).to eq TestEtcd.new('test1', field: "value")

        expect(etcd_server).to_not be_modified
      end

      it 'raises Invalid if the etcd node is a directory', :etcd => true do
        etcd_server.load!(
          '/kontena/ipam/test/test1/' => nil,
        )
        expect(etcd).to receive(:get).with('/kontena/ipam/test/test1').and_call_original

        expect{ TestEtcd.get('test1') }.to raise_error(TestEtcd::Invalid)
      end

      it 'raises Invalid if the etcd node is not JSON', :etcd => true do
        etcd_server.load!(
          '/kontena/ipam/test/test1' => 'asdf',
        )
        expect(etcd).to receive(:get).with('/kontena/ipam/test/test1').and_call_original

        expect{ TestEtcd.get('test1') }.to raise_error(TestEtcd::Invalid, /Invalid JSON value: \d+: unexpected token at 'asdf/)
      end

    end

    describe '#create' do
      it 'returns new object stored to etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/ipam/test/test1', prevExist: false, value: '{"field":"value"}').and_call_original

        expect(TestEtcd.create('test1', field: "value")).to eq TestEtcd.new('test1', field: "value")

        expect(etcd_server.logs).to eq [
          [:create, '/kontena/ipam/test/test1'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/ipam/',
          '/kontena/ipam/test/',
          '/kontena/ipam/test/test1',
        ])
        expect(etcd_server.nodes).to eq(
          '/kontena/ipam/test/test1' => {'field' => "value"}
        )
        expect(etcd_server).to be_modified
      end

      it 'raises conflict if object exists in etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/ipam/test/test1' => { 'field' => "value 1" }
        )

        expect(etcd).to receive(:set).with('/kontena/ipam/test/test1', prevExist: false, value: '{"field":"value 2"}').and_call_original

        expect{TestEtcd.create('test1', field: "value 2")}.to raise_error(TestEtcd::Conflict)

        expect(etcd_server).to_not be_modified
      end
    end

    describe '#create_or_get' do
      it 'returns new object stored to etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/ipam/test/test1', prevExist: false, value: '{"field":"value"}').and_call_original

        expect(TestEtcd.create_or_get('test1', field: "value")).to eq TestEtcd.new('test1', field: "value")

        expect(etcd_server.logs).to eq [
          [:create, '/kontena/ipam/test/test1'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/ipam/',
          '/kontena/ipam/test/',
          '/kontena/ipam/test/test1',
        ])
        expect(etcd_server.nodes).to eq(
          '/kontena/ipam/test/test1' => {'field' => "value"}
        )
        expect(etcd_server).to be_modified
      end

      it 'returns existing object loaded from etcd', :etcd => true do
        etcd_server.load!(
          '/kontena/ipam/test/test1' => { 'field' => "value 1" }
        )

        expect(etcd).to receive(:set).with('/kontena/ipam/test/test1', prevExist: false, value: '{"field":"value 2"}').and_call_original
        expect(etcd).to receive(:get).with('/kontena/ipam/test/test1').and_call_original

        expect(TestEtcd.create_or_get('test1', field: "value 2")).to eq TestEtcd.new('test1', field: "value 1")

        expect(etcd_server).to_not be_modified
      end

      it 'raises conflict if the world is a scary place', :etcd => true do
        etcd_server.load!(
          '/kontena/ipam/test/test1' => { 'field' => "value 1" }
        )

        # this is a create vs delete race
        expect(etcd).to receive(:set).with('/kontena/ipam/test/test1', prevExist: false, value: '{"field":"value"}').and_call_original
        expect(etcd).to receive(:get).with('/kontena/ipam/test/test1').and_raise(Etcd::KeyNotFound)

        expect{TestEtcd.create_or_get('test1', field: "value")}.to raise_error(TestEtcd::Conflict)

        expect(etcd_server).to_not be_modified
      end
    end

    it 'lists from etcd', :etcd => true do
      etcd_server.load!(
        '/kontena/ipam/test/test1' => { 'field' => "value 1" },
        '/kontena/ipam/test/test2' => { 'field' => "value 2" },
      )

      expect(etcd).to receive(:get).with('/kontena/ipam/test/').and_call_original

      expect(TestEtcd.list().sort).to eq [
        TestEtcd.new('test1', field: "value 1"),
        TestEtcd.new('test2', field: "value 2"),
      ]

      expect(etcd_server).to_not be_modified
    end

    it 'lists empty if directory is missing in etcd', :etcd => true do
      expect(etcd).to receive(:get).with('/kontena/ipam/test/').and_raise(Etcd::KeyNotFound)

      expect(TestEtcd.list()).to eq []

      expect(etcd_server).to_not be_modified
    end

    it 'deletes instance from etcd', :etcd => true do
      etcd_server.load!(
        '/kontena/ipam/test/test1' => { 'field' => "value 1" },
        '/kontena/ipam/test/test2' => { 'field' => "value 2" },
      )

      expect(etcd).to receive(:delete).with('/kontena/ipam/test/test1').and_call_original

      TestEtcd.new('test1').delete!

      expect(etcd_server.logs).to eq [
        [:delete, '/kontena/ipam/test/test1'],
      ]
      expect(etcd_server.list).to eq Set.new([
        '/kontena/ipam/',
        '/kontena/ipam/test/',
        '/kontena/ipam/test/test2',
      ])
      expect(etcd_server.nodes).to eq(
        '/kontena/ipam/test/test2' => {'field' => "value 2"},
      )
      expect(etcd_server).to be_modified
    end

    it 'deletes everything from etcd recursively', :etcd => true do
      etcd_server.load!(
        '/kontena/ipam/test/test1' => { 'field' => "value 1" },
        '/kontena/ipam/test/test2' => { 'field' => "value 2" },
      )

      expect(etcd).to receive(:delete).with('/kontena/ipam/test/', recursive: true).and_call_original

      TestEtcd.delete()

      expect(etcd_server.logs).to eq [
        [:delete, '/kontena/ipam/test/'],
      ]
      expect(etcd_server.list).to eq Set.new([
        '/kontena/ipam/',
      ])
      expect(etcd_server).to be_modified
    end

    it 'deletes instance from etcd', :etcd => true do
      etcd_server.load!(
        '/kontena/ipam/test/test1' => { 'field' => "value 1" },
        '/kontena/ipam/test/test2' => { 'field' => "value 2" },
      )

      expect(etcd).to receive(:delete).with('/kontena/ipam/test/test1', recursive: false).and_call_original

      TestEtcd.delete('test1')

      expect(etcd_server.logs).to eq [
        [:delete, '/kontena/ipam/test/test1'],
      ]
      expect(etcd_server.list).to eq Set.new([
        '/kontena/ipam/',
        '/kontena/ipam/test/',
        '/kontena/ipam/test/test2',
      ])
      expect(etcd_server.nodes).to eq(
        '/kontena/ipam/test/test2' => {'field' => "value 2"},
      )
      expect(etcd_server).to be_modified
    end
  end

  context 'for a complex model' do
    class TestEtcdChild
      include EtcdModel
      include JSONModel

      etcd_path '/kontena/ipam/test/:parent/children/:name'
      json_attr :field, type: String

      attr_accessor :parent, :name
      attr_accessor :field
    end

    it 'renders the path for the class' do
      expect(TestEtcdChild.etcd_schema.to_s).to eq '/kontena/ipam/test/:parent/children/:name'
    end

    it 'renders the path prefix for the class' do
      expect(TestEtcdChild.etcd_schema.prefix()).to eq '/kontena/ipam/test/'
      expect(TestEtcdChild.etcd_schema.prefix('parent1')).to eq '/kontena/ipam/test/parent1/children/'
    end

    it 'renders to path for the object' do
      expect(TestEtcdChild.new('parent1', 'child1').etcd_key).to eq '/kontena/ipam/test/parent1/children/child1'
    end

    describe '#mkdir' do
      it 'creates parent directory in etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/ipam/test/', dir: true, prevExist: false).and_call_original

        TestEtcdChild.mkdir()

        expect(etcd_server.logs).to eq [
          [:create, '/kontena/ipam/test/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/ipam/',
          '/kontena/ipam/test/',
        ])
        expect(etcd_server).to be_modified
      end

      it 'creates child directory in etcd', :etcd => true do
        expect(etcd).to receive(:set).with('/kontena/ipam/test/parent/children/', dir: true, prevExist: false).and_call_original

        TestEtcdChild.mkdir('parent')

        expect(etcd_server.logs).to eq [
          [:create, '/kontena/ipam/test/parent/children/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/ipam/',
          '/kontena/ipam/test/',
          '/kontena/ipam/test/parent/',
          '/kontena/ipam/test/parent/children/',
        ])
        expect(etcd_server).to be_modified
      end

      it 'fails if given a full key' do
        expect{TestEtcdChild.mkdir('parent', 'child')}.to raise_error(ArgumentError)
      end
    end

    context 'with etcd having nodes' do
      before do
        etcd_server.load!(
          '/kontena/ipam/test/test1/children/childA' => { 'field' => "value 1A" },
          '/kontena/ipam/test/test1/children/childB' => { 'field' => "value 1B" },
          '/kontena/ipam/test/test2/children/childA' => { 'field' => "value 2A" },
          '/kontena/ipam/test/test2/children/childB' => { 'field' => "value 2B" },
        )
      end

      it 'lists recursively from etcd', :etcd => true do
        expect(TestEtcdChild.list().sort).to eq [
          TestEtcdChild.new('test1', 'childA', field: "value 1A"),
          TestEtcdChild.new('test1', 'childB', field: "value 1B"),
          TestEtcdChild.new('test2', 'childA', field: "value 2A"),
          TestEtcdChild.new('test2', 'childB', field: "value 2B"),
        ]

        expect(etcd_server).to_not be_modified
      end

      it 'lists etcd', :etcd => true do
        expect(TestEtcdChild.list('test1').sort).to eq [
          TestEtcdChild.new('test1', 'childA', field: "value 1A"),
          TestEtcdChild.new('test1', 'childB', field: "value 1B"),
        ]

        expect(etcd_server).to_not be_modified
      end

      it 'deletes instance from etcd', :etcd => true do
        expect(etcd).to receive(:delete).with('/kontena/ipam/test/test1/children/childA').and_call_original

        TestEtcdChild.new('test1', 'childA').delete!

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/ipam/test/test1/children/childA'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/ipam/',
          '/kontena/ipam/test/',
          '/kontena/ipam/test/test1/',
          '/kontena/ipam/test/test1/children/',
          '/kontena/ipam/test/test1/children/childB',
          '/kontena/ipam/test/test2/',
          '/kontena/ipam/test/test2/children/',
          '/kontena/ipam/test/test2/children/childA',
          '/kontena/ipam/test/test2/children/childB',
        ])
        expect(etcd_server).to be_modified
      end

      it 'deletes one set of instances', :etcd => true do
        expect(etcd).to receive(:delete).with('/kontena/ipam/test/test1/children/', recursive: true).and_call_original

        TestEtcdChild.delete('test1')

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/ipam/test/test1/children/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/ipam/',
          '/kontena/ipam/test/',
          '/kontena/ipam/test/test1/',
          '/kontena/ipam/test/test2/',
          '/kontena/ipam/test/test2/children/',
          '/kontena/ipam/test/test2/children/childA',
          '/kontena/ipam/test/test2/children/childB',
        ])
        expect(etcd_server).to be_modified
      end

      it 'deletes everything from etcd recursively', :etcd => true do
        expect(etcd).to receive(:delete).with('/kontena/ipam/test/', recursive: true).and_call_original

        TestEtcdChild.delete()

        expect(etcd_server.logs).to eq [
          [:delete, '/kontena/ipam/test/'],
        ]
        expect(etcd_server.list).to eq Set.new([
          '/kontena/ipam/',
        ])
        expect(etcd_server).to be_modified
      end
    end

    it 'fails if trying to delete with an invalid value' do
      expect{TestEtcdChild.delete(nil)}.to raise_error ArgumentError
      expect{TestEtcdChild.delete("")}.to raise_error ArgumentError
    end
  end
end
