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

  # Allocate a subnet of the configured length within the supernet, avoiding any
  # overlap with the given reserved subnets.
  #
  # Returns nil if there is not enough space within the supernet for the desired subnet.
  #
  # @param reserved_subnets [Array<IPAddr>] existing subnets
  # @return [IPAddr] new subnet, or nil
  def allocate_subnet (reserved_subnets)
    supernet.each_subnet(subnet_length) do |subnet|
      return subnet unless reserved_subnets.any? { |s| s.include?(subnet) || subnet.include?(s) }
    end
    return nil
  end
end
