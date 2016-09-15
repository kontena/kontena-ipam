
describe Addresses::Request do

  let(:etcd) do
    double()
  end

  before(:each) do
    $etcd = etcd
  end

  describe '#validate' do
    it 'errors when pool no found' do
      expect(etcd).to receive(:get).with('/kontena/ipam/pools/not_found').and_raise(Etcd::KeyNotFound)

      subject = described_class.new(pool_id: 'not_found')

      expect(subject.has_errors?).to be_truthy
    end

    it 'errors when address not in pool range' do
      expect(etcd).to receive(:get)
        .with('/kontena/ipam/pools/foo')
        .and_return(double(value: '10.81.0.0/16'))

      subject = described_class.new(pool_id: 'foo', address: '10.99.100.100')

      expect(subject.has_errors?).to be_truthy
    end

    it 'retrives pool when found' do
      value = double(value: '10.81.0.0/16')
      expect(etcd).to receive(:get).with('/kontena/ipam/pools/found').and_return(value)

      subject = described_class.new(pool_id: 'found')

      expect(subject.has_errors?).to be_falsey
      expect(subject.instance_variable_get(:@pool)).to eq('10.81.0.0/16')
    end

    it 'validates address format if given' do
      value = double(value: '10.81.0.0/16')
      expect(etcd).to receive(:get).with('/kontena/ipam/pools/foo').and_return(value)
      subject = described_class.new(pool_id: 'foo', address: 'fdfdfds')
      expect(subject.has_errors?).to be_truthy
    end

  end

  describe '#execute' do

    before(:each) do
      allow_any_instance_of(described_class).to receive(:validate)
    end

    it 'reserves given address if available' do
      expect(etcd).to receive(:set)
        .with('/kontena/ipam/addresses/pool/10.81.100.100', {:value=>"10.81.100.100"})

      subject = described_class.new(pool_id: 'pool', address: '10.81.100.100')
      expect(subject).to receive(:available_addresses)
        .and_return(IPAddr.new('10.81.0.0/16').to_range.to_a)
      subject.instance_variable_set(:@pool, '10.81.0.0/16')

      expect(subject.run.result).to eq('10.81.100.100/16')

    end

    it 'errors if given address not available' do
      subject = described_class.new(pool_id: 'pool', address: '10.81.100.100')
      available = IPAddr.new('10.81.0.0/16').to_range.to_a
      available.delete(IPAddr.new('10.81.100.100/16'))

      expect(subject).to receive(:available_addresses).and_return(available)
      subject.instance_variable_set(:@pool, '10.81.0.0/16')

      expect(subject.run.success?).to be_falsey
    end

    it 'reserves random address if address not given' do
      expect(etcd).to receive(:set)

      subject = described_class.new(pool_id: 'pool')
      expect(subject).to receive(:available_addresses)
        .and_return(IPAddr.new('10.81.0.0/16').to_range.to_a)
      subject.instance_variable_set(:@pool, '10.81.0.0/16')

      expect(subject.run.result).not_to be_nil

    end

  end


  describe '#reserved_addresses' do

    before(:each) do
      allow_any_instance_of(described_class).to receive(:validate)
    end

    it 'returns all reserved addresses' do
      subject = described_class.new(pool_id: 'pool')
      expected_addresses = ['10.81.1.1', '10.81.1.1']
      expect(etcd).to receive(:get).with('/kontena/ipam/addresses/pool/')
        .and_return(double(children: [
          double({value: expected_addresses[0]}),
          double({value: expected_addresses[1]})
          ]))
      expect(subject.reserved_addresses).to eq(expected_addresses)
    end

  end

  describe '#address_pool' do

    before(:each) do
      allow_any_instance_of(described_class).to receive(:validate)
    end

    it 'returns whole pool when not default kontena pool' do
      subject = described_class.new(pool_id: 'pool')
      subject.instance_variable_set(:@pool, '10.89.0.0/24')

      pool = subject.address_pool
      expect(pool.size).to eq(255)
      expect(subject.class.pools['10.89.0.0/24']).to eq(pool)
    end

    it 'returns reducted pool when default kontena pool' do
      subject = described_class.new(pool_id: 'kontena')
      subject.instance_variable_set(:@pool, '10.81.0.0/16')

      pool = subject.address_pool
      expect(pool.size).to eq(65534 - 254)
      expect(subject.class.pools['10.81.0.0/16']).to eq(pool)
    end
  end

end
