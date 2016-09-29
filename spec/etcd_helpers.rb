module EtcdHelpers
  def etcd_server
    @etcd_server ||= if ENV['ETCD_ENDPOINT']
      Etcd::TestServer.new('/kontena/ipam')
    else
      Etcd::FakeServer.new('/kontena/ipam')
    end
  end

  def etcd
      EtcdModel.etcd
  end
end
