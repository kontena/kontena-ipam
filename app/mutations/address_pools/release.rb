require 'ipaddr'

module AddressPools
  class Release < Mutations::Command
    include Logging

    required do
      string :id
    end

    def execute
      info "AddressPools::Relase: #{self.inputs}"
      etcd.delete("/kontena/ipam/pools/#{self.id}", recursive: true) rescue nil
      etcd.delete("/kontena/ipam/addresses/#{self.id}", recursive: true) rescue nil
    end

    # @return [Etcd::Client]
    def etcd
      $etcd
    end
  end
end
