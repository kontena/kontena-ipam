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

      add_error(:pool_id, :reserved_addresses, "AddressPool #{pool_id} has still reserved addresses") unless @pool.empty?

    end

    def execute
      @pool.delete!
    end
  end
end
