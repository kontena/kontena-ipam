require 'ipaddr'
require 'docker'
require 'socket'

require_relative 'boot'
require_relative 'logging'
require_relative 'node_helper'

class AddressCleanup
  include Logging
  include NodeHelper

  # @param node_id [String]
  # @param reserver_addresses [Array<String>]
  def initialize(reserved_addresses = [])
    @node = node
    @reserved_addresses = reserved_addresses.map { |a| IPAddr.new(a).to_host }
  end

  def cleanup
    info "starting cleanup routine"
    debug "locally known addresses: #{@reserved_addresses.size}"
    AddressPool.list.each { |pool|
      debug "checking pool: #{pool.id}"
      pool.list_addresses.each { |address|
        debug "checking address: #{address.address.to_host}..."
        if address.node == @node
          if @reserved_addresses.include?(address.address.to_host) || pool.gateway.to_host == address.address.to_host
            debug '..still in use or gateway, skipping.'
            next
          else
            warn "found reserved address #{address.address.to_host} no longer known by local Docker. Removing the reservation."
            address.delete!
          end
        else
          debug "...not managed by this node, skipping."
          next
        end
      }

    }
    info "cleanup done"
  end

end
