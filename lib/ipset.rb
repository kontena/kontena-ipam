# A sparse set of IPAddrs, with membership tests.
#
# Uses binary search over a sorted array for lookups.
class IPSet
  # Initialize for given IPAddrs.
  #
  # @param addrs [Array<IPAddr>]
  def initialize(addrs)
    @addrs = addrs.sort
  end

  # Test if the given addr is included in this set
  #
  # @param addr [IPAddr] address
  # @return [Boolean]
  def include? (addr)
    return @addrs.bsearch {|a| a >= addr} == addr
  end
end
