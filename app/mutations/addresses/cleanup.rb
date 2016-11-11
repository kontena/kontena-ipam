module Addresses
  class Cleanup < Mutations::Command
    include Logging
    include NodeHelper

    required do
      string :pool_id
      array :addresses do
        ipaddr
      end
    end

    optional do
      integer :etcd_index_upto
    end

    def validate
      @node = node
      @ipset = IPSet.new(self.addresses.map{|ipaddr| ipaddr.to_host})

      unless @pool = AddressPool.get(self.pool_id)
        add_error(:pool_id, :not_found, "AddressPool not found: #{self.pool_id}")
      end

      if @pool
        for address in @ipset.addrs
          unless @pool.subnet.include?(address)
            add_error(:addresses, :out_of_pool, "Address #{address} outside of pool subnet #{@pool.subnet}")
          end
        end
      end
    end

    def execute
      debug "checking pool #{@pool.id} for node=#{@node} with active_addresses=#{@ipset.length}"

      @pool.list_addresses.each do |address|
        debug "checking address #{address.address.to_host}: #{address.inspect}"

        if address.node != @node
          debug "...not managed by this node, skipping"

        elsif @pool.gateway.to_host == address.address.to_host
          debug "...gateway, skipping"

        elsif @ipset.include?(address.address.to_host)
          debug "..still in use, skipping"

        elsif self.etcd_index_upto && address.etcd_modified?(after_index: self.etcd_index_upto)
          debug "...recently allocated, skipping"

        else
          warn "Cleanup unused address #{address.address.to_host}"
          address.delete!
        end
      end
    end
  end
end
