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

    # Yield each of the subnets of a given length within this larger supernet.
    #
    # IPAddr.new('10.80.0.0/16').each_subnet(24) { |subnet| puts subnet }
    #   10.80.0.0/24
    #   10.80.1.0/24
    #   ...
    #   10.80.255.0/24
    #
    # @param length [Integer] desired subnet prefix length
    # @yield [subnet] iterate over the subnets
    # @yieldparam subnet [IPAddr] smaller subnet within this supernet
    def each_subnet (length)
      raise ArgumentError, 'Short subnet prefix' if length < self.length

      subnet_count = 2 ** (length - self.length)

      for i in 0...subnet_count
        yield subnet(length, i)
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

    # Yield each of the subnet addresses.
    # Optionally skip the first offset addresses.
    # The addr is yielded as a subnet addr with the subnet mask.
    #
    # @param offset [Integer] skip the first N addresses
    # @param exclude [IPSet] exclude specific addresses
    # @yield [addr]
    # @yieldparam addr [IPAddr] host address with the subnet mask
    def each_host(offset: nil, exclude: nil)
      for addr in to_range
        next if addr.network? || addr.broadcast?
        next if offset && addr.host_offset < offset
        next if exclude && (exclude.include? addr)

        yield addr
      end
    end

    def list_hosts(**opts)
      hosts = []
      each_host(**opts) do |host|
        hosts << host
      end
      hosts
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
end
