# Configurable etcd client, with logging
class EtcdClient < Etcd::Client
  include Logging

  ENDPOINT = 'http://localhost:2379'
  PORT = 2379

  attr_accessor :uri

  def initialize(env = {})
    # we only support a single endpoint, which is a URL
    endpoint = env.fetch('ETCD_ENDPOINT', ENDPOINT).split(',')[0]
    @uri = URI(endpoint)

    super(
      host: @uri.host,
      port: @uri.port.to_i || PORT,
      use_ssl: @uri.scheme == 'https',
    )

    # test, raises if bad endpoint
    info "Connected to #{uri} version #{version} "
  end

  # Query and parse the etcd daemon version
  def version
    @version ||= JSON.parse(api_execute('/version', :get).body)
  end

  # Format Etcd::Error for logging
  #
  # @param op [Symbol] request operation
  # @param key [String] request key
  # @param opts [Hash] request options
  # @param error [Etcd::Error]
  # @return [String]
  def log_error(op, key, opts, error)
    "#{op} #{key} #{opts}: error #{error.class} #{error.cause}@#{error.index}: #{error.message}"
  end

  # Format Etcd::Response for logging
  #
  # @param op [Symbol] request operation
  # @param key [String] request key
  # @param opts [Hash] request options
  # @param response [Etcd::Response]
  # @return [String]
  def log_response(op, key, opts, response)
    if response.node.directory?
      names = response.node.children.map{ |node|
        name = File.basename(node.key)
        name += '/' if node.directory?
        name
      }
      "#{op} #{key} #{opts}: directory@#{response.etcd_index}: #{names.join ' '}"
    else
      "#{op} #{key} #{opts}: node@#{response.etcd_index}: #{response.node.value}"
    end
  end

  # Logging wrapper
  def get(key, **opts)
    response = super
  rescue Etcd::Error => error
    debug { log_error(:get, key, opts, error) }
    raise
  else
    debug { log_response(:get, key, opts, response) }
    return response
  end

  # Logging wrapper
  def set(key, **opts)
    response = super
  rescue Etcd::Error => error
    debug { log_error(:set, key, opts, error) }
    raise
  else
    debug { log_response(:set, key, opts, response) }
    return response
  end

  # Logging wrapper
  def delete(key, **opts)
    response = super
  rescue Etcd::Error => error
    debug { log_error(:delete, key, opts, error) }
    raise
  else
    debug { log_response(:delete, key, opts, response) }
    return response
  end

  # Logging wrapper
  def create_in_order(key, **opts)
    response = super
  rescue Etcd::Error => error
    debug { log_error(:create_in_order, key, opts, error) }
    raise
  else
    debug { log_response(:create_in_order, key, opts, response) }
    return response
  end
end
