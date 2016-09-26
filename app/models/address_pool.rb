class AddressPool
  include JSONModel
  include EtcdModel

  etcd_path '/kontena/ipam/pools/:id'
  json_attr :subnet, type: IPAddr
  json_attr :iprange, type: IPAddr, omitnil: true

  attr_accessor :id, :subnet, :iprange

  # Return currently reserved subnets
  #
  # @return [IPSet]
  def self.reserved_subnets
    Subnet.all
  end

  # Reserve Subnet and create Address directory for this pool
  #
  # @raise [Subnet::Conflict] if reserving the subnet fails
  # @see Address
  # @see Subnet
  def create!
    Subnet.reserve(@subnet)
    super
    Address.mkdir(@id)
  end

  # Delete Address directory and release Subnet for this pool
  #
  # @see Address
  # @see Subnet
  def delete!
    super
    Address.delete(@id)
    Subnet.delete(@subnet)
  end

  # Return the set of allocatable addresses.
  #
  # @return [IPAddr] subnet
  def allocatable
    @iprange || @subnet
  end

  # Return given Address from AddressPool
  #
  # @param addr [IPAddr] within our subnet
  # @return [Address] or nil on conflict
  def create_address(addr, **opts)
    Address.create(@id, addr.to_s, address: subnet.subnet_addr(addr), **opts)
  end

  # Return specific address from pool
  #
  # @param addr [IPAddr]
  # @return [Address] or nil if not found
  def get_address(addr)
    Address.get(@id, addr.to_s)
  end

  # List addresses from pool
  #
  # @return [Array<Address>]
  def list_addresses
    Address.list(@id)
  end

  # Return the set of reserved IP addresses from etcd.
  #
  # @return [IPSet]
  def reserved_addresses
    IPSet.new(list_addresses.map{|a| a.address })
  end
end
