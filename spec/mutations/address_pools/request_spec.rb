
describe AddressPools::Request do

  let(:subject) do
    described_class.new()
  end

  let(:etcd) do
    spy()
  end

  before(:each) do
    allow(subject).to receive(:etcd).and_return(etcd)
  end

  describe '#execute' do
    it 'returns address pool if it is already reserved in etcd' do
      expect(etcd).to receive(:get).with('/kontena/ipam/pools/kontena').and_return(double({value: '10.81.0.0/16'}))
      pool = subject.execute
      expect(pool.id).to eq('kontena')
      expect(pool.pool).to eq('10.81.0.0/16')
    end

    it 'errors if given pool already reserved' do
      expect(etcd).to receive(:get).with('/kontena/ipam/pools/test').and_return(nil)
      subject = described_class.new(network: 'test', pool: '10.1.2.0/16')
      allow(subject).to receive(:etcd).and_return(etcd)
      expect(subject).to receive(:reserve_pool).with('test', '10.1.2.0/16').and_return(nil)
      expect(subject).to receive(:add_error)
      subject.execute
    end

    it 'reserves given pool' do
      subject = described_class.new(network: 'test', pool: '10.1.2.0/16')
      allow(subject).to receive(:etcd).and_return(etcd)
      expect(etcd).to receive(:get).with('/kontena/ipam/pools/test').and_return(nil)

      expect(subject).to receive(:reserve_pool).with('test', '10.1.2.0/16').and_return('10.1.2.0/16')
      pool = subject.execute
      expect(pool.id).to eq('test')
      expect(pool.pool).to eq('10.1.2.0/16')
    end

  end

  describe '#reserve_pool' do
    it 'generates default pool when no pool given' do
      expect(subject).to receive(:generate_default_pool).with('test')
      subject.reserve_pool('test', '')
    end

    it 'reserves given pool' do
      expect(subject).to receive(:reserve_requested_pool).with('test', '10.1.2.0/16')
      subject.reserve_pool('test', '10.1.2.0/16')
    end
  end

  describe '#generate_default_pool' do
    it 'reserves new pool' do
      expect(subject).to receive(:reserved_pools).and_return([])
      expect(etcd).to receive(:set).with('/kontena/ipam/pools/test', value: '10.82.0.0/16')
      expect(etcd).to receive(:set).with('/kontena/ipam/addresses/test', dir: true)

      subject.generate_default_pool('test')
    end

    it 'reserves new pool after last reserved' do
      expect(subject).to receive(:reserved_pools).and_return([IPAddr.new('10.82.0.0/16'), IPAddr.new('10.83.0.0/16')])
      expect(etcd).to receive(:set).with('/kontena/ipam/pools/test', value: '10.84.0.0/16')
      expect(etcd).to receive(:set).with('/kontena/ipam/addresses/test', dir: true)

      subject.generate_default_pool('test')
    end

    it 'returns nil if pool cannot be generated' do
      reserved_pools = []
      (82..254).each do |i|
        reserved_pools << IPAddr.new("10.#{i}.0.0/16")
      end
      expect(subject).to receive(:reserved_pools).and_return(reserved_pools)

      pool = subject.generate_default_pool('test')
      expect(pool).to be_nil
    end
  end

  describe '#reserve_requested_pool' do
    it 'reserves given pool when no existing pools' do
      expect(subject).to receive(:reserved_pools).and_return([])
      expect(etcd).to receive(:set).with('/kontena/ipam/pools/test', value: '10.82.0.0/16')
      expect(etcd).to receive(:set).with('/kontena/ipam/addresses/test', dir: true)

      subject.reserve_requested_pool('test', '10.82.0.0/16')
    end

    it 'reserves given pool when no overlaps with existing pools' do
      reserved_pools = [IPAddr.new('10.82.0.0/16'), IPAddr.new('10.84.0.0/16')]
      expect(subject).to receive(:reserved_pools).and_return(reserved_pools)
      expect(etcd).to receive(:set).with('/kontena/ipam/pools/test', value: '10.83.0.0/17')
      expect(etcd).to receive(:set).with('/kontena/ipam/addresses/test', dir: true)

      subject.reserve_requested_pool('test', '10.83.0.0/17')
    end

    it 'fails to reserve given pool when overlaps with existing pools' do
      reserved_pools = [IPAddr.new('10.82.0.0/16'), IPAddr.new('10.84.0.0/16')]
      expect(subject).to receive(:reserved_pools).twice.and_return(reserved_pools)
      expect(etcd).not_to receive(:set)

      subject.reserve_requested_pool('test', '10.82.0.0/17')
      subject.reserve_requested_pool('test', '10.80.0.0/14')
    end
  end
end
