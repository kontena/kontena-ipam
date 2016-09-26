module AddressPools
  class SubnetError < RuntimeError
    attr_reader :sym
    def initialize(sym)
      @sym = sym
    end
  end
  class IPRangeError < RuntimeError
    attr_reader :sym
    def initialize(sym)
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
    end

    def execute
      if pool = AddressPool.get(network)
        info "request existing network #{network} pool"

        # existing network created on a remote node
        if subnet && pool.subnet != subnet
          raise SubnetError.new(:config), "network #{network} already exists with subnet #{pool.subnet}, requested #{@subnet}"
        end

        if iprange && pool.iprange != iprange
          raise IPRangeError.new(:config), "network #{network} already exists with iprange #{pool.iprange}, requested #{@iprange}"
        end

        return pool
      elsif @subnet
        info "request static network #{network} pool: subnet=#{@subnet}"

        # statically allocated network
        if conflict = reserved_subnets.find { |s| s if s.include?(@subnet) || @subnet.include?(s) }
          raise SubnetError.new(:conflict), "#{subnet} conflict with #{conflict.to_cidr}"
        end

        return pool if pool = reserve_pool(@subnet)

        # XXX: can we just retry and return the existing network?
        fail "concurrent network create"
      else
        info "request dynamic network #{network} pool"

        # dynamically allocated network
        policy.allocate_subnets(reserved_subnets) do |subnet|
          return pool if pool = reserve_pool(subnet)

          # XXX: can we just retry and return the existing network?
          fail "concurrent network create"
        end

        raise SubnetError.new(:allocate), "supernet #{policy.supernet} is exhausted"
      end
    rescue SubnetError => error
      add_error(:subnet, error.sym, error.message)
    rescue IPRangeError => error
      add_error(:iprange, error.sym, error.message)
    end

    # Returns currently allocated subnets.
    #
    # This is not transactional; new subnets may appear after listing them
    #
    # @return [Array<IPAddr>] existing subnet allcoations
    def reserved_subnets
        AddressPool.list.map{|pool| pool.subnet}
    end

    # Reserve and return a pool using the given subnet as a new AddressPool,
    # or return nil if a conflicting pool already exists.
    #
    # This conflicts on the network name, not the subnet.
    #
    # @return [AddressPool] or nil
    def reserve_pool(subnet)
      pool = AddressPool.create(network,
        subnet: subnet,
        iprange: @iprange,
      )

      if pool
        $etcd.set("/kontena/ipam/addresses/#{pool.id}/", dir: true)
      end

      pool
    end
  end
end
