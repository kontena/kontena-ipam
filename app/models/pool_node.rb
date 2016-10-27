# A node lease on an AddressPool
class PoolNode
  include JSONModel
  include EtcdModel

  etcd_path '/kontena/ipam/pool-nodes/:pool/:node'
end
