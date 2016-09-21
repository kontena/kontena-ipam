require 'ipaddr'

module Addresses
  class Request < Mutations::Command
    class PoolError < StandardError

    end

    include Logging

    required do
      string :pool_id
    end

    optional do
      string :address, discard_empty: true
    end

    def validate
      @address = IPAddr.new(self.address) if self.address_present?
      @pool = AddressPool.get(pool_id)

      raise PoolError, "Pool not found: #{pool_id}" unless @pool

      if @address
        add_error(:address, :out_of_pool,
          "Given address not within pool") unless @pool.subnet.include?(@address)
      end
    rescue IPAddr::InvalidAddressError => e
      add_error(:address, :invalid, e.message)
    rescue PoolError => e
      add_error(:pool_id, :not_found, e.message)
    end

    def execute
      info "requesting address(#{@address}) in pool: #{@pool.subnet}"
      addresses = available_addresses
      info "available addresses: (#{self.pool_id}): #{addresses.size}"
      ip = nil
      if @address
        if addresses.include?(@address)
          ip = @address
        else
          add_error(:address, :not_available, 'Given address not available')
          return
        end
      else
        if addresses.size > 100
          ip = addresses[rand(0..100)]
        else
          ip = addresses[0]
        end
      end

      if ip
        etcd.set("/kontena/ipam/addresses/#{self.pool_id}/#{ip.to_s}", value: ip.to_s)
      else
        add_error(:address, :cannot_allocate, 'Cannot allocate ip, address pool is full')
        return
      end

      "#{ip.to_s}/#{@pool.subnet.length}"
    end

    # @return [Array<IPAddr>]
    def available_addresses
      reserved = reserved_addresses
      address_pool.reject { |a| reserved.include?(a)}
    end

    # @return [Array<IPAddr>]
    def address_pool
      unless self.class.pools[@pool.subnet]
        if self.pool_id == 'kontena'
          # In the default kontena network, skip first /24 block for weave expose
          self.class.pools[@pool.subnet] = @pool.subnet.to_range.to_a[256...-1]
        else
          self.class.pools[@pool.subnet] = @pool.subnet.to_range.to_a[1...-1]
        end
      end
      self.class.pools[@pool.subnet]
    end

    # @return [Array<IPAddr>]
    def reserved_addresses
      reserved_addresses = []
      response = etcd.get("/kontena/ipam/addresses/#{self.pool_id}/")
      response.children.map{|c|
        reserved_addresses << IPAddr.new(c.value)
      }
      reserved_addresses
    end

    # @return [Etcd::Client]
    def etcd
      $etcd
    end

    def self.pools
      @pools ||= {}
    end
  end
end
