require 'ipaddr'

module AddressPools
  class Release < Mutations::Command
    include Logging

    required do
      string :pool_id
    end

    def validate
      unless @pool = AddressPool.get(pool_id)
        add_error(:pool_id, :notfound, "AddressPool not found: #{pool_id}")
        return
      end

      reserved_addresses = @pool.list_addresses
      if reserved_addresses.size == 1
        # Should be only the gw reserved
        unless @pool.gateway.to_host == reserved_addresses.first.address.to_host
          add_error(:pool, :gateway, "Expected gateway to be the only reserved address, instead had: #{reserved_addresses.first.address.to_host}")
        end
      else
        add_error(:pool_id, :reserved_addresses, "AddressPool #{pool_id} has still #{reserved_addresses.size} reserved addresses")
      end

    end

    def execute
      @pool.delete!
    end
  end
end
