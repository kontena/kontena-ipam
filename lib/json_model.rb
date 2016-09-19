require 'json'

# Map a Class with instance variables to/from a JSON-encoded object.
module JSONModel
  # A single JSON-encodable/decodable attribute with an object value
  class JSONAttr
    attr_reader :name, :default

    # Initialize from class declaration
    #
    # @param sym [Symbol] instance variable name
    # @param name [String] override JSON object attribute
    # @param type [Class] convert from basic JSON value to object value using type.new(...)
    # @param omitnil [Boolean] omit from JSON if nil
    # @param default [Object] default value. Used for both load() and initialize()
    def initialize(sym, name: nil, type: nil, omitnil: false, default: nil)
      @name = name || sym.to_s
      @type = type
      @omitnil = omitnil
      @default = default
    end

    # Store attribute value to JSON object for encoding
    #
    # @param object [Hash] JSON object for encoding
    # @param value [Object] attr value of type
    def store(object, value)
      return if @omitnil && value == nil

      object[@name] = value # will later call .to_json
    end

    # Load attribute value from decoded JSON object
    #
    # @param object [Hash] decoded JSON object
    # @return [Object] of type
    def load(object)
      value = object.fetch(@name, @default)

      value = @type.new(value) if @type && value

      value
    end
  end

  module ClassMethods
    # Declared JSON attributes
    #
    # @return [Hash<Symbol, JSONAttr>]
    def json_attrs
      @json_attrs
    end

    # Return decoded JSON object
    #
    # @param value [String] JSON-encoded object
    # @raise JSON::JSONError
    # @return [JSONModel] new value with JSON attrs set
    def from_json(value)
      obj = new
      obj.from_json!(value)
      obj
    end

    protected

    # Declare a JSON object attribute using the given instance variable Symbol
    #
    # @see JSONAttr
    # @param sym [Symbol] instance variable
    # @param opts [Hash] JSONAttr options
    def json_attr(sym, **options)
      @json_attrs ||= {}
      @json_attrs[sym] = JSONAttr.new(sym, **options)
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  # Initialize JSON instance variables from keyword arguments
  def initialize_json(**attrs)
    attrs.each do |sym, value|
      raise ArgumentError, "Extra JSON attr argument: #{sym.inspect}" unless self.class.json_attrs[sym]
    end
    self.class.json_attrs.each do |sym, json_attr|
      self.instance_variable_set("@#{sym}", attrs.fetch(sym, json_attr.default))
    end
  end

  # Compare equality of JSON attributes
  def eq_json(other)
    self.class.json_attrs.each do |sym, json_attr|
      self_value = self.instance_variable_get("@#{sym}")
      other_value = other.instance_variable_get("@#{sym}")

      return false if self_value != other_value
    end
    return true
  end

  # Serialize to encoded JSON object
  #
  # @return [String] JSON-encoded object
  def to_json
    object = {}

    self.class.json_attrs.each do |sym, json_attr|
      json_attr.store(object, self.instance_variable_get("@#{sym}"))
    end

    JSON.generate(object)
  end

  # Set attributes from encoded JSON object
  #
  # @param value [String] JSON-encoded object
  # @raise JSON::JSONError
  # @return self
  def from_json!(value)
    object = JSON.parse(value)

    self.class.json_attrs.each do |sym, json_attr|
      self.instance_variable_set("@#{sym}", json_attr.load(object))
    end

    self
  end
end
