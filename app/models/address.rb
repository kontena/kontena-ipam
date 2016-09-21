class Address
  include JSONModel
  include EtcdModel

  etcd_path '/kontena/ipam/addresses/:pool/:id'
  json_attr :address, type: IPAddr # in A.B.C.D/X CIDR format

  attr_accessor :pool, :id, :address
end
