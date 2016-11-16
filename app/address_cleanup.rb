require 'ipaddr'
require 'docker'
require 'socket'

require_relative 'boot'
require_relative 'logging'
require_relative 'node_helper'

class AddressCleanup
  include Logging
  include NodeHelper

  def initialize()
    @node = node
  end

  def cleanup_docker_networks
    cleanup(local_docker_known_addresses)
  end

  def cleanup_known_addresses(reserved_addresses = [])
    cleanup(reserved_addresses.map { |a| IPAddr.new(a).to_host })
  end

  private

  def cleanup(reserved_addresses)
    info "starting cleanup routine for node: #{@node}"
    debug "locally known addresses: #{reserved_addresses.size}"
    AddressPool.list.each { |pool|
      debug "checking pool: #{pool.id}"
      pool.list_addresses.each { |address|
        debug "checking address: #{address.address.to_host}..."
        debug "address.node: #{address.node.inspect}"
        debug "node: #{@node.inspect}"
        if address.node == @node
          if reserved_addresses.include?(address.address.to_host) || pool.gateway.to_host == address.address.to_host
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

  # Collect all known addresses of local docker networks using this ipam
   def local_docker_known_addresses
    local_addresses = []

    Docker::Network.all.each { |network|
      debug "checking network #{network.json}"
      nw_json = network.json
      if nw_json.dig('IPAM', 'Driver') == 'kontena-ipam'
        debug "Kontena ipam managed network, checking containers (#{nw_json.dig('Containers').size})"
        nw_json.dig('Containers').each { |c, value|
          debug "container: #{c}"
          debug "value: #{value}"
          address = IPAddr.new(value.dig('IPv4Address'))
          local_addresses << address if address
        }
      end

      local_addresses.map!{ |a| a.to_host }
    }
    info "Collected #{local_addresses.size} local Docker network addresses managed by Kontena ipam driver"
    local_addresses
   end

end
