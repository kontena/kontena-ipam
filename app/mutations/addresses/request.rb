require 'ipaddr'

module Addresses
  class Request < Mutations::Command
    include Logging

    required do
      string :pool_id
    end

    optional do
      model :address, class: IPAddr
    end

    def validate
      resp = etcd.get("/kontena/ipam/pools/#{self.pool_id}") rescue nil
      add_error(:error, :not_found, 'Pool not found') if resp.nil?
      @pool = IPAddr.new(resp.value) unless resp.nil?
      if @pool && self.address
        add_error(:error, :address_not_within_pool,
          "Given address not within pool") unless @pool.include?(self.address)
      end
    end

    def execute
      info "requesting address(#{self.address}) in pool: #{@pool}"
      addresses = available_addresses
      info "available addresses: (#{self.pool_id}): #{addresses.size}"
      ip = nil
      if self.address
        if addresses.include?(self.address.to_s)
          ip = self.address
        else
          add_error(:error, :not_available, 'Given address not available')
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
        add_error(:error, :cannot_allocate, 'Cannot allocate ip, address pool is full')
        return
      end

      "#{ip.to_s}/#{@pool.length}"
    end

    # @return [Array<IPAddr>]
    def available_addresses
      reserved = reserved_addresses
      address_pool.reject { |a| reserved.include?(a)}
    end

    # @return [Array<IPAddr>]
    def address_pool
      unless self.class.pools[@pool]
        if self.pool_id == 'kontena'
          # In the default kontena network, skip first /24 block for weave expose
          self.class.pools[@pool] = @pool.to_range.to_a[256...-1]
        else
          self.class.pools[@pool] = @pool.to_range.to_a[1...-1]
        end
      end
      self.class.pools[@pool]
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
