class AvroSchema
  class Error < StandardError; end

  ROOT_NAME = "Root"
  NAME_PATTERN = /\A[A-Za-z_][A-Za-z0-9_]*\z/
  LONG_MIN = -(2**63)
  LONG_MAX = (2**63) - 1

  def self.derive(value)
    new(value).derive
  end

  def initialize(value)
    @value = value
    @used_names = Set.new
  end

  def derive = build(@value, ROOT_NAME)

  private
    def build(value, name)
      case value
      when Hash
        build_record(value, name)
      when Array
        { "type" => "array", "items" => build_array_items(value, name) }
      when Integer
        ensure_long_range!(value)
        "long"
      when Float
        "double"
      when String
        "string"
      when TrueClass, FalseClass
        "boolean"
      when NilClass
        "null"
      else
        raise Error, "unsupported JSON value: #{value.inspect}"
      end
    end

    def build_record(hash, name)
      {
        "type" => "record",
        "name" => unique_name!(name),
        "fields" => hash.map { |key, child| field(key, child, name) }
      }
    end

    def field(key, child, parent_name)
      validate_name!(key)
      { "name" => key, "type" => build(child, nested_name(parent_name, key)) }
    end

    def build_array_items(array, parent_name)
      if array.empty?
        "null"
      else
        first_shape = shape_of(array.first)
        unless array.all? { |item| shape_of(item) == first_shape }
          raise Error, "array items are not homogeneous (expected #{first_shape.inspect})"
        end
        build(array.first, nested_name(parent_name, "item"))
      end
    end

    # Canonical structural signature, ignoring record names: equal shapes
    # produce identical Avro schemas for the same field paths.
    def shape_of(value)
      case value
      when Hash
        [ :record, value.map { |key, child| [ key, shape_of(child) ] } ]
      when Array
        [ :array, value.empty? ? :null : shape_of(value.first) ]
      when Integer
        :long
      when Float
        :double
      when String
        :string
      when TrueClass, FalseClass
        :boolean
      when NilClass
        :null
      else
        raise Error, "unsupported JSON value: #{value.inspect}"
      end
    end

    def nested_name(parent_name, key)
      "#{parent_name}_#{key}"
    end

    def validate_name!(key)
      unless NAME_PATTERN.match?(key)
        raise Error, "invalid Avro field name #{key.inspect} (must match #{NAME_PATTERN})"
      end
    end

    def ensure_long_range!(integer)
      unless integer.between?(LONG_MIN, LONG_MAX)
        raise Error, "integer #{integer} is outside Avro long range (#{LONG_MIN}..#{LONG_MAX})"
      end
    end

    def unique_name!(name)
      base = name
      suffix = 2
      while @used_names.include?(name)
        name = "#{base}_#{suffix}"
        suffix += 1
      end
      @used_names << name
      name
    end
end
