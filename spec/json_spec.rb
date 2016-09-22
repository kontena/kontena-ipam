describe JSONModel do
  class TestJSON
    include JSONModel

    json_attr :str, omitnil: true
    json_attr :int, name: 'number', omitnil: true
    json_attr :bool, default: false
    json_attr :ipaddr, type: IPAddr

    attr_accessor :str, :int, :bool, :ipaddr

    def initialize(**attrs)
      initialize_json(**attrs)
    end

    def ==(other)
      self.eq_json(other)
    end
  end

  it 'initializes default attributes' do
    subject = TestJSON.new()

    expect(subject.str).to be_nil
    expect(subject.int).to be_nil
    expect(subject.bool).to be false
    expect(subject.ipaddr).to be_nil
  end

  it 'initializes json attributes' do
    subject = TestJSON.new(str: "string", int: 2, bool: true, ipaddr: IPAddr.new("127.0.0.1"))

    expect(subject.str).to eq "string"
    expect(subject.int).to eq 2
    expect(subject.bool).to eq true
    expect(subject.ipaddr).to eq IPAddr.new("127.0.0.1")
  end

  it 'compares equal' do
    expect(TestJSON.new().eq_json TestJSON.new()).to be true
    expect(TestJSON.new(str: "string").eq_json TestJSON.new(str: "string")).to be true
    expect(TestJSON.new(str: "string", int: 5).eq_json TestJSON.new(str: "string", int: 5)).to be true
    expect(TestJSON.new(str: "string", ipaddr: IPAddr.new("127.0.0.1")).eq_json TestJSON.new(str: "string", ipaddr: IPAddr.new("127.0.0.1"))).to be true
  end

  it 'compares unequal' do
    expect(TestJSON.new(str: "string").eq_json TestJSON.new()).to be false
    expect(TestJSON.new(str: "string").eq_json TestJSON.new(str: "different")).to be false
    expect(TestJSON.new(str: "string").eq_json TestJSON.new(int: 5)).to be false
    expect(TestJSON.new(str: "test", ipaddr: IPAddr.new("127.0.0.1")).eq_json TestJSON.new(str: "test", ipaddr: IPAddr.new("127.0.0.2"))).to be false
  end

  it 'encodes to json with default values' do
    expect(JSON.parse(TestJSON.new().to_json)).to eq({'bool' => false, 'ipaddr' => nil})
  end

  it 'encodes to json with simple value' do
    expect(JSON.parse(TestJSON.new(str: "test").to_json)).to eq({'str' => "test", 'bool' => false, 'ipaddr' => nil})
  end

  it 'encodes to json with name' do
    expect(JSON.parse(TestJSON.new(int: 5).to_json)).to eq({'number' => 5, 'bool' => false, 'ipaddr' => nil})
  end

  it 'encodes to json with overriden default value' do
    expect(JSON.parse(TestJSON.new(str: "test", int: 5, bool: true).to_json)).to eq({'str' => "test", 'number' => 5, 'bool' => true, 'ipaddr' => nil})
  end

  it 'encodes to json with type value #to_json' do
   expect(JSON.parse(TestJSON.new(ipaddr: IPAddr.new("127.0.0.1")).to_json)).to eq({'bool' => false, 'ipaddr' => "127.0.0.1"})
 end

  it 'decodes from json with default values' do
    expect(TestJSON.from_json('{}')).to eq TestJSON.new()
  end

  it 'decodes from json' do
    expect(TestJSON.from_json('{"str": "test"}')).to eq TestJSON.new(str: "test")
    expect(TestJSON.from_json('{"bool": true}')).to eq TestJSON.new(bool: true)
    expect(TestJSON.from_json('{"bool": false}')).to eq TestJSON.new()
  end

  it 'decodes from json with name' do
    expect(TestJSON.from_json('{"number": 5}')).to eq TestJSON.new(int: 5)
  end

  it 'decodes with type' do
    expect(TestJSON.from_json('{"ipaddr": "127.0.0.1"}')).to eq TestJSON.new(ipaddr: IPAddr.new("127.0.0.1"))
    expect(TestJSON.from_json('{"ipaddr": "127.0.0.1/8"}')).to eq TestJSON.new(ipaddr: IPAddr.new("127.0.0.1/8"))
    expect(TestJSON.from_json('{"ipaddr": "127.0.0.1/8"}').ipaddr.to_cidr).to eq "127.0.0.1/8"

  end

  it 'ignores unknown attributes' do
    expect(TestJSON.from_json('{"foo": "bar"}')).to eq TestJSON.new()
    expect(TestJSON.from_json('{"str": "test", "foo": "bar"}')).to eq TestJSON.new(str: "test")
  end
end
