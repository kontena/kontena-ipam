require 'ipaddr'

module Addresses
  class Request < Mutations::Command
    class AddressError < RuntimeError
      attr_reader :sym
      def initialize(sym)
        @sym = sym
      end
    end

    include Logging

    required do
      model :policy
      string :pool_id
    end

    optional do
      string :address, discard_empty: true
    end

    def validate
      @address = IPAddr.new(self.address) if self.address_present?

      unless @pool = AddressPool.get(pool_id)
        add_error(:pool, :not_found, "Pool not found: #{pool_id}")
      end

      if @address && @pool
        unless @pool.subnet.include?(@address)
          add_error(:address, :out_of_pool, "Address #{@address} outside of pool subnet #{@pool.subnet}")
        end
      end
    rescue IPAddr::InvalidAddressError => error
      add_error(:address, :invalid, error.message)
    end

    # Compute available addresses for allocation within pool
    #
    # @return [Array<IPAddr>]
    def available_addresses
      allocatable = @pool.allocatable
      reserved = @pool.reserved_addresses
      addresses = allocatable.list_hosts(exclude: IPSet.new(reserved))

      info "pool #{@pool} allocates from #{allocatable.to_cidr} and has #{reserved.length} reserved + #{addresses.length} available addresses"

      addresses
    end

    def execute
      if @address
        info "request static address #{@address} in pool #{@pool.id} with subnet #{@pool.subnet}"

        request_static
      else
        info "request dynamic address in pool #{@pool.id} with subnet #{@pool.subnet}"

        request_dynamic
      end
    rescue AddressError => error
      add_error(:address, error.sym, error.message)
    end

    # Allocate static @address within @pool.
    #
    # @raise AddressError if reservation failed (conflict)
    # @return [Address] reserved address
    def request_static
      # reserve
      return @pool.create_address(@address)

    rescue Address::Conflict => error
      raise AddressError.new(:conflict), "Allocation conflict for address #{@address}: #{error.message}"
    end

    # Allocate dynamic address within @pool.
    # Retries allocation on AddressConflict
    #
    # @raise AddressError if allocation failed (pool is full)
    # @return [Address] reserved address
    def request_dynamic
      # allocate
      unless allocate_address = policy.allocate_address(available_addresses)
        raise AddressError.new(:allocate), "No addresses available for allocation"
      end

      # reserve
      return @pool.create_address(allocate_address)

    rescue Address::Conflict => error
      warn "retry dynamic address allocation: #{error.message}"

      # should make progress given that we refresh the set of reserved addresses, and raise a different error if the pool is full
      retry
    end
  end
end
