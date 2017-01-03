class Address
  include Kontena::JSON::Model
  include Kontena::Etcd::Model

  etcd_path '/kontena/ipam/addresses/:pool/:id'
  json_attr :address, type: IPAddr # in A.B.C.D/X CIDR format
  json_attr :node, type: String
end
