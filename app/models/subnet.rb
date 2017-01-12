class Subnet
  include Kontena::JSON::Model
  include Kontena::Etcd::Model

  etcd_path '/kontena/ipam/subnets/:id'
  json_attr :address, type: IPAddr

  # Returns currently allocated subnets.
  #
  # @return [IPSet] allocated subnets
  def self.all
    IPSet.new(list.map{|subnet| subnet.address})
  end

  # Search for a subnet address overlapping the given subnet
  #
  # @yield [addr]
  # @yieldparam addr [IPAddr] overlapping subnet address
  def self.search(address, &block)
    all.search(address, &block)
  end

  # Reserve given subnet.
  #
  # Provides hard guarantees for duplicate subnets, and also does a best-effort
  # attempt at checking for conflicts with arbitrary overlapping/underlapping subnets.
  # I don't know if the write-verify-cancel algorithm here is 100% robust in the face
  # of arbitrary etcd partitions and failures, but it's a best effort at preventing
  # subnet conflicts in the unlikely case of concurrent allocations of different subnets.
  #
  # Consider two nodes (A and B) attempting to reserve overlapping subnets
  # (10.80.0.0/16 and 10.80.10.0/24). Each node will perform a create operation
  # writing the subnet to etcd, a search operation to check for conflicting subnets,
  # and then either commit the reservation by returning, or cancel by deleting
  # the node and raising. This should guarantee consistent allocations, assuming
  # linearizable writes/reads? Do we need to use etcd.get(quorum: true) reads if
  # we're only reading from a single node?
  #
  # * A create, A search, A commit, B create, B search, B cancel
  # * A create, B create, A search, B search, A cancel, B cancel
  # * A create, B create, B search, B cancel, A search, A commit
  #
  # If the read-verify get operation or cancel delete operation fails, the
  # possibly-valid/invalid subnet node will remain orphaned in etcd, but this method
  # will raise an error and the subnet will not be commited into use. Such orphaned
  # subnets would need to be cleaned up later.
  #
  # @param address [IPAddr]
  # @raise Subnet::Conflict
  # @return [Subnet]
  def self.reserve(address)
    unless address.network?
      raise ArgumentError, "Not a network address, has host bits set"
    end

    # create a new node to open the "transaction"
    subnet = create(address)

    # search: read to verify constraints
    search(address) do |other|
      next if other == address

      error = Subnet::Conflict.exception("Conflict with network #{other.to_cidr}")

      # cancel: delete the node to "rollback" the reservation
      subnet.delete!

      raise error
    end

    # commit
    return subnet
  end

  # @param address [IPAddr]
  def self.create(address)
    super(address.network.to_s, address: address)
  end

  # @param address [IPAddr]
  def self.delete(address)
    super(address.network.to_s)
  end
end
