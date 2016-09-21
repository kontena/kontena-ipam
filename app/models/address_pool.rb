class AddressPool
  include JSONModel
  include EtcdModel

  etcd_path '/kontena/ipam/pools/:id'
  json_attr :subnet, type: IPAddr
  json_attr :iprange, type: IPAddr

  attr_accessor :id, :subnet, :iprange
end
