require_relative '../lib/ipaddr_helpers'

describe IPAddr do
  describe 'for IPv4 addresses' do
    it 'has a prefix length' do
      expect(IPAddr.new('0.0.0.0/0').length).to eq 0
      expect(IPAddr.new('10.80.0.0/12').length).to eq 12
      expect(IPAddr.new('10.80.0.0/24').length).to eq 24
      expect(IPAddr.new('10.80.0.1/24').length).to eq 24
      expect(IPAddr.new('10.80.1.1/32').length).to eq 32
    end

    it 'formats as a CIDR' do
      expect(IPAddr.new('0.0.0.0/0').to_cidr).to eq '0.0.0.0/0'
      expect(IPAddr.new('10.80.0.0/12').to_cidr).to eq '10.80.0.0/12'
      expect(IPAddr.new('10.80.0.0/24').to_cidr).to eq '10.80.0.0/24'
      expect(IPAddr.new('10.80.0.1/24').to_cidr).to eq '10.80.0.1/24'
      expect(IPAddr.new('10.80.1.1/32').to_cidr).to eq '10.80.1.1/32'
    end

    it 'can generate a host address within the subnet' do
      expect(IPAddr.new('192.0.2.0/24').subnet_addr('192.0.2.100').to_cidr).to eq '192.0.2.100/24'
    end
    it 'rejects a host address outside the subnet' do
      expect{IPAddr.new('192.0.2.0/24').subnet_addr('192.0.0.1')}.to raise_error ArgumentError
    end

    it 'encodes network addresses to JSON' do
      expect(JSON.dump('test' => IPAddr.new('10.80.1.0/24'))).to eq '{"test":"10.80.1.0/24"}'
    end
    it 'encodes network addresses to JSON' do
      expect(JSON.dump('test' => IPAddr.new('10.80.1.0/24').list_hosts.first)).to eq '{"test":"10.80.1.1/24"}'
    end
    it 'encodes host addresses to JSON' do
      expect(JSON.dump('test' => IPAddr.new('10.80.1.1'))).to eq '{"test":"10.80.1.1"}'
    end
  end

  describe "for IPv6 addresses" do
    it 'has a prefix length' do
      expect(IPAddr.new('::/0').length).to eq 0
      expect(IPAddr.new('2001:db8::/64').length).to eq 64
      expect(IPAddr.new('fe80::/64').length).to eq 64
      expect(IPAddr.new('fe80::aabb:ccff:fedd:eeff/64').length).to eq 64
      expect(IPAddr.new('fe80:db8::1/128').length).to eq 128
    end

    it 'formats as a CIDR' do
      expect(IPAddr.new('::/0').to_cidr).to eq '::/0'
      expect(IPAddr.new('2001:db8::/64').to_cidr).to eq '2001:db8::/64'
      expect(IPAddr.new('fe80::aabb:ccff:fedd:eeff/64').to_cidr).to eq 'fe80::aabb:ccff:fedd:eeff/64'
      expect(IPAddr.new('fe80:db8::1/128').to_cidr).to eq 'fe80:db8::1/128'
    end

    it 'can generate a host address within the subnet' do
      expect(IPAddr.new('fe80::/64').subnet_addr('fe80::aabb:ccff:fedd:eeff').to_cidr).to eq 'fe80::aabb:ccff:fedd:eeff/64'
    end
  end

  describe 'for the IPv4 192.0.2.0/24 network' do
    let :subject do
      IPAddr.new('192.0.2.0/24')
    end

    it 'has an addrmask' do
      expect(subject._addrmask).to eq 0xffffffff
    end
    it 'has an netmask' do
      expect(subject._netmask).to eq 0xffffff00
    end
    it 'has an hostmask' do
      expect(subject._hostmask).to eq 0x000000ff
    end

    it 'knows the network address' do
      expect(subject.network.to_cidr).to eq '192.0.2.0/24'
    end

    it 'recognizes the network address' do
      expect(subject.network).to be_network
    end

    it 'knows the broadcast address' do
      expect(subject.broadcast.to_cidr).to eq '192.0.2.255/24'
    end

    it 'recognizes the broadcast address' do
      expect(subject.broadcast).to be_broadcast
    end

    it 'lists the host addresses' do
      hosts = subject.list_hosts

      expect(hosts.first).to eq '192.0.2.1'
      expect(hosts.first).to_not be_host
      expect(hosts.first.to_cidr).to eq '192.0.2.1/24'
      expect(hosts).to eq((1..254).map{|i| IPAddr.new("192.0.2.#{i}")})
    end

    it 'lists the host from an offset' do
      hosts = subject.list_hosts offset: 100

      expect(hosts.first.to_cidr).to eq '192.0.2.100/24'
      expect(hosts).to eq((100..254).map{|i| IPAddr.new("192.0.2.#{i}")})
    end

    it 'lists the host addresses with an IPSet exclude' do
      excludes = [20, 10, 11]
      exclude_addrs = excludes.map{|i| IPAddr.new("192.0.2.#{i}")}

      hosts = subject.list_hosts exclude: IPSet.new(exclude_addrs)

      expect(hosts.first.to_cidr).to eq '192.0.2.1/24'
      expect(hosts).to eq((1..254).map { |i|
        next if excludes.include? i

        IPAddr.new("192.0.2.#{i}")
      }.compact)
    end
  end

  describe 'for the 10.80.0.0/12 supernet' do
    let :supernet do
      IPAddr.new('10.80.0.0/12')
    end

    it 'does not retain cached length across clone' do
      expect(supernet.length).to eq 12
      expect(supernet.subnet(24, 0)).to eq IPAddr.new('10.80.0.0/24')
      expect(supernet.length).to eq 12
    end

    it 'calculates subnets' do
      expect(supernet.subnet(24, 0)).to eq IPAddr.new('10.80.0.0/24')
      expect(supernet.subnet(24, 100)).to eq IPAddr.new('10.80.100.0/24')
      expect(supernet.subnet(24, 2**12 -1 )).to eq IPAddr.new('10.95.255.0/24')

      expect(supernet.subnet(26, 100)).to eq IPAddr.new('10.80.25.0/26')
      expect(supernet.subnet(26, 101)).to eq IPAddr.new('10.80.25.64/26')
      expect(supernet.subnet(32, 0)).to eq IPAddr.new('10.80.0.0/32')
    end

    it 'rejects invalid subnets' do
      expect{supernet.subnet(33, 0)}.to raise_error ArgumentError
      expect{supernet.subnet(24, 2**12)}.to raise_error ArgumentError
    end

    it 'generates big subnets' do
      expect{|block| supernet.each_subnet(14, &block)}.to yield_successive_args(
        IPAddr.new('10.80.0.0/14'),
        IPAddr.new('10.84.0.0/14'),
        IPAddr.new('10.88.0.0/14'),
        IPAddr.new('10.92.0.0/14'),
      )
    end

    it 'generates small subnets' do
      subnets = []
      for x in 80..95 do
        for y in 0..255 do
          subnets << IPAddr.new("10.#{x}.#{y}.0/24")
        end
      end

      expect{|block| supernet.each_subnet(24, &block)}.to yield_successive_args(*subnets)
    end
  end

  describe 'for the fd00:ecec::/48 supernet' do
    let :supernet do
      IPAddr.new('fd00:ecec::/48')
    end

    it 'calculates subnets' do
      expect(supernet.subnet(64, 0)).to eq IPAddr.new('fd00:ecec::/64')
      expect(supernet.subnet(64, 0xABCD)).to eq IPAddr.new('fd00:ecec:0:abcd::/64')
      expect(supernet.subnet(64, 0xFFFF)).to eq IPAddr.new('fd00:ecec:0:ffff::/64')

      expect(supernet.subnet(128, 1)).to eq IPAddr.new('fd00:ecec::1/128')
    end

    it 'rejects invalid subnets' do
      expect{supernet.subnet(129, 0)}.to raise_error ArgumentError
      expect{supernet.subnet(64, 2**16)}.to raise_error ArgumentError
    end

    it 'generates big subnets' do
      expect{|block| supernet.each_subnet(50, &block)}.to yield_successive_args(
        IPAddr.new('fd00:ecec:0:0000::/50'),
        IPAddr.new('fd00:ecec:0:4000::/50'),
        IPAddr.new('fd00:ecec:0:8000::/50'),
        IPAddr.new('fd00:ecec:0:c000::/50'),
      )
    end
  end
end
