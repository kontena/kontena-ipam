require_relative 'server_base'

# etcd adapter for managing an etcd server for tests
class Etcd::TestServer < Etcd::ServerBase
  protected

  def initialize(root, env = ENV)
    super(root)
    @client = EtcdClient.new(env)
  end

  # Recursive walk over nodes
  def walk_node(node, &block)
    yield node

    if node.directory?
      for node in node.children
        walk_node(node, &block)
      end
    end
  end

  # Yield all etcd nodes under @root, recursively
  #
  def walk(&block)
    root = @client.get(@root, recursive: true)

    walk_node(root, &block)
  end

  public

  # Clear the etcd server database.
  #
  # Used before the each test
  def reset!
    @client.delete(@root, recursive: true)
  rescue Etcd::KeyNotFound => error
    return
  end

  # Load a hash of nodes into the store.
  # Encodes any JSON objects given as values
  # Creates any directories as needed.
  #
  # @param tree [Hash<String, Object or String>]
  def load!(tree)
    load_nodes(tree) do |key, value|
      @client.set(key, value: value)
    end
  end

  # Has the store been modified since reset()?
  #
  # This does not count failed set operations
  #
  # @return [Boolean]
  def modified?
    # TODO: implememt
  end

  # Operation log
  def logs
    # TODO: implememt
  end
end
