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

# Workaround https://github.com/ranjib/etcd-ruby/issues/59
class RSpec::Core::Formatters::ExceptionPresenter
  def final_exception(exception, previous=[])
    cause = exception.cause
    if cause && !previous.include?(cause) && !cause.is_a?(String)
      previous << cause
      final_exception(cause, previous)
    else
      exception
    end
  end
end
