require 'ipaddr'

module Addresses
  class Request < Mutations::Command
    include Logging

    required do
      string :pool_id, default: 'kontena'
    end

    def validate
      resp = etcd.get("/kontena/ipam/pools/#{self.pool_id}") rescue nil
      add_error(:error, :not_found, 'Pool not found') if resp.nil?

      @pool = resp.value
    end

    def execute
      addresses = available_addresses
      info "requesting address in pool: #{@pool}"
      info "available (#{self.pool_id}): #{addresses.size}"
      if addresses.size > 100
        ip = addresses[rand(0..100)]
      else
        ip = addresses[0]
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
        self.class.pools[@pool] = IPAddr.new(@pool).to_range.to_a[1..-1].map{|ip| ip.to_s }
      end
      self.class.pools[@pool]
    end

    # @return [Array<IPAddr>]
    def reserved_addresses
      reserved_addresses = []
      response = etcd.get("/kontena/ipam/addresses/#{self.pool_id}/")
      subnet_size = @pool.split('/')[1]
      response.children.map{|c|
        reserved_addresses << c.value
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
