# Map an object to an etcd path, with a JSON value
module EtcdModel
  # Configure global etcd client to use
  #
  # @param etcd [Etcd::Client]
  def self.etcd=(etcd)
    @@etcd = etcd
  end

  # @return [Etcd::Client]
  def self.etcd
    @@etcd
  end

  # @return [Etcd::Client]
  def etcd
    @@etcd
  end

  # Set operation failed with a conflict
  class Conflict < StandardError

  end

  # A structured etcd key path, consisting of String and Symbol components.
  #
  # @attr_reader path [Array<String, Symbol>] normalized path components, which are path-component strings, or symbols for instance variables
  class Schema
    attr_reader :path

    # Normalize path from String to internal @path
    #
    # @raise ArgumentError
    # @param path [String] etcd key schema path definition with :symbol placeholders
    def initialize(path)
      raise ArgumentError, "etcd_key path must start with a /" unless path.start_with? '/'

      # normalize to an Array of Strings and Symbols
      @path = path[1..-1].split('/', -1).map { |part|
        if part.empty?
          raise ArgumentError, "invalid path component: #{part}"
        elsif part.start_with? ':'
          part[1..-1].to_sym
        else
          part
        end
      }
    end

    # Returns string representation of schema path, with symbol placeholders.
    #
    # @return [String]
    def to_s
      '/' + @path.map { |part|
        if part.is_a? String
          part
        elsif part.is_a? Symbol
          part.inspect
        else
          fail "Invalid path part: #{part}"
        end
      }.join('/')
    end

    # Yield each key symbol for object.
    #
    # @return [Array<String>] key values
    def each_key()
      for part in @path
        if part.is_a? String

        elsif part.is_a? Symbol
          yield part
        else
          raise "Invalid path part: #{part}"
        end
      end
    end

    # Yield each key-value pair for given values.
    #
    # @param key_values [Array<String>] key values for etcd path
    # @yield [sym, value]
    # @yieldparam sym [Symbol] instance variable symbol for key
    # @yieldparam value [String] instance variable value for key
    def each_key_value(*values)
      each_key do |sym|
        value = values.shift

        raise ArgumentError, "Missing key argument for #{sym.inspect}" unless value

        yield sym, value
      end

      raise ArgumentError, "Extra key arguments" unless values.empty?
    end

    # Returns full etcd path for object, using key values from instance variables.
    #
    # @yield [sym] Get key instance variable values
    # @yieldparam sym [Symbol] key instance variable name
    # @yieldreturn [String] etcd key value
    # @return [String] etcd path
    def path_with_keys()
      path = []

      for part in @path
        if part.is_a? String
          path << part
        elsif part.is_a? Symbol
          path << (yield part)
        else
          raise "Invalid path part: #{part}"
        end
      end
      '/' + path.join('/')
    end

    # Returns as much of the leading path as possible, for the given number of keys.
    # If the full set if keys is given, returns a full path.
    # If a partial set of keys is given, returns a directory path ending in /
    #
    # @param key [String] key values, may be shorter than the full key
    # @raise ArgumentError if an invalid key value is given, or if too many keys are given
    # @return [String] etcd path, ending in / for a partial prefix
    def prefix(*key)
      path = []
      partial = false

      for part in @path
        if part.is_a? String
          path << part
        elsif part.is_a? Symbol
          if key.empty?
            partial = true
            break
          else
            part = key.shift

            # guard against accidential broad prefixes
            raise ArgumentError, "Invalid key prefix value: #{part}" if part.nil? || part.empty?

            path << part
          end
        else
          raise "Invalid path part: #{part}"
        end
      end

      raise ArgumentError, "Etcd key is too long" if !key.empty?

      if partial
        '/' + path.join('/') + '/'
      else
        '/' + path.join('/')
      end
    end

    # Parse key values from full etcd path
    #
    # @param node_path [String] etcd path
    # @return [Array<String>] key values
    def parse(node_path)
      path = node_path[1..-1] while node_part.start_with '/' # lstrip '/'
      key = []
      for part in @path
        if part.is_a? String
          if path.start_with(part)
            path = path[part.length..-1]
          else
            raise "Incorrect path for #{self} at #{part}: #{node_path} at #{part}"
          end
        elsif part.is_a? Symbol
          value, path = path.split('/', 1)
          key << value
        else
          raise "Invalid path part: #{part}"
        end
      end
      key
    end
  end

  module ClassMethods
    def etcd
      EtcdModel.etcd
    end
    def etcd_schema
      @etcd_schema
    end

    # Define the etcd key schema used for object identity. This is an absolute path-like
    # string, starting from the root, with :symbol placeholders for instance variables.
    # This is normalized into a flattened array of String and Symbol components.
    #
    # @param path [Array<String, Symbol>]
    def etcd_path(path)
      @etcd_schema = Schema.new(path)
    end

    # Return object from etcd node
    #
    # @param node [Etcd::Node]
    # @return [EtcdModel]
    def load(node)
      key = @etcd_schema.parse(node.key)
      object = new(*key)
      object.from_json!(node.value)
      object
    end

    public

    # Create directory for objects under the given partial key prefix.
    # Idempotent, does nothing if the directory already exists.
    #
    # For safety, every key value is checked to be non-nil and non-empty.
    #
    # @raise ArgumentError if any invalid keys are given
    # @param key [String] key values
    def mkdir(*key)
      prefix = @etcd_schema.prefix(*key)

      raise ArgumentError, "mkdir for complete object key" unless prefix.end_with? '/'

      etcd.set(prefix, dir: true, prevExist: false)
    rescue Etcd::NodeExist => errors
      # XXX: the same error is returned if the path exists as a file
      return
    end

    # Create and return new object in etcd, or raise Conflict if already exists
    #
    # @param key [Array<String>] object key values
    # @param opts [Hash<String, Object>] object attribute values
    # @raise [Conflict] object already exists
    # @return [EtcdModel] stored instance
    def create(*key, **opts)
      object = new(*key, **opts)
      object.create!
      object
    rescue Etcd::NodeExist => error
      raise const_get(:Conflict), "Create conflict with #{error.cause}@#{error.index}: #{error.message}"
    end

    # Return object from etcd, or nil if not exists
    #
    # @param name [String] object key name
    # @return [EtcdModel] loaded instance, or nil if not exists
    def get(*key)
      object = new(*key)
      object.get!
      object
    rescue Etcd::KeyNotFound
      nil
    end

    # Create and return new object in etcd, or return existing object.
    #
    # The returned object is guaranteed to have the same key values, but may have different attribute values.
    #
    # @param key [Array<String>] object key values
    # @param opts [Hash<String, Object>] object attribute values
    # @raise [Conflict] if the create races with a delete
    # @return [EtcdModel] stored instance
    def create_or_get(*key, **attrs)
      begin
        object = new(*key, **attrs)
        object.create!
        object
      rescue Etcd::NodeExist => error
        object.get!
        object
      end
    rescue Etcd::KeyNotFound
      raise const_get(:Conflict), "Create-and-Delete conflict with #{error.cause}@#{error.index}: #{error.message}"
    end

    # Iterate over all etcd objects under the given (partial) key prefix
    #
    # @param key [String] key values
    # @yield [object]
    # @yieldparam object [EtcdModel]
    def each(*key, &block)
      prefix = @etcd_schema.prefix(*key)
      response = etcd.get(prefix)

      for node in response.children
        name = node.key[prefix.length..-1]
        node_key = key + [name]

        if node.directory?
          each(*node_key, &block)
        else
          object = new(*node_key)
          object.from_json!(node.value)

          yield object
        end
      end
    end

    # List all objects under the given (partial) key prefix
    #
    # @param key [String] key values
    # @return [Array<EtcdModel>]
    def list(*key)
      objects = []

      each(*key) do |object|
        objects << object
      end

      objects
    end

    # Delete all objects under the given (partial) key prefix.
    #
    # Call without arguments to delete everything under the initial prefix of this class.
    # Any other class objects sharing the same common prefix as this class will also be deleted.
    #
    # For safety, every key value is checked to be non-nil and non-empty.
    #
    # @raise ArgumentError if any invalid keys are given
    # @param key [String] key values
    def delete(*key)
      prefix = @etcd_schema.prefix(*key)

      etcd.delete(prefix, recursive: prefix.end_with?('/'))
    end
  end

  def self.included(base)
    base.extend(ClassMethods)

    # define per-model Errors
    base.const_set :Conflict, Class.new(EtcdModel::Conflict)
  end

  # Initialize from etcd key values and JSON attrs
  #
  # @param keys [Array<String>] EtcdModel key values
  # @param attrs [Hash<Symbol, EtcdModel>] JSONModel attribute values
  def initialize(*keys, **attrs)
    self.class.etcd_schema.each_key_value(*keys) do |sym, value|
      self.instance_variable_set("@#{sym}", value)
    end
    initialize_json(**attrs)
  end

  # Compare for equality based on etcd key and JSON attr values
  #
  # @param other [EtcdModel]
  # @return [Boolean]
  def ==(other)
    return false if self.etcd_key != other.etcd_key

    return false if !eq_json(other)

    return true
  end

  # Compute etcd path, using key value
  #
  # @return [String] etcd path, with key values
  def etcd_key
    self.class.etcd_schema.path_with_keys do |sym|
      self.instance_variable_get("@#{sym}")
    end
  end

  # Get this objcet from etcd.
  #
  # Updates all JSON attribute values.
  #
  # @raise Etcd::KeyNotFound
  def get!
    from_json!(etcd.get(etcd_key).value)
  end

  # Create this object in etcd, raising if the object already exists.
  #
  # @raise Etcd::NodeExist
  def create!
    etcd.set(etcd_key, value: to_json, prevExist: false)
  end

  # Update this object in etcd, raising if the object does not exist.
  #
  # @raise ...
  def update!
    etcd.set(etcd_key, value: to_json, prevExist: true)
  end

  # Delete this object in etcd, raising if the object does not exist.
  #
  # @raise ...
  def delete!
    etcd.delete(etcd_key)
  end
end
