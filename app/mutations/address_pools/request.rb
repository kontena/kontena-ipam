module AddressPools
  class Request < Mutations::Command
    include Logging

    required do
      model :policy
      string :network
    end

    optional do
      string :pool
    end

    def execute
      info "requesting pool with pool: #{self.pool}, network: #{self.network}"
      item = etcd.get("/kontena/ipam/pools/#{self.network}") rescue nil
      if item
        address_pool = AddressPool.new(self.network, item.value)
      else
        reserved_pool = reserve_pool(self.network, self.pool.to_s)
        add_error(:error, :duplicate, 'Pool address already in use') if reserved_pool.nil?
        address_pool = AddressPool.new(self.network, reserved_pool)
      end
      address_pool
    end

    # @param [String] id
    # @param [String] pool
    def reserve_pool(id, pool)
      info "reserve pool, id: #{id}, pool: #{pool}"
      if pool.empty?
        generate_default_pool(id)
      else
        reserve_requested_pool(id, pool)
      end
    end

    def generate_default_pool(pool_id)
      reserved_pools = self.reserved_pools
      pool = policy.allocate_subnet(reserved_pools)

      unless pool.nil?
        etcd.set("/kontena/ipam/pools/#{pool_id}", value: pool.to_cidr)
        etcd.set("/kontena/ipam/addresses/#{pool_id}", dir: true)

        pool.to_cidr
      end
    end

    # @param [String] pool_id
    # @param [String] pool
    # @return [String] pool
    def reserve_requested_pool(pool_id, pool)
      ip = IPAddr.new(pool)
      reserved_pools = self.reserved_pools
      reserved_pool = nil
      unless reserved_pools.any? { |p| p.include?(ip) || ip.include?(p) }
        etcd.set("/kontena/ipam/pools/#{pool_id}", value: pool)
        etcd.set("/kontena/ipam/addresses/#{pool_id}", dir: true)
        reserved_pool = pool
      end

      reserved_pool
    end

    # @return [Array<IPAddr>]
    def reserved_pools
      reserved_pools = []
      response = etcd.get("/kontena/ipam/pools/")
      response.children.map{|c|
        reserved_pools << IPAddr.new(c.value)
      }

      reserved_pools
    end

    # @return [Etcd::Client]
    def etcd
      $etcd
    end
  end
end
