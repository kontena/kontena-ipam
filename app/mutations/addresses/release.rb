require 'ipaddr'

module Addresses
  class Release < Mutations::Command
    include Logging

    required do
      string :pool_id
      ipaddr :address
    end

    def validate
      unless @pool = AddressPool.get(self.pool_id)
        add_error(:pool_id, :not_found, "AddressPool not found: #{self.pool_id}")
      end

      if self.address && @pool
        unless @pool.subnet.include?(self.address)
          add_error(:address, :out_of_pool, "Address #{self.address} outside of pool subnet #{@pool.subnet}")
        end
      end
    end

    def execute
      info "releasing address: #{self.address} in pool: #{@pool_id}"
      address = @pool.get_address(@address)
      if address && address.to_host != @pool.gateway.to_host
        address.delete!
      end
    end
  end
end
