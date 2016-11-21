# Configurable policy for dynamically allocating Subnets
#
# Supports configuration from environment variables:
#
#   KONTENA_IPAM_SUPERNET=10.80.0.0/12
#   KONTENA_IPAM_SUBNET_LENGTH=24
#
# @attr_reader [IPAddr] supernet CIDR range for allocating subnets
# @attr_reader [Integer] subnet_length desired subnet length
class Policy
  # Allocate subnets from within this network
  SUPERNET = IPAddr.new('10.80.0.0/12')

  # Subnet prefix length
  SUBNET_LENGTH = 24

  attr_accessor :supernet, :subnet_length

  # @param env [Hash<String, String>] environment variables for configuration
  def initialize (env = ENV)
    @supernet = SUPERNET
    @subnet_length = SUBNET_LENGTH

    supernet = env['KONTENA_IPAM_SUPERNET']
    subnet_length = env['KONTENA_IPAM_SUBNET_LENGTH']

    @supernet = IPAddr.new(supernet) if supernet
    @subnet_length = Integer(subnet_length) if subnet_length

    raise ArgumentError, 'Supernet must be an IPv4 address' unless @supernet.ipv4?
    raise ArgumentError, 'Invalid subnet length' unless @subnet_length.between?(0, 32)
  end

  # Enumerate allocatable subnets of the configured length within the supernet, avoiding any
  # overlap with the given reserved subnets.
  #
  # @param reserved [IPSet] existing subnets
  # @return [Enumerator<IPAddr>]
  def allocatable_subnets(reserved)
    supernet.subnets(subnet_length, exclude: reserved)
  end

  # Allocate an IP address from within the given set of available addresses.
  # Returns nil if no available addresses
  #
  # @param addresses [Array<IPAddr>] available host addresses
  # @return [IPAddr] or nil
  def allocate_address(addresses)
    if addresses.empty?
      nil
    else
      addresses[rand(0...addresses.size)]
    end
  end
end
