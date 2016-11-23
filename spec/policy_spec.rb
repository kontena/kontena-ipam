require_relative '../app/policy'

describe Policy do
  context 'using an invalid policy' do
    it 'rejects an invalid supernet' do
      expect{Policy.new('KONTENA_IPAM_SUPERNET' => 'foo')}.to raise_error(IPAddr::InvalidAddressError)
    end

    it 'rejects an IPv6 supernet' do
      expect{Policy.new('KONTENA_IPAM_SUPERNET' => '2001:db8::/48')}.to raise_error(ArgumentError)
    end

    it 'rejects an invalid subnet length' do
      expect{Policy.new('KONTENA_IPAM_SUBNET_LENGTH' => 'x')}.to raise_error(ArgumentError)
      expect{Policy.new('KONTENA_IPAM_SUBNET_LENGTH' => '-1')}.to raise_error(ArgumentError)
      expect{Policy.new('KONTENA_IPAM_SUBNET_LENGTH' => '33')}.to raise_error(ArgumentError)
    end
  end

  context 'using the 10.80.0.0/12 supernet' do
    subject do
      Policy.new(
        'KONTENA_IPAM_SUPERNET' => '10.80.0.0/12',
        'KONTENA_IPAM_SUBNET_LENGTH' => '24',
      )
    end

    describe '#allocatable_subnets' do
      it 'allocates consecutive subnet' do
        reserved = IPSet.new([
          IPAddr.new('10.80.0.64/28'),
        ])

        expect(subject.allocatable_subnets(reserved).take(3)).to eq [
            IPAddr.new('10.80.1.0/24'),
            IPAddr.new('10.80.2.0/24'),
            IPAddr.new('10.80.3.0/24'),
        ]
      end

      it 'allocates after sparse subnets' do
        expect(subject.allocatable_subnets(IPSet.new([
          IPAddr.new('10.80.0.64/26'),
          IPAddr.new('10.80.0.128/26'),
        ])).first).to eq IPAddr.new('10.80.1.0/24')
      end

      it 'allocates after mixed subnets' do
        expect(subject.allocatable_subnets(IPSet.new([
          IPAddr.new('10.80.0.0/22'),
          IPAddr.new('10.80.3.64/26'),
        ])).first).to eq IPAddr.new('10.80.4.0/24')
      end

      it 'allocates in between subnets' do
        expect(subject.allocatable_subnets(IPSet.new([
          IPAddr.new('10.80.0.0/23'),
          IPAddr.new('10.80.4.0/23'),
        ])).first).to eq IPAddr.new('10.80.2.0/24')
      end

      it 'allocates to the very end' do
        expect(subject.allocatable_subnets(IPSet.new([])).to_a.last).to eq IPAddr.new('10.95.255.0/24')
      end

      it 'returns nil if the supernet is full' do
        reserved_subnets = (80..95).map {|x| IPAddr.new("10.#{x}.0.0/16") }

        expect(subject.allocatable_subnets(IPSet.new(reserved_subnets)).first).to be_nil
      end
    end


    end
  end
end
