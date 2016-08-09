require 'ipaddr'

module AddressPools
  class Request < Mutations::Command

    optional do
      string :id
    end

    def execute
      etcd.delete("/kontena/ipam/pools/#{self.id}", recursive: true)
      etcd.delete("/kontena/ipam/addresses/#{self.id}", recursive: true)
    end

    # @return [Etcd::Client]
    def etcd
      $etcd
    end
  end
end
