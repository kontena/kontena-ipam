require_relative '../lib/ipset'

describe IPSet do
  it 'includes an added address' do
    subject = described_class.new([])
    subject.add! IPAddr.new('192.0.2.1')

    expect(subject.length).to eq 1
    expect(subject).to include IPAddr.new('192.0.2.1')
  end

  it 'also includes an added address' do
    subject = described_class.new([IPAddr.new('192.0.2.1')])
    subject.add! IPAddr.new('192.0.2.2')

    expect(subject.length).to eq 2
    expect(subject).to include IPAddr.new('192.0.2.1')
    expect(subject).to include IPAddr.new('192.0.2.2')
  end

  it 'also includes an added address in reverse order' do
    subject = described_class.new([IPAddr.new('192.0.2.2')])
    subject.add! IPAddr.new('192.0.2.1')

    expect(subject.length).to eq 2
    expect(subject).to include IPAddr.new('192.0.2.1')
    expect(subject).to include IPAddr.new('192.0.2.2')
  end

  context 'for a full subnet' do
    let :subject do
      described_class.new((1..254).map { |i| IPAddr.new("192.0.2.#{i}")})
    end

    it 'includes every address' do
      (1..254).each do |i|
        addr = IPAddr.new("192.0.2.#{i}")

        expect(subject).to include addr
      end
    end

    it 'includes the subnet' do
      expect(subject).to include IPAddr.new('192.0.2.0/24')
    end
    it 'includes the subnet with host bits set' do
      expect(subject).to include IPAddr.new('192.0.2.1/24')
    end
    it 'includes a sub-subnet' do
      expect(subject).to include IPAddr.new('192.0.2.64/30')
    end
    it 'includes a supernet' do
      expect(subject).to include IPAddr.new('192.0.0.0/16')
    end

    it 'excludes other addresses' do
      expect(subject).to_not include IPAddr.new('1.2.3.4')

      expect(subject).to_not include IPAddr.new('192.0.2.0')
      expect(subject).to_not include IPAddr.new('192.0.2.255')

      expect(subject).to_not include IPAddr.new('200.100.2.5')
    end

    it 'exclude a different network' do
      expect(subject).to_not include IPAddr.new('192.0.3.0/24')
    end
  end

  context 'for an sparse subnet' do
    let :subject do
       described_class.new([20, 10, 11, 13].map{|i| IPAddr.new("192.0.2.#{i}")})
    end

    it 'includes those addresses' do
      expect(subject).to include IPAddr.new('192.0.2.10')
      expect(subject).to include IPAddr.new('192.0.2.11')
      expect(subject).to include IPAddr.new('192.0.2.13')
      expect(subject).to include IPAddr.new('192.0.2.20')
    end

    it 'includes the subnet' do
      expect(subject).to include IPAddr.new('192.0.2.0/24')
    end
    it 'includes a covering sub-subnet' do
      expect(subject).to include IPAddr.new('192.0.2.0/28')
    end
    it 'excludes a non-overlapping sub-subnet' do
      expect(subject).to_not include IPAddr.new('192.0.2.64/30')
    end
    it 'includes a supernet' do
      expect(subject).to include IPAddr.new('192.0.0.0/16')
    end

    it 'exclude other addresses' do
      expect(subject).to_not include IPAddr.new('1.2.3.4')

      expect(subject).to_not include IPAddr.new('192.0.2.0')
      expect(subject).to_not include IPAddr.new('192.0.2.9')
      expect(subject).to_not include IPAddr.new('192.0.2.9')
      expect(subject).to_not include IPAddr.new('192.0.2.12')
      expect(subject).to_not include IPAddr.new('192.0.2.14')
      expect(subject).to_not include IPAddr.new('192.0.2.255')

      expect(subject).to_not include IPAddr.new('200.100.2.5')
    end

    it 'excludes a different network' do
      expect(subject).to_not include IPAddr.new('192.0.3.0/24')
    end
  end

  context 'for a set of networks' do
    let :subject do
      described_class.new([
        IPAddr.new('10.80.1.0/24'),
        IPAddr.new('10.80.2.0/24'),
        IPAddr.new('10.81.0.0/16'),
      ])
    end

    it 'excludes a subnet' do
      expect(subject).to_not include IPAddr.new('10.80.0.0/24')
    end
    it 'excludes a host' do
      expect(subject).to_not include IPAddr.new('10.80.0.100')
    end
    it 'includes a subnet' do
      expect(subject).to include IPAddr.new('10.80.1.0/24')
    end
    it 'includes a host' do
      expect(subject).to include IPAddr.new('10.80.1.100')
    end

    it 'includes a supernet' do
      expect(subject).to include IPAddr.new('10.80.0.0/16')
    end
    it 'includes a with different address bits' do
      expect(subject).to include IPAddr.new('10.0.0.0/8')
    end
  end
end
