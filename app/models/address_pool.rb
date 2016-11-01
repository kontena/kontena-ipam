class AddressPool
  include JSONModel
  include EtcdModel
  include NodeHelper

  # Address pool is full
  class Full < StandardError

  end

  etcd_path '/kontena/ipam/pools/:id'
  json_attr :subnet, type: IPAddr
  json_attr :iprange, type: IPAddr, omitnil: true
  json_attr :gateway, type: IPAddr

  attr_accessor :id, :subnet, :iprange, :gateway

  # Return currently reserved subnets
  #
  # @return [IPSet]
  def self.reserved_subnets
    Subnet.all
  end

  def self.create(id, subnet: nil, **opts)
    # use the first host address as gateway
    gateway = subnet ? subnet.hosts.first : nil
    super(id, subnet: subnet, gateway: gateway, **opts)
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
    PoolNode.mkdir(@id)
    create_address(gateway)
  end

  # Creates a PoolNode lease for the current node
  def request!
    PoolNode.create_or_get(@id, node)
  end

  # @return [Boolean] pool is not in use on any nodes
  def orphaned?
    PoolNode.list(@id).empty?
  end

  # Release the PoolNode lease for the current node
  def release!
    PoolNode.delete(@id, node)
  end

  # delete! if orphaned?
  def cleanup
    delete!
  rescue PoolNode::Conflict
    # still in use
  end

  # Delete Address directory and release Subnet for this pool
  #
  # @raise [PoolNode::Conflict] if the pool is still in use on some node
  # @see Address
  # @see Subnet
  def delete!
    PoolNode.rmdir(@id)
    super
    Address.delete(@id)
    Subnet.delete(@subnet)
  end

  # Return the range of of allocatable addresses.
  #
  # @return [Range<IPAddr>] allocation range
  def allocation_range
    (@iprange or @subnet).to_range
  end

  # Return given Address from AddressPool
  #
  # @param addr [IPAddr] within our subnet
  # @return [Address] or nil on conflict
  def create_address(addr, **opts)
    Address.create(@id, addr.to_s, node: node, address: subnet.subnet_addr(addr), **opts)
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
  # These are host addresses without a netmask.
  #
  # @return [IPSet]
  def reserved_addresses
    IPSet.new(list_addresses.map{|a| a.address.to_host })
  end

  # Compute available addresses for allocation within pool
  #
  # @return [Array<IPAddr>]
  def available_addresses
    @subnet.hosts(range: allocation_range, exclude: reserved_addresses).to_a
  end
end
