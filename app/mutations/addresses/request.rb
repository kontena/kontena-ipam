require 'ipaddr'

module Addresses
  class Request < Mutations::Command
    include Logging

    required do
      string :pool_id
    end

    optional do
      string :address
    end

    def validate
      resp = etcd.get("/kontena/ipam/pools/#{self.pool_id}") rescue nil
      add_error(:error, :not_found, 'Pool not found') if resp.nil?
      @pool = resp.value unless resp.nil?
      if @pool && self.address
        pool = IPAddr.new(@pool)
        add_error(:error, :address_not_within_pool,
          "Given address not within pool") unless pool.include?(addr)
      end
    rescue IPAddr::InvalidAddressError
       add_error(:error, :address_not_valid, "Given address not valid")
    end

    def execute
      addresses = available_addresses
      info "available (#{self.pool_id}): #{addresses.size}"
      ip = nil
      if self.address
        if addresses.include?(addr)
          ip = self.address
        else
          add_error(:error, :not_available, 'Given address already taken')
        end
      else
        if addresses.size > 100
          ip = addresses[rand(0..100)]
        else
          ip = addresses[0]
        end
      end

      if ip
        etcd.set("/kontena/ipam/addresses/#{self.pool_id}/#{ip}", value: ip)
      else
        add_error(:error, :cannot_allocate, 'Cannot allocate ip, address pool is full')
      end

      "#{ip}/#{@pool.split('/')[1]}"
    end

    # @return [Array<IPAddr>]
    def available_addresses
      address_pool - reserved_addresses
    end

    # @return [Array<IPAddr>]
    def address_pool
      unless self.class.pools[@pool]
        if self.pool_id == 'kontena'
          # In the default kontena network, skip first /24 block for weave expose
          self.class.pools[@pool] = IPAddr.new(@pool).to_range.to_a[256..-1].map{|ip| ip.to_s }
        else
          self.class.pools[@pool] = IPAddr.new(@pool).to_range.to_a[1..-1].map{|ip| ip.to_s }
        end
      end
      self.class.pools[@pool]
    end

    # @return [Array<IPAddr>]
    def reserved_addresses
      reserved_addresses = []
      response = etcd.get("/kontena/ipam/addresses/#{self.pool_id}/")
      response.children.map{|c|
        reserved_addresses << c.value
      }
      reserved_addresses
    end

    # @return [IPAddr]
    def addr
      IPAddr.new("#{self.address}/#{@pool.split('/')[1]}")
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
