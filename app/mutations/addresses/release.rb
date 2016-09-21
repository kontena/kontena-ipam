require 'ipaddr'

module Addresses
  class Release < Mutations::Command
    include Logging

    required do
      string :address
      string :pool_id
    end

    def validate
      resp = etcd.get("/kontena/ipam/pools/#{self.pool_id}") rescue nil
      add_error(:error, :not_found, 'Pool not found') if resp.nil?
    end

    def execute
      info "releasing address: #{self.address} in pool: #{self.pool_id}"
      etcd.delete("/kontena/ipam/addresses/#{self.pool_id}/#{self.address}")
    end

    # @return [Etcd::Client]
    def etcd
      $etcd
    end
  end
end
