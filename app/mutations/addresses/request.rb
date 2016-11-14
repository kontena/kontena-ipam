require 'ipaddr'

module Addresses
  class Request < Mutations::Command
    include Logging
    include RetryHelper

    required do
      model :policy
      string :pool_id
    end

    optional do
      ipaddr :address, discard_empty: true
    end

    def validate
      unless @pool = AddressPool.get(pool_id)
        add_error(:pool, :not_found, "Pool not found: #{pool_id}")
      end

      if self.address && @pool
        unless @pool.subnet.include?(self.address)
          add_error(:address, :out_of_pool, "Address #{self.address} outside of pool subnet #{@pool.subnet}")
        end
      end
    end

    def execute
      if self.address
        address = request_static

        info "Request static address in pool=#{@pool.id} with subnet=#{@pool.subnet}: address=#{address.id}"
      else
        # should make progress given that we refresh the set of reserved addresses, and raise a different error if the pool is full
        address = with_retry(Address::Conflict) do
          request_dynamic
        end

        info "Request dynamic address in pool=#{@pool.id} with subnet=#{@pool.subnet}: address=#{address.id}"
      end

      return address
    rescue Address::Conflict => error
      add_error(:address, :conflict, "Allocation conflict for address=#{self.address}: #{error}")

    rescue AddressPool::Full => error
      add_error(:pool, :full, error.message)
    end

    # Allocate static self.address within @pool.
    #
    # @raise Address::Conflict
    # @return [Address] reserved address
    def request_static
      # reserve
      return @pool.create_address(self.address)
    end

    # Allocate dynamic address within @pool.
    #
    # @raise Address::Conflict
    # @raise AddressPool::Full
    # @return [Address] reserved address
    def request_dynamic
      available = @pool.available_addresses.first(100).to_a

      info "Allocate dynamic address in pool=#{@pool.id} from range=#{@pool.allocation_range} with available=#{available.size}#{available.size >= 100 ? '+' : ''} addresses"

      # allocate
      unless allocate_address = policy.allocate_address(available)
        raise AddressPool::Full, "No addresses available for allocation in pool #{@pool}"
      end

      # reserve
      return @pool.create_address(allocate_address)
    end
  end
end
