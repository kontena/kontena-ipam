class Etcd::ServerBase
  protected

  # Setup, requires reset() before use
  #
  # @see #reset
  def initialize(root)
    @root = root
  end

  def load_nodes(tree)
    for key, value in tree
      if key.end_with? '/'
        key = key.chomp('/')

        fail "Value given for directory" if value

        yield key, :directory
      else
        value = value.to_json unless value.is_a? String

        yield key, value
      end
    end
  end

  public

  # Reset database to empty state for key
  #
  # Initializes an unmodified, empty database.
  def reset!
    fail NotImplementedError
  end

  # Load a hash of nodes into the store.
  # Encodes any JSON objects given as values
  # Creates any directories as needed.
  #
  # @param tree [Hash<String, Object or String>]
  def load!(tree)
    fail NotImplementedError
  end

  # Has the store been modified since reset()?
  #
  # This does not count failed set operations
  #
  # @return [Boolean]
  def modified?
    fail NotImplementedError
  end

  # Operation log
  #
  # @return [Array<Symbol, String>] operation, key pairs
  def logs
    fail NotImplementedError
  end

  # List all keys, including the root, any dirs, and any nodes.
  # Dir keys are rendered with a trailing /
  #
  # @return [Set<String>] key paths
  def list
    set = Set.new()

    walk do |node|
      path = node.key || '/'

      if node.directory?
        path += '/' unless path == '/'

        set.add(path)
      else
        set.add(path)
      end
    end

    set
  end

  # Dump all nodes to a hash of JSON-decoded objects
  #
  # @return [Hash<String, JSON>]
  def nodes
    tree = {}

    walk do |node|
      if !node.directory?
        tree[node.key] = JSON.parse(node.value)
      end
    end

    tree
  end
end
