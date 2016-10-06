require 'ipaddr'
require 'docker'
require 'socket'

require_relative 'boot'
require_relative 'logging'

class AddressCleanup
  include Logging

  def initialize(node_id = nil)
    @node = node_id || ENV['NODE_ID'] || Socket.gethostname
  end

  def self.run_async
    cleanup = AddressCleanup.new
    t = Thread.new {
      loop do
        cleanup.cleanup
        sleep(60)
      end
    }
  end


  def cleanup
    info "starting cleanup routine"
    known_addresses = local_addresses
    debug "locally known addresses: #{known_addresses}"
    AddressPool.list.each { |pool|
      debug "checking pool: #{pool.id}"
      pool.list_addresses.each { |address|
        debug "checking address: #{address.address.to_host}..."
        if address.node == @node
          # TODO Uncomment the gateway part when gateway stuff merget into master
          if known_addresses.include?(address.address.to_host) #|| pool.gateway.to_host == address.address.to_host
            debug '..still in use or gateway, skipping.'
            next
          else
            debug "found reserved address #{address.address.to_host} no longer known by local Docker. Removing the reservation."
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
  def local_addresses
    local_addresses = []

    Docker::Network.all.each { |network|
      debug "checking network #{network.json}"
      nw_json = network.json
      if nw_json.dig('IPAM', 'Driver') == 'kontena-ipam'
        debug "Kontena ipam managed network, checking containers (#{nw_json.dig('Containers').size})"
        nw_json.dig('Containers').each { |c, value|
          debug "container: #{c}"
          debug "value: #{value}"
          address = IPAddr.new(value.dig('IPv4Address')) rescue nil
          local_addresses << address if address
        }
      end

      local_addresses.map!{ |a| a.to_host }
    }
    info "Collected #{local_addresses.size} local addresses managed by Kontena ipam driver"
    local_addresses
  end
end
