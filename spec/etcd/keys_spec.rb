describe Etcd::Keys do
  class MockEtcd
    include Etcd::Keys
  end

  let :etcd do
    MockEtcd.new
  end

  it 'returns nodes' do
    pools_kontena = double('pools/kontena', key: '/kontena/ipam/pools/kontena', value: '{"network": "kontena", "subnet": "10.81.0.0/16"}')

    expect(etcd).to receive(:get).with('/kontena/ipam/pools/').and_return(double('pools',
      children: [
        pools_kontena
      ],
    ))

    expect{|block| etcd.each('/kontena/ipam/pools', &block) }.to yield_with_args('kontena', pools_kontena)
  end
end
