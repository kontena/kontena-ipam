require 'ipaddr'
require 'docker'

require_relative 'logging'

class DockerClient
  include Logging

  # Collect all known addresses of local Docker networks using this IPAM Driver
  #
  # @yield [pool, address] active endpoint on Docker network
  # @yieldparam pool [String] name of Kontena IPAM pool
  # @yieldparam addresses [Array<IPAddr>] active container endpoint addresses, not including gateway or auxiliar addresses
  def networks_addresses
    Docker::Network.all.each do |network|
      network_info = network.json
      name = network_info['Name']
      ipam_driver = network_info.dig('IPAM', 'Driver')
      ipam_pool = network_info.dig('IPAM', 'Options', 'network')
      containers = network_info['Containers']

      debug "Scanning network: #{name}"

      if ipam_driver != 'kontena-ipam'
        debug "Skip non-kontena network: IPAM.Driver=#{ipam_driver}"

      elsif !ipam_pool
        warn "Skip Kontena IPAM network with missing network= option for pool"

      else
        debug "Kontena IPAM network #{name}: pool=#{ipam_pool} containers=#{containers.size}"

        containers.each { |container_id, container_info|
          debug "container #{container_id}: #{container_info}"

          yield ipam_pool, IPAddr.new(container_info['IPv4Address'])
        }
      end
    end
  end
end
