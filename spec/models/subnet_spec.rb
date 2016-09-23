describe Subnet do
  let :etcd do
    double()
  end

  before do
    EtcdModel.etcd = etcd
  end

  it 'lists all subnets in etcd' do
    expect(etcd).to receive(:get).with('/kontena/ipam/subnets/').and_return(double(directory?: true, children: [
      double(key: '/kontena/ipam/subnets/10.80.1.0', directory?: false, value: '{"address": "10.80.1.0/24"}'),
      double(key: '/kontena/ipam/subnets/10.80.2.0', directory?: false, value: '{"address": "10.80.2.0/24"}'),
      double(key: '/kontena/ipam/subnets/10.81.0.0', directory?: false, value: '{"address": "10.81.0.0/16"}'),
    ]))

    expect(Subnet.all.addrs).to eq [
      IPAddr.new('10.80.1.0/24'),
      IPAddr.new('10.80.2.0/24'),
      IPAddr.new('10.81.0.0/16'),
    ]
  end

  it 'reserves a subnet in etcd' do
    expect(etcd).to receive(:set).with('/kontena/ipam/subnets/10.82.0.0', prevExist: false, value: '{"address":"10.82.0.0/16"}')
    expect(etcd).to receive(:get).with('/kontena/ipam/subnets/').and_return(double(directory?: true, children: [
      double(key: '/kontena/ipam/subnets/10.80.1.0', directory?: false, value: '{"address": "10.80.1.0/24"}'),
      double(key: '/kontena/ipam/subnets/10.80.2.0', directory?: false, value: '{"address": "10.80.2.0/24"}'),
      double(key: '/kontena/ipam/subnets/10.81.0.0', directory?: false, value: '{"address": "10.81.0.0/16"}'),
      double(key: '/kontena/ipam/subnets/10.82.0.0', directory?: false, value: '{"address": "10.82.0.0/16"}'),
    ]))

    expect(Subnet.reserve(IPAddr.new('10.82.0.0/16'))).to eq Subnet.new('10.82.0.0', address: IPAddr.new('10.82.0.0/16'))
  end

  it 'raises on conflict' do
    expect(etcd).to receive(:set).with('/kontena/ipam/subnets/10.81.0.0', prevExist: false, value: '{"address":"10.81.0.0/16"}').and_raise(Etcd::NodeExist)

    expect{Subnet.reserve(IPAddr.new('10.81.0.0/16'))}.to raise_error(Subnet::Conflict)
  end

  it 'raises on underlap conflict' do
    expect(etcd).to receive(:set).with('/kontena/ipam/subnets/10.80.0.0', prevExist: false, value: '{"address":"10.80.0.0/16"}')
    expect(etcd).to receive(:get).with('/kontena/ipam/subnets/').and_return(double(directory?: true, children: [
      double(key: '/kontena/ipam/subnets/10.80.0.0', directory?: false, value: '{"address": "10.80.0.0/16"}'),
      double(key: '/kontena/ipam/subnets/10.80.1.0', directory?: false, value: '{"address": "10.80.1.0/24"}'),
      double(key: '/kontena/ipam/subnets/10.80.2.0', directory?: false, value: '{"address": "10.80.2.0/24"}'),
      double(key: '/kontena/ipam/subnets/10.81.0.0', directory?: false, value: '{"address": "10.81.0.0/16"}'),
    ]))
    expect(etcd).to receive(:delete).with('/kontena/ipam/subnets/10.80.0.0')

    expect{Subnet.reserve(IPAddr.new('10.80.0.0/16'))}.to raise_error(Subnet::Conflict)
  end

  it 'raises on overlap conflict' do
    expect(etcd).to receive(:set).with('/kontena/ipam/subnets/10.81.1.0', prevExist: false, value: '{"address":"10.81.1.0/24"}')
    expect(etcd).to receive(:get).with('/kontena/ipam/subnets/').and_return(double(directory?: true, children: [
      double(key: '/kontena/ipam/subnets/10.80.1.0', directory?: false, value: '{"address": "10.80.1.0/24"}'),
      double(key: '/kontena/ipam/subnets/10.80.2.0', directory?: false, value: '{"address": "10.80.2.0/24"}'),
      double(key: '/kontena/ipam/subnets/10.81.0.0', directory?: false, value: '{"address": "10.81.0.0/16"}'),
      double(key: '/kontena/ipam/subnets/10.81.1.0', directory?: false, value: '{"address": "10.81.1.0/24"}'),
    ]))
    expect(etcd).to receive(:delete).with('/kontena/ipam/subnets/10.81.1.0')

    expect{Subnet.reserve(IPAddr.new('10.81.1.0/24'))}.to raise_error(Subnet::Conflict)
  end
end
