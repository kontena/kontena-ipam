require_relative '../lib/ipaddr_helpers'

describe IPAddr do
  describe 'for IPv4 addresses' do
    it 'has a prefix length' do
      expect(IPAddr.new('0.0.0.0/0').length).to eq 0
      expect(IPAddr.new('10.80.0.0/12').length).to eq 12
      expect(IPAddr.new('10.80.0.0/24').length).to eq 24
      expect(IPAddr.new('10.80.1.1/32').length).to eq 32
    end

    it 'formats as a CIDR' do
      expect(IPAddr.new('0.0.0.0/0').to_cidr).to eq '0.0.0.0/0'
      expect(IPAddr.new('10.80.0.0/12').to_cidr).to eq '10.80.0.0/12'
      expect(IPAddr.new('10.80.0.0/24').to_cidr).to eq '10.80.0.0/24'
      expect(IPAddr.new('10.80.1.1/32').to_cidr).to eq '10.80.1.1/32'
    end

    it 'encodes to JSON' do
      expect(JSON.dump('test' => IPAddr.new('10.80.1.0/32'))).to eq '{"test":"10.80.1.0/32"}'
    end
  end

  describe "for IPv6 addresses" do
    it 'has a prefix length' do
      expect(IPAddr.new('::/0').length).to eq 0
      expect(IPAddr.new('2001:db8::/64').length).to eq 64
      expect(IPAddr.new('fe80::aabb:ccff:fedd:eeff/64').length).to eq 64
      expect(IPAddr.new('fe80:db8::1/128').length).to eq 128
    end

    it 'formats as a CIDR' do
      expect(IPAddr.new('::/0').to_cidr).to eq '::/0'
      expect(IPAddr.new('2001:db8::/64').to_cidr).to eq '2001:db8::/64'
      expect(IPAddr.new('fe80::aabb:ccff:fedd:eeff/64').to_cidr).to eq 'fe80::/64'
      expect(IPAddr.new('fe80:db8::1/128').to_cidr).to eq 'fe80:db8::1/128'
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
