module AddressPools
  class Request < Mutations::Command
    include Logging

    required do
      model :policy
      string :network
      boolean :ipv6, default: false, nils: true
    end

    optional do
      ipaddr :subnet, discard_empty: true
      ipaddr :iprange, discard_empty: true
    end

    def validate
      add_error(:ipv6, :not_supported, 'IPv6 is not supported') if self.ipv6

      if self.subnet && self.iprange
        unless self.subnet.include?(self.iprange)
          add_error(:iprange, :out_of_pool, "IPRange #{self.iprange} outside of pool subnet #{self.subnet}")
        end
      end
    end

    def execute
      if pool = AddressPool.get(self.network)
        info "request existing network #{network} pool with subnet=#{pool.subnet}"

      elsif self.subnet
        info "request static network #{network} pool: subnet=#{self.subnet}"

        pool = request_static
      else
        info "request dynamic network #{network} pool"

        pool = RetryHelper.with_retry(Subnet::Conflict) {
           request_dynamic
        }
      end

      return verify(pool)

    rescue AddressPool::Full => error
      add_error(:subnet, :full, error.message)

    rescue AddressPool::Invalid => error
      add_error(:pool, :invalid, error.message)

    rescue Subnet::Conflict => error
      add_error(:subnet, :conflict, "#{self.subnet} conflict: #{error}")
    end

    # Verify that the requested pool matches the requested configuration.
    # This may happen if concurrently allocating pools.
    #
    # @raise [RequestError] if the subnet already exists, but with a conflicting configuration
    # @return [AddressPool]
    def verify(pool)
      # existing network created on a remote node
      if self.subnet && pool.subnet != self.subnet
        raise AddressPool::Invalid, "pool #{pool.id} exists with subnet #{pool.subnet}, requested #{self.subnet}"
      end

      if self.iprange && pool.iprange != self.iprange
        raise AddressPool::Invalid, "pool #{pool.id} exists with iprange #{pool.iprange}, requested #{self.iprange}"
      end

      return pool
    end

    # Request for a network with a statically allocated subnet, with optional iprange.
    #
    # @raise [Subnet::Conflict]
    # @return [AddressPool]
    def request_static
      # reserve
      return AddressPool.create_or_get(self.network, subnet: self.subnet, iprange: self.iprange)
    end

    # Request for a network with a dynamically allocated subnet.
    #
    # @raise [Subnet::Conflict]
    # @return [AddressPool]
    def request_dynamic
      reserved = AddressPool.reserved_subnets

      # allocate
      unless subnet = policy.allocatable_subnets(reserved).first
        raise AddressPool::Full, "supernet #{policy.supernet} is exhausted"
      end

      # reserve
      return AddressPool.create_or_get(self.network, subnet: subnet)
    end
  end
end
