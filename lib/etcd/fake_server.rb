require_relative 'server_base'

# Fake etcd /v2/keys API implementation for application testing.
#
# You can use #load() to initialize the database, and then use the #api() as a client endpoint.
# Afterwards, use #modified(), #to_nodes() and #to_dirs() to check the end state.
#
# ## Implemented:
# * GET /version
# * GET/v2/keys/*
# ** For key and directories
# * GET /v2/keys/*?recursive=true
# * PUT /v2/keys/*?dir=true
# * PUT /v2/keys/* value=...
# * PUT /v2/keys/*?prevExist=false value=...
# * PUT /v2/keys/*?prevExist=true value=...
# * DELETE /v2/keys/*
# * DELETE /v2/keys/*?dir=true
# * DELETE /v2/keys/*?recursive=true
#
# ## Unimplemented
# * set prevIndex, prevValue
# * delete prevIndex, prevValue
# * error index
# * node created/modified index
# * HTTP X-Etcd-Index headers
# * HTTP X-Raft-Index, X-Raft-Term
# * TTL
#
# Usage example:
=begin

describe Application do
  let :etcd_server do
    Etcd::FakeServer.new()
  end

  let :etcd do
    EtcdClient.new()
  end

  before do
    stub_request(:any, /localhost:2379/).to_rack(etcd_server.api)

    EtcdModel.etcd = etcd

    etcd_server.load(
      '/test' => { 'value' => 'foobar' }
    )
  end

  it 'gets the value from etcd' do
    expect(etcd.get('/test').value).to eq 'foobar'
  end
end
=end
class Etcd::FakeServer < Etcd::ServerBase
  class Node
      attr_reader :key, :value, :nodes

      def initialize(key, value: nil, nodes: nil)
        @key = key
        @value = value
        @nodes = nodes
      end

      def directory?
        @nodes != nil
      end

      def serialize(recursive: false, toplevel: true)
        obj = {
          'key' => @key,
        }

        if directory?
          obj['dir'] = true

          if recursive || toplevel
            obj['nodes'] = nodes.map{ |key, node| node.serialize(recursive: recursive, toplevel: false) }
          end
        else
          obj['value'] = @value
        end

        return obj
      end

      def to_json(*args)
        serialize.to_json(*args)
      end
  end

  class Error < StandardError
    attr_reader :status

    def initialize(status, code, key)
      @status = status
      @code = code
      @key = key
    end

    def to_json(*args)
      {
          'errorCode' => @code,
          'cause' => @key,
          'index' => 0,
          'message' => message,
      }.to_json(*args)
    end
  end

  protected

  # Lookup a (normalized) key as a directory node
  def mkdir(key)
    @nodes[key] ||= Node.new(key, nodes: {})
  end

  # Lookup a key
  def read(key)
    key = '/' + key unless key.start_with? '/'
    key = key.chomp('/')

    return key, @nodes[key]
  end

  # Write a node
  def write(node)
    path = node.key

    @nodes[path] = node

    # create parent dirs
    until path == '/'
      path = File.dirname(path)
      parent = mkdir(path)
      parent.nodes[node.key] = node
      node = parent
    end
  end

  def remove(node, toplevel: true)
    if toplevel
      dir = File.dirname(node.key)

      @nodes[dir].nodes.delete(node.key)
    end

    @nodes.delete(node.key)

    if node.directory?
      for key, node in node.nodes
        remove(node, toplevel: false)
      end
    end
  end

  # Log an operation
  def log!(action, node)
    path = node.key
    path += '/' if node.directory?

    @logs << [action, path]
  end

  def modified!
    @modified = true
  end

  # Yield all nodes under root
  def walk
    for key, node in @nodes
      next unless key.start_with? @root

      yield node
    end
  end

  public

  # Reset database to empty state for key
  #
  # Initializes an empty database.
  def reset!
    @nodes = {}
    @logs = []
    @modified = false
  end

  # Load a hash of nodes into the store.
  # Encodes any JSON objects given as values
  # Creates any directories as needed.
  #
  # @param tree [Hash<String, Object or String>]
  def load!(tree)
    load_nodes(tree) do |key, value|
      if value == :directory
        write Node.new(key,
          nodes: {},
        )
      else
        write Node.new(key,
          value: value,
        )
      end
    end
  end

  def modified?
    @modified
  end

  def logs
    @logs
  end

  public

  def version
    {
      'etcdserver' => '0.0.0',
      'etcdcluster' => '0.0.0',
    }
  end

  def get(key, recursive: nil)
    key, node = read(key)

    if node
      return {
        'action' => 'get',
        'node' => node.serialize(recursive: recursive),
      }
    else
      raise Error.new(404, 100, key), "Key not found"
    end
  end

  def set(key, prevExist: nil, dir: nil, value: nil)
    key, node = read(key)

    if prevExist == false && node
      raise Error.new(412, 105, key), "Key already exists"
    elsif prevExist == true && !node
      raise Error.new(404, 100, key), "Key not found"
    elsif dir && node
      raise Error.new(403, 102, key), "Not a file"
    end

    action = node ? :set : :create

    set_node = if dir
      Node.new(key, nodes: {})
    else
      Node.new(key, value: value)
    end

    log! action, set_node

    write set_node
    modified!

    return {
      'action' => action,
      'node' => set_node,
      'prevNode' => node,
    }
  end

  def delete(key, recursive: nil, dir: nil)
    key, node = read(key)

    if !node
      raise Error.new(404, 100, key), "Key not found"
    #elsif dir && !node.directory?
    #  raise Etcd::NotDir.new('cause' => key)
    elsif node.directory? && !dir && !recursive
      raise Error.new(403, 102, key), "Not a file"
    elsif node.directory? && dir && !node.nodes.empty? && !recursive
      raise Error.new(403, 108, key), "Directory not empty"
    end

    log! :delete, node

    remove(node)
    modified!

    return {
      'action' => 'delete',
      'node' => node,
      'prevNode' => node,
    }
  end

  def api
    API.new(self)
  end

  class API < Sinatra::Base
    def initialize(server)
      super
      @server = server
    end

    def param_bool(name)
      case params[name]
      when nil
         nil
      when 'true', '1'
        true
      when 'false', '0'
        false
      else
        raise Error.new(400, 209, "invalid value for #{name}"), "Invalid field"
      end
    end

    def respond(status, object)
      return status, { 'Content-Type' => 'application/json' }, object.to_json
    end

    get '/version' do
      begin
        respond 200, @server.version
      rescue Error => error
        respond error.status, error
      end
    end

    get '/v2/keys/*' do |key|
      begin
        respond 200, @server.get(key,
          recursive: param_bool('recursive'),
        )
      rescue Error => error
        respond error.status, error
      end
    end

    put '/v2/keys/*' do |key, value: nil|
      begin
        respond 201, @server.set(key,
          prevExist: param_bool('prevExist'),
          dir: param_bool('dir'),
          value: params['value'],
        )
      rescue Error => error
        respond error.status, error
      end
    end

    delete '/v2/keys/*' do |key|
      begin
        respond 200, @server.delete(key,
          recursive: param_bool('recursive'),
          dir: param_bool('dir'),
        )
      rescue Error => error
        respond error.status, error
      end
    end
  end
end
