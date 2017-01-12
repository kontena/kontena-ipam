# A node lease on an AddressPool
class PoolNode
  include Kontena::JSON::Model
  include Kontena::Etcd::Model

  etcd_path '/kontena/ipam/pool-nodes/:pool/:node'
end
