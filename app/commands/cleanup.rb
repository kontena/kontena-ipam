require 'optparse'

module Commands
  class Cleanup
    include Logging

    attr_accessor :quiesce_sleep
    attr_accessor :docker_networks
    attr_accessor :docker_container_pool_label
    attr_accessor :docker_container_addr_label

    def self.parse(argv)
      command = new

      OptionParser.new do |opts|
        opts.banner = "Usage: kontena-ipam-cleanup [--docker-networks]"
        opts.on("--quiesce-sleep=SECONDS", Integer, "Wait for concurrent operations to complete") do |seconds|
          command.quiesce_sleep = seconds
        end
        opts.on("--docker-networks", "Cleanup Docker networks") do |flag|
          command.docker_networks = flag
        end
        opts.on("--docker-container-pool-label", "Cleanup Docker containers by pool label") do |label|
          command.docker_container_pool_label = label
        end
        opts.on("--docker-container-address-label", "Cleanup Docker containers by address label") do |label|
          command.docker_container_addr_label = label
        end
      end.parse!(argv)

      command
    end

    def docker_client
      @docker_client ||= DockerClient.new
    end

    def docker_scan(&block)
      if self.docker_networks
        docker_client.networks_addresses &block
      elsif self.docker_container_pool_label && self.docker_container_addr_label
        docker_client.containers_addresses(self.docker_container_pool_label, self.docker_container_addr_label, &block)
      end
    end

    def execute
      etcd_index = EtcdModel.etcd.get_index

      if self.quiesce_sleep
        info "Cleanup upto etcd-index=#{etcd_index} after quiesce delay of #{self.quiesce_sleep} seconds..."
        sleep self.quiesce_sleep
      else
        info "Cleanup upto etcd-index=#{etcd_index} without any quiesce delay"
      end

      info "Cleanup addresses from Docker..."
      docker_scan do |pool, addresses|
        info "Cleanup Kontena IPAM pool #{pool} with #{addresses.length} local Docker addresses"

        Addresses::Cleanup.run!(
          pool_id: pool,
          addresses: addresses,

          etcd_index_upto: etcd_index,
        )
      end
    end
  end
end
