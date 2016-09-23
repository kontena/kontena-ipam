# A sparse set of IPAddrs, with membership tests.
#
# Members can be networks, and you can test for network membership, including overlapping and underlapping networks.
class IPSet
  attr_reader :addrs
  
  # Initialize for given IPAddrs.
  #
  # @param addrs [Array<IPAddr>]
  def initialize(addrs)
    @addrs = addrs.sort
  end

  # Search for addrs contained within the given networks, or networks containing the given addr
  def search(addr)
    @addrs.each do |a|
      yield a if a.include?(addr) || addr.include?(a)
    end
  end

  # Test if the given addr is included in this set
  #
  # @param addr [IPAddr] address
  # @return [Boolean]
  def include? (addr)
    search(addr) do |a|
      return true
    end
    return false
  end
end
