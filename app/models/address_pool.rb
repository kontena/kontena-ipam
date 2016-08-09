class AddressPool
  attr_accessor :id, :pool
  
  def initialize(id = nil, pool = nil)
    @id = id
    @pool = pool
  end
end
