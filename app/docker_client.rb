require 'ipaddr'
require 'docker'

require_relative 'logging'

class DockerClient
  include Logging

  # Collect all known addresses of local Docker networks using this IPAM Driver
  #
  # @yield [pool, addresses] local Docker networks with active endpoints
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

        addresses = containers.map { |container_id, container_info|
          debug "container #{container_id}: #{container_info}"

          IPAddr.new(container_info['IPv4Address'])
        }

        yield ipam_pool, addresses
      end
    end
  end

  # Collect all known addresses of local Docker containers using the given labels
  #
  def containers_addresses(pool_label, addr_label)
    pools = { }

    Docker::Container.all(all: true).each do |container|
      info = container.info
      name = info['Names'].first
      labels = info['Labels']
      pool = labels[pool_label]
      addr = labels[addr_label]

      debug "Scanning container #{name}: pool=#{pool} addr=#{addr}"

      if pool && addr
        (pools[pool] ||= []) << addr
      end
    end

    pools.each_pair do |pool, addr|
      yield pool, addr
    end
  end
end
