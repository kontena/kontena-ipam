require 'ipaddr'
require 'net/ping/icmp'

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
      address = @pool.get_address(self.address)

      if !address
        info "Skip missing address=#{self.address} in pool=#{@pool.id}"

      elsif address.address.to_host == @pool.gateway.to_host
        info "Skip gateway address=#{address.id} in pool=#{@pool.id}"

      elsif ping?(address.address)
        message = "Skip zombie address=#{address.id} in pool=#{@pool.id} that still responds to ping"
        warn message
        add_error(:address, :zombie, message)
      else
        info "Delete address=#{address.id} in pool=#{@pool.id}"
        address.delete!
      end
    end

    # @param [IPAddr] ip address to ping
    # @raise [RuntimeError] requires root privileges
    #@return [Boolean]
    def ping?(ip_address)
      icmp = Net::Ping::ICMP.new(ip_address.to_s, 0, 1)
      icmp.ping?
    end
  end
end
