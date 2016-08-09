require 'ipaddr'

module Addresses
  class Release < Mutations::Command

    required do
      string :address
    end

    def validate
      resp = etcd.get("/kontena/ipam/pools/#{self.pool_id}") rescue nil
      add_error(:error, :not_found, 'Pool not found') if resp.nil?
    end

    def execute
      etcd.delete("/kontena/ipam/addresses/#{self.pool_id}/#{address}")
    end

    # @return [Etcd::Client]
    def etcd
      $etcd
    end
  end
end
