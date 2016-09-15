module AddressPools
  class SubnetAllocationError < StandardError

  end
  class SubnetMismatchError < SubnetAllocationError

  end
  class SubnetConflictError < SubnetAllocationError

  end
  class SubnetExhaustionError < SubnetAllocationError

  end

  class Request < Mutations::Command
    include Logging

    required do
      model :policy
      string :network
    end

    optional do
      string :subnet, discard_empty: true
    end

    def validate
      @subnet = IPAddr.new(subnet) if subnet_present?
    rescue IPAddr::InvalidAddressError => e
      add_error(:subnet, :invalid, e.message)
    end

    def execute
      if pool = AddressPool.get(network)
        info "request existing network #{network} pool"

        # existing network created on a remote node
        if subnet && pool.subnet != subnet
          raise SubnetMismatchError, "network #{network} already exists with subnet #{pool.subnet}, asked for #{subnet}"
        end

        return pool
      elsif @subnet
        info "request static network #{network} pool: subnet=#{@subnet}"

        # statically allocated network
        if conflict = reserved_subnets.find { |s| s if s.include?(@subnet) || @subnet.include?(s) }
          raise SubnetConflictError, "#{subnet} conflict with #{conflict.to_cidr}"
        end

        return pool if pool = reserve_pool(@subnet)

        # XXX: can we just retry and return the existing network?
        fail "concurrent network create"
      else
        info "request dynamic network #{network} pool"

        # dynamically allocated network
        policy.allocate_subnets(reserved_subnets) do |subnet|
          return pool if pool = reserve_pool(subnet)

          # XXX: can we just retry and return the existing network?
          fail "concurrent network create"
        end

        raise SubnetExhaustionError, "supernet #{policy.supernet} is exhausted"
      end
    rescue SubnetMismatchError => e
      add_error(:subnet, :mismatch, e.message)
    rescue SubnetConflictError => e
      add_error(:subnet, :conflict, e.message)
    rescue SubnetAllocationError => e
      add_error(:subnet, :allocate, e.message)
    end

    # Returns currently allocated subnets.
    #
    # This is not transactional; new subnets may appear after listing them
    #
    # @return [Array<IPAddr>] existing subnet allcoations
    def reserved_subnets
        AddressPool.list.map{|pool| pool.subnet}
    end

    # Reserve and return a pool using the given subnet as a new AddressPool,
    # or return nil if a conflicting pool already exists.
    #
    # This conflicts on the network name, not the subnet.
    #
    # @return [AddressPool] or nil
    def reserve_pool(subnet)
      pool = AddressPool.create(network,
        subnet: subnet,
      )

      if pool
        $etcd.set("/kontena/ipam/addresses/#{pool.id}/", dir: true)
      end

      pool
    end
  end
end
