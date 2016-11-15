require 'optparse'

module Commands
  class Cleanup
    include Logging

    attr_accessor :quiesce_sleep
    attr_accessor :pool
    attr_accessor :docker_networks

    def self.parse(argv)
      command = new

      OptionParser.new do |opts|
        opts.banner = "Usage: kontena-ipam-cleanup [--docker-networks]"
        opts.on("--quiesce-sleep=SECONDS", Integer, "Wait for concurrent operations to complete") do |seconds|
          command.quiesce_sleep = seconds
        end
        opts.on("--pool=POOL", "Scan pool for cleanup even if not in use by any containers") do |pool|
          command.pool = pool
        end
        opts.on("--docker-networks", "Scan Docker network endpoints") do |flag|
          command.docker_networks = flag
        end
      end.parse!(argv)

      command
    end

    def docker_client
      @docker_client ||= DockerClient.new
    end

    def docker_scan(&block)
      pools = { }

      if self.pool
        pools[self.pool] = []
      end

      if self.docker_networks
        docker_client.networks_addresses do |pool, address|
          (pools[pool] ||= []) << address
        end
      end

      pools.each_pair &block
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
