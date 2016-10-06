require 'socket'

module NodeHelper

  def node
    ENV['NODE_ID'] || Socket.gethostname
  end

end
