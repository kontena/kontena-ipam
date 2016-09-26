module Etcd::Keys
  # Iterate through key => value pairs directly under given preifx
  #
  # @yield [name, node]
  # @yieldparam name [String] node name, without the leading prefix
  # @yieldparam node [Node] node object
  def each(prefix = '/')
    prefix = prefix + '/' unless prefix.end_with? '/'

    response = get(prefix)

    for node in response.children
      yield node.key[prefix.length..-1], node
    end
  end
end
