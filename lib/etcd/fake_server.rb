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
      attr_reader :key, :created_index, :modified_index, :value, :nodes

      def initialize(key, index, value: nil, nodes: nil)
        @key = key
        @created_index = index
        @modified_index = index
        @value = value
        @nodes = nodes
      end

      def parent_path
        File.dirname(key)
      end

      def directory?
        @nodes != nil
      end

      def update(index, value)
        @modified_index = index
        @value = value
      end
      def delete(index)
        @modified_index = index
        @nodes = {} if @nodes
      end

      # @raise [TypeError] if not a directory
      def link(node)
        # @nodes will be nil if not a directory
        @nodes[node.key] = node
      end
      def unlink(node)
        @nodes.delete(node.key)
      end

      def serialize(recursive: false, toplevel: true)
        obj = {
          'key' => @key,
          'createdIndex' => @created_index,
          'modifiedIndex' => @modified_index,
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

  def initialize(*args)
    super
    reset!
  end

  # Link the directory node at the given path with the given child node
  # @return [Node] directory node
  def mkdir(path)
    @nodes[path] ||= Node.new(path, @index, nodes: {})
  end

  # Lookup a key
  def read(key)
    key = key.chomp('/')
    key = '/' + key unless key.start_with? '/'

    return key, @nodes[key]
  end

  # Write a node
  def write(path, **attrs)
    @index += 1

    @nodes[path] = node = Node.new(path, @index, **attrs)

    # create parent dirs
    child = node
    until child.key == '/'
      parent = mkdir(child.parent_path)
      parent.link(child)
      child = parent
    end

    node
  end

  def update(node, value)
    @index += 1

    node.update(@index, value)
  end

  # recursively unlink node and any child nodes
  def unlink(node)
    @nodes.delete(node.key)

    if node.directory?
      for key, node in node.nodes
        unlink(node)
      end
    end
  end

  def remove(node)
    @index += 1

    # unlink from parent
    @nodes[node.parent_path].unlink(node)

    # remove from @nodes
    unlink(node)

    # mark node as deleted
    node.delete(@index)
  end

  # Log an operation
  def log!(action, node)
    path = node.key
    path += '/' if node.directory?

    @logs << [action, path]
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
    @index = 0
    @nodes = {}
    @logs = []
    @modified = false

    mkdir('/')
    @start_index = @index
  end

  # Load a hash of nodes into the store.
  # Encodes any JSON objects given as values
  # Creates any directories as needed.
  #
  # @param tree [Hash<String, Object or String>]
  def load!(tree)
    load_nodes(tree) do |key, value|
      if value == :directory
        write key, nodes: {}
      else
        write key, value: value
      end
    end
    @start_index = @index
  end

  # Return etcd index at start of test
  def etcd_index
    @start_index
  end

  def modified?
    @index > @start_index
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

  def index
    @index
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
    end

    if dir && node
      raise Error.new(403, 102, key), "Not a file"
    elsif node
      action = :set
      prev_node = node.serialize

      update node, value
    else
      action = :create
      prev_node = nil

      node = if dir
        write key, nodes: {}
      else
        write key, value: value
      end
    end

    log! action, node

    return {
      'action' => action,
      'node' => node.serialize,
      'prevNode' => prev_node,
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
      headers = {
        'Content-Type' => 'application/json',
        'X-Etcd-Index' => @server.index,
      }
      return status, headers, object.to_json
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
