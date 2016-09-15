require_relative '../app/ipaddr'

describe IPAddr do
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
end
