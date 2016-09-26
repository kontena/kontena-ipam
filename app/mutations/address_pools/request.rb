module AddressPools
  class RequestError < RuntimeError
    attr_reader :param, :sym
    def initialize(param, sym)
      @param = param
      @sym = sym
    end
  end

  class Request < Mutations::Command
    include Logging

    required do
      model :policy
      string :network
      boolean :ipv6, default: false, nils: true
    end

    optional do
      string :subnet, discard_empty: true
      string :iprange, discard_empty: true
    end

    def validate
      add_error(:ipv6, :not_supported, 'IPv6 is not supported') if self.ipv6
      @subnet = IPAddr.new(subnet) if subnet_present? rescue add_error(:subnet, :invalid, "Invalid address")
      @iprange = IPAddr.new(iprange) if iprange_present? rescue add_error(:iprange, :invalid, "Invalid address")

      if @subnet && @iprange
        unless @subnet.include?(@iprange)
          add_error(:iprange, :out_of_pool, "IPRange #{@iprange} outside of pool subnet #{@subnet}")
        end
      end
    end

    def execute
      if pool = AddressPool.get(self.network)
        info "request existing network #{network} pool with subnet=#{pool.subnet}"

      elsif @subnet
        info "request static network #{network} pool: subnet=#{@subnet}"

        pool = request_static
      else
        info "request dynamic network #{network} pool"

        pool = request_dynamic
      end

      return verify(pool)
    rescue RequestError => error
      add_error(error.param, error.sym, error.message)
    end

    # Verify that the requested pool matches the requested configuration.
    # This may happen if concurrently allocating pools.
    #
    # @raise [RequestError] if the subnet already exists, but with a conflicting configuration
    # @return [AddressPool]
    def verify(pool)
      # existing network created on a remote node
      if @subnet && pool.subnet != @subnet
        raise RequestError.new(:subnet, :config), "pool #{pool.id} exists with subnet #{pool.subnet}, requested #{@subnet}"
      end

      if @iprange && pool.iprange != @iprange
        raise RequestError.new(:iprange, :config), "pool #{pool.id} exists with iprange #{pool.iprange}, requested #{@iprange}"
      end

      return pool
    end

    # Request for a network with a statically allocated subnet, with optional iprange.
    #
    # @raise [RequestError]
    # @return [AddressPool]
    def request_static
      # reserve
      return AddressPool.create_or_get(self.network, subnet: @subnet, iprange: @iprange)

    rescue Subnet::Conflict => error
      raise RequestError.new(:subnet, :conflict), "#{@subnet} conflict: #{error}"
    end

    # Request for a network with a dynamically allocated subnet.
    #
    # @raise [RequestError]
    # @return [AddressPool]
    def request_dynamic
      reserved = AddressPool.reserved_subnets

      # allocate
      unless subnet = policy.allocatable_subnets(reserved).first
        raise RequestError.new(:subnet, :allocate), "supernet #{policy.supernet} is exhausted"
      end

      # reserve
      return AddressPool.create_or_get(self.network, subnet: subnet)

    rescue Subnet::Conflict => error
      warn "retry on subnet conflict: #{error}"
      retry
    end
  end
end
