describe EtcdModel do
  describe EtcdModel::Schema do
    it 'rejects a non-absolute path' do
      expect{described_class.new('test')}.to raise_error ArgumentError
    end

    it 'rejects a directory path' do
      expect{described_class.new('/test/:name/')}.to raise_error ArgumentError
    end

    it 'parses a simple path' do
      expect(described_class.new('/test/:name').path).to eq ['test', :name]
    end

    it 'parses a simple path with a sub-node' do
      expect(described_class.new('/test/:name/foo').path).to eq ['test', :name, 'foo']
    end

    it 'parses a complex path with two symbols' do
      expect(described_class.new('/test/:name/foo/:bar').path).to eq ['test', :name, 'foo', :bar]
    end

    context 'for a simple schema' do
      let :subject do
        described_class.new('/test/:name')
      end

      it 'renders the path for the class' do
        expect(subject.to_s).to eq '/test/:name'
      end

      it 'renders the path prefix for the class' do
        expect(subject.prefix()).to eq '/test/'
      end

      it 'renders the complete path prefix for the class' do
        expect(subject.prefix('test1')).to eq '/test/test1'
      end

      it 'fails the prefix if given too many arguments' do
        expect{subject.prefix('test1', 'test2')}.to raise_error ArgumentError
      end
    end
  end

  let :etcd do
    instance_double(EtcdClient)
  end

  before do
    EtcdModel.etcd = etcd
  end

  context 'a simple model' do
    class TestEtcd
      include EtcdModel
      include JSONModel

      etcd_path '/test/:name'
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
      expect(TestEtcd.new('test1').etcd_key).to eq '/test/test1'
    end

    context 'with only key values' do
      it 'compares equal' do
        expect(TestEtcd.new('test1')).to eq TestEtcd.new('test1')
      end

      it 'compares unequal' do
        expect(TestEtcd.new('test1')).to_not eq TestEtcd.new('test1', field: "value 1")
        expect(TestEtcd.new('test1')).to_not eq TestEtcd.new('test2')
      end
    end

    context 'with key and attr values' do
      it 'compares equal' do
        expect(TestEtcd.new('test1', field: "value 1")).to eq TestEtcd.new('test1', field: "value 1")
      end

      it 'compares unequal' do
        expect(TestEtcd.new('test1', field: "value 1")).to_not eq TestEtcd.new('test1')
        expect(TestEtcd.new('test1', field: "value 1")).to_not eq TestEtcd.new('test1', field: "value 2")
        expect(TestEtcd.new('test1', field: "value 1")).to_not eq TestEtcd.new('test2')
        expect(TestEtcd.new('test1', field: "value 1")).to_not eq TestEtcd.new('test2', field: "value 2")
      end
    end

    describe '#mkdir' do
      it 'creates directory in etcd' do
        expect(etcd).to receive(:set).with('/test/', dir: true, prevExist: false)

        TestEtcd.mkdir()
      end

      it 'fails if given a full key' do
        expect{TestEtcd.mkdir('test')}.to raise_error(ArgumentError)
      end
    end

    describe '#get' do
      it 'returns nil if missing from etcd' do
        expect(etcd).to receive(:get).with('/test/test1').and_raise(Etcd::KeyNotFound)

        expect(TestEtcd.get('test1')).to be_nil
      end

      it 'returns object loaded from etcd' do
        expect(etcd).to receive(:get).with('/test/test1').and_return(instance_double(Etcd::Response, value: '{"field":"value"}'))

        expect(TestEtcd.get('test1')).to eq TestEtcd.new('test1', field: "value")
      end
    end

    describe '#create' do
      it 'returns new object stored to etcd' do
        expect(etcd).to receive(:set).with('/test/test1', prevExist: false, value: '{"field":"value"}')

        expect(TestEtcd.create('test1', field: "value")).to eq TestEtcd.new('test1', field: "value")
      end

      it 'raises conflict if object exists in etcd' do
        expect(etcd).to receive(:set).with('/test/test1', prevExist: false, value: '{"field":"value"}').and_raise(Etcd::NodeExist)

        expect{TestEtcd.create('test1', field: "value")}.to raise_error(TestEtcd::Conflict)
      end
    end

    describe '#create_or_get' do
      it 'returns new object stored to etcd' do
        expect(etcd).to receive(:set).with('/test/test1', prevExist: false, value: '{"field":"value"}')

        expect(TestEtcd.create_or_get('test1', field: "value")).to eq TestEtcd.new('test1', field: "value")
      end

      it 'returns existing object loaded from etcd' do
        expect(etcd).to receive(:set).with('/test/test1', prevExist: false, value: '{"field":"value 1"}').and_raise(Etcd::NodeExist)
        expect(etcd).to receive(:get).with('/test/test1').and_return(instance_double(Etcd::Response, value: '{"field":"value 2"}'))

        expect(TestEtcd.create_or_get('test1', field: "value 1")).to eq TestEtcd.new('test1', field: "value 2")
      end

      it 'raises conflict if the world is a scary place' do
        # this is a create vs delete race
        expect(etcd).to receive(:set).with('/test/test1', prevExist: false, value: '{"field":"value"}').and_raise(Etcd::NodeExist)
        expect(etcd).to receive(:get).with('/test/test1').and_raise(Etcd::KeyNotFound)

        expect{TestEtcd.create_or_get('test1', field: "value")}.to raise_error(TestEtcd::Conflict)
      end
    end

    it 'lists from etcd' do
      expect(etcd).to receive(:get).with('/test/').and_return(instance_double(Etcd::Response, children: [
        instance_double(Etcd::Node, key: '/test/test1', value: '{"field":"value 1"}', directory?: false),
        instance_double(Etcd::Node, key: '/test/test2', value: '{"field":"value 2"}', directory?: false),

      ]))

      expect(TestEtcd.list()).to eq [
        TestEtcd.new('test1', field: "value 1"),
        TestEtcd.new('test2', field: "value 2"),
      ]
    end

    it 'lists empty if directory is missing in etcd' do
      expect(etcd).to receive(:get).with('/test/').and_raise(Etcd::KeyNotFound)

      expect(TestEtcd.list()).to eq []
    end

    it 'deletes instance from etcd' do
      expect(etcd).to receive(:delete).with('/test/test1')

      TestEtcd.new('test1').delete!
    end

    it 'deletes everything from etcd recursively' do
      expect(etcd).to receive(:delete).with('/test/', recursive: true)

      TestEtcd.delete()
    end

    it 'deletes instance from etcd' do
      expect(etcd).to receive(:delete).with('/test/test1', recursive: false)

      TestEtcd.delete('test1')
    end
  end

  context 'for a complex model' do
    class TestEtcdChild
      include EtcdModel
      include JSONModel

      etcd_path '/test/:parent/children/:name'
      json_attr :field, type: String

      attr_accessor :parent, :name
      attr_accessor :field
    end

    it 'renders the path for the class' do
      expect(TestEtcdChild.etcd_schema.to_s).to eq '/test/:parent/children/:name'
    end

    it 'renders the path prefix for the class' do
      expect(TestEtcdChild.etcd_schema.prefix()).to eq '/test/'
      expect(TestEtcdChild.etcd_schema.prefix('parent1')).to eq '/test/parent1/children/'
    end

    it 'renders to path for the object' do
      expect(TestEtcdChild.new('parent1', 'child1').etcd_key).to eq '/test/parent1/children/child1'
    end

    describe '#mkdir' do
      it 'creates parent directory in etcd' do
        expect(etcd).to receive(:set).with('/test/', dir: true, prevExist: false)

        TestEtcdChild.mkdir()
      end

      it 'creates child directory in etcd' do
        expect(etcd).to receive(:set).with('/test/parent/children/', dir: true, prevExist: false)

        TestEtcdChild.mkdir('parent')
      end

      it 'fails if given a full key' do
        expect{TestEtcdChild.mkdir('parent', 'child')}.to raise_error(ArgumentError)
      end
    end

    it 'lists recursively from etcd' do
      expect(etcd).to receive(:get).with('/test/').and_return(instance_double(Etcd::Response, children: [
        instance_double(Etcd::Node, key: '/test/test1', directory?: true),
        instance_double(Etcd::Node, key: '/test/test2', directory?: true),
      ]))
      expect(etcd).to receive(:get).with('/test/test1/children/').and_return(instance_double(Etcd::Response, children: [
        instance_double(Etcd::Node, key: '/test/test1/children/childA', value: '{"field":"value 1A"}', directory?: false),
        instance_double(Etcd::Node, key: '/test/test1/children/childB', value: '{"field":"value 1B"}', directory?: false),
      ]))
      expect(etcd).to receive(:get).with('/test/test2/children/').and_return(instance_double(Etcd::Response, children: [
        instance_double(Etcd::Node, key: '/test/test2/children/childA', value: '{"field":"value 2A"}', directory?: false),
        instance_double(Etcd::Node, key: '/test/test2/children/childB', value: '{"field":"value 2B"}', directory?: false),
      ]))

      expect(TestEtcdChild.list()).to eq [
        TestEtcdChild.new('test1', 'childA', field: "value 1A"),
        TestEtcdChild.new('test1', 'childB', field: "value 1B"),
        TestEtcdChild.new('test2', 'childA', field: "value 2A"),
        TestEtcdChild.new('test2', 'childB', field: "value 2B"),
      ]
    end

    it 'lists etcd' do
      expect(etcd).to receive(:get).with('/test/test1/children/').and_return(instance_double(Etcd::Response, children: [
        instance_double(Etcd::Node, key: '/test/test1/children/childA', value: '{"field":"value 1A"}', directory?: false),
        instance_double(Etcd::Node, key: '/test/test1/children/childB', value: '{"field":"value 1B"}', directory?: false),
      ]))

      expect(TestEtcdChild.list('test1')).to eq [
        TestEtcdChild.new('test1', 'childA', field: "value 1A"),
        TestEtcdChild.new('test1', 'childB', field: "value 1B"),
      ]
    end

    it 'deletes instance from etcd' do
      expect(etcd).to receive(:delete).with('/test/test1/children/test2')

      TestEtcdChild.new('test1', 'test2').delete!
    end

    it 'deletes one set of instances' do
      expect(etcd).to receive(:delete).with('/test/test1/children/', recursive: true)

      TestEtcdChild.delete('test1')
    end

    it 'deletes everything from etcd recursively' do
      expect(etcd).to receive(:delete).with('/test/', recursive: true)

      TestEtcdChild.delete()
    end

    it 'fails if trying to delete with an invalid value' do
      expect{TestEtcdChild.delete(nil)}.to raise_error ArgumentError
      expect{TestEtcdChild.delete("")}.to raise_error ArgumentError
    end
  end
end
