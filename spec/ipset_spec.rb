require_relative '../lib/ipset'

describe IPSet do
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

    it 'excludes other addresses' do
      expect(subject).to_not include IPAddr.new('1.2.3.4')

      expect(subject).to_not include IPAddr.new('192.0.2.0')
      expect(subject).to_not include IPAddr.new('192.0.2.255')

      expect(subject).to_not include IPAddr.new('200.100.2.5')
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
  end

end
