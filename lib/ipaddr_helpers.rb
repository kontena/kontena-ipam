require 'ipaddr'

# monkey-patch
class IPAddr
    # @return [Integer] /X CIDR prefix length
    def length
        @mask_addr.to_s(2).count('1')
    end

    # @return [Integer] maximum prefix length (/32 for IPv4, /128 for IPv6)
    def maxlength
      case
      when ipv4?
        32
      when ipv6?
        128
      else
        raise
      end
    end

    # @return [String] The address + netmask in W.X.Y.Z/P format
    #
    # For a host address, this will include the /32 suffix
    def to_cidr
        "#{to_s}/#{length}"
    end

    # Serialize to JSON as a CIDR string
    def to_json(*args)
        to_cidr.to_json(*args)
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
end
