require 'ipaddr'

module Addresses
  class Release < Mutations::Command
    include Logging

    required do
      string :pool_id
      string :address
    end

    def validate
      @address = IPAddr.new(self.address)

      unless @pool = AddressPool.get(self.pool_id)
        add_error(:pool_id, :not_found, "AddressPool not found: #{self.pool_id}")
      end

      if @address && @pool
        unless @pool.subnet.include?(@address)
          add_error(:address, :out_of_pool, "Address #{@address} outside of pool subnet #{@pool.subnet}")
        end
      end

    rescue IPAddr::InvalidAddressError => e
      add_error(:address, :invalid, e.message)
    end

    def execute
      info "releasing address: #{@address} in pool: #{@pool_id}"

      if address = @pool.get_address(@address)
        address.delete!
      end
    end
  end
end
