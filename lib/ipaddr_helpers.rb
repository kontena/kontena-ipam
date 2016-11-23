require 'ipaddr'

# monkey-patch
class IPAddr

    _wrap_initialize = instance_method :initialize
    define_method(:initialize) do |addr, family = Socket::AF_UNSPEC|
      orig_addr = addr

      if addr.kind_of?(String) && addr.include?('/')
        addr, prefixlen = addr.split('/')
      end

      _wrap_initialize.bind(self).(addr, family)

      if prefixlen
        addr = @addr

        mask!(prefixlen)

        # restore host bits
        @addr = addr
      end
    end

    # Compares with a different IPAddr, including subnet mask.
    def <=>(other)
      other = coerce_other(other)

      return nil if other.family != @family

      if @addr != other.to_i
        return @addr <=> other.to_i
      else
        return _netmask <=> other._netmask
      end
    end
    def ==(other)
      (self <=> other) == 0
    end
    def eql?(other)
      (self <=> other) == 0
    end

    # @return [Integer] /X CIDR prefix length
    def length
        @mask_addr.to_s(2).count('1')
    end

    # @return [Integer] maximum prefix length (/32 for IPv4, /128 for IPv6)
    def maxlength
      ipv4? ? 32 : 128
    end

    # @return [Integer] full address mask bits
    def _addrmask
      ipv4? ? IN4MASK : IN6MASK
    end

    # @return [Integer] mask net bits
    def _netmask
      @mask_addr
    end

    # @return [Integer] mask host bits
    def _hostmask
      @mask_addr ^ _addrmask
    end

    # @return [String] The address + netmask in W.X.Y.Z/P format
    #
    # For a host address, this will include the /32 suffix
    def to_cidr
        "#{to_s}/#{length}"
    end

    # Serialize to JSON as a  string.
    # For a host address this will be the address itself, otherwise a CIDR string.
    #
    # @return [String] JSON-encoded address string
    def to_json(*args)
      if host?
        to_s.to_json(*args)
      else
        to_cidr.to_json(*args)
      end
    end

    # Return a new IPAddr representing a smaller subnet within this larger supernet.
    #
    # The given subnet length must be longer than this supernet's length.
    # The given offset must be within the number of such subnets which would fit into this supernet.
    #
    # For example, the 10.80.0.0/12 supernet can contain up to 4k /24 subnets,
    # from .subnet(24, 0) for 10.80.0.0/24 to .subnet(24, 4095) for 10.95.255.0/24.
    #
    # @param length [Integer] desired subnet prefix length
    # @param offset [Integer] ordinal subnet offset within
    # @raise ArgumentError
    # @return subnet [IPAddr] smaller subnet within this larger supernet
    def subnet(length, offset)
      raise ArgumentError, 'Invalid subnet prefix' unless length.between?(self.length, self.maxlength)
      raise ArgumentError, 'Invalid subnet offset' unless offset.between?(0, 2 ** (length - self.length) - 1)

      mask(length) | (offset << (self.maxlength - length))
    end

    # Enumerate the subnets of a given length within this larger supernet.
    #
    # IPAddr.new('10.80.0.0/16').subnets(24).each { |subnet| puts subnet }
    #   10.80.0.0/24
    #   10.80.1.0/24
    #   ...
    #   10.80.255.0/24
    #
    # @param length [Integer] desired subnet prefix length
    # @param exclude [IPSet] exclude other IPAddrs
    # @return [Enumerator<IPAddr>] enumerate IPAddr
    def subnets(length, exclude: nil)
      raise ArgumentError, 'Short subnet prefix' if length < self.length
      raise ArgumentError, "Exclude must be an IPSet, not a #{exclude.class}" if exclude unless exclude.is_a? IPSet

      subnet_count = 2 ** (length - self.length)

      Enumerator.new do |y|
        for i in 0...subnet_count
          s = subnet(length, i)

          next if exclude && exclude.include?(s)

          y << s
        end
      end
    end

    # Compute the subnet network address
    #
    # @return IPAddr with subnet mask and no host bits set
    def network
      self & _netmask
    end

    # Test for the reserved network address within a subnet
    #
    # @return Boolean
    def network?
      @addr & _hostmask == 0
    end

    # Compute the subnet broadcast address
    #
    # @return IPAddr with subnet mask and all host bits set
    def broadcast
      self | _hostmask
    end

    # Test for the reserved broadcast address within a subnet
    #
    # @return Boolean
    def broadcast?
      @addr & _hostmask == _hostmask
    end

    # Test if this is a host address with a full-length mask
    def host?
      _hostmask == 0
    end

    # Return the full-length host address for a masked address
    #
    # @return IPAddr with a full-length mask
    def to_host
      mask(maxlength)
    end

    # Return the number of the host within the network.
    #
    # @raise RuntimeError if this is a host address without a subnet mask
    def host_offset
      raise "Not a subnet address" if host?

      @addr & _hostmask
    end

    # Return address within subnet.
    #
    def [](i)
      raise ArgumentError, "IP #{i} outside of subnet #{inspect}" if i > _hostmask

      self | i
    end

    # Enumerate the subnet addresses within this network.
    #
    # Optionally skip the first offset addresses.
    # The addr is yielded as a subnet addr with a subnet mask and host bits set.
    #
    # @param offset [Integer] skip the first N addresses
    # @param range [Range<IPAddr>] more specific range of host addresses
    # @param exclude [IPSet] exclude specific addresses
    # @return [Enumerator<IPAddr>]
    def hosts(offset: nil, range: nil, exclude: nil)
      range = to_range unless range

      Enumerator.new do |y|
        for addr in range
          addr = subnet_addr(addr)

          next if addr.network? || addr.broadcast?
          next if offset && addr.host_offset < offset
          next if exclude && (exclude.include? addr.to_host)

          y << addr
        end
      end
    end

    # Return the given host addr within this subnet, with the subnet mask.
    #
    # @param addr [IPAddr] host address
    # @raise ArgumentError host address outside of subnet
    # @return [IPAddr] host address with subnet mask
    def subnet_addr(addr)
      addr = coerce_other(addr)

      raise ArgumentError, "Host address #{addr} outside of subnet #{self}" unless self.include? addr

      return clone.set(addr.to_i)
    end

    # Yield each of the higher networks that contains this subnet.
    #
    # For example, IPAddr.new('192.0.2.0/24').supernets would yield 192.0.2.0/23, 192.0.0.0/22, ..., 0.0.0.0/0.
    #
    # @yield [supernet]
    # @yieldparam supernet [IPAddr] a larger network containing this network
    def supernets
      Enumerator.new do |y|
        (0...length).reverse_each do |super_length|
          y << mask(super_length)
        end
      end
    end
end
