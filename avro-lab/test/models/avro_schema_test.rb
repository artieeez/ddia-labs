require "test_helper"

class AvroSchemaTest < ActiveSupport::TestCase
  test "derives a flat record from a hash" do
    schema = AvroSchema.derive("name" => "Artur", "age" => 42)

    expected = {
      "type" => "record", "name" => "Root",
      "fields" => [
        { "name" => "name", "type" => "string" },
        { "name" => "age", "type" => "long" }
      ]
    }
    assert_equal expected, schema
  end

  test "maps primitive scalars" do
    assert_equal "long", AvroSchema.derive(42)
    assert_equal "double", AvroSchema.derive(3.14)
    assert_equal "string", AvroSchema.derive("hi")
    assert_equal "boolean", AvroSchema.derive(true)
    assert_equal "null", AvroSchema.derive(nil)
  end

  test "derives nested records with path-based names" do
    schema = AvroSchema.derive("user" => { "name" => "x" })

    assert_equal "Root_user", schema.dig("fields", 0, "type", "name")
    assert_equal({ "name" => "name", "type" => "string" }, schema.dig("fields", 0, "type", "fields", 0))
  end

  test "derives arrays, using the first element for the items type" do
    schema = AvroSchema.derive("tags" => %w[a b c])

    assert_equal({ "type" => "array", "items" => "string" }, schema["fields"].first["type"])
  end

  test "derives arrays of records" do
    schema = AvroSchema.derive("users" => [ { "n" => 1 }, { "n" => 2 } ])

    items = schema.dig("fields", 0, "type", "items")
    assert_equal "record", items["type"]
    assert_equal "Root_users_item", items["name"]
    assert_equal({ "name" => "n", "type" => "long" }, items["fields"].first)
  end

  test "empty arrays become null items" do
    schema = AvroSchema.derive("x" => [])

    assert_equal({ "type" => "array", "items" => "null" }, schema["fields"].first["type"])
  end

  test "keeps record names unique when paths collide" do
    schema = AvroSchema.derive("a_b" => { "x" => 1 }, "a" => { "b" => { "x" => 1 } })

    names = record_names(schema).sort
    assert_includes names, "Root_a_b"
    assert_includes names, "Root_a_b_2"
    assert_equal names.uniq.length, names.length
  end

  test "rejects invalid Avro field names" do
    error = assert_raises(AvroSchema::Error) { AvroSchema.derive("user name" => 1) }
    assert_match(/invalid Avro field name/, error.message)
  end

  test "rejects integers outside the long range" do
    error = assert_raises(AvroSchema::Error) { AvroSchema.derive("x" => 2**63) }
    assert_match(/outside Avro long range/, error.message)
  end

  test "rejects non-homogeneous arrays" do
    error = assert_raises(AvroSchema::Error) { AvroSchema.derive("x" => [ 1, "a" ]) }
    assert_match(/not homogeneous/, error.message)
  end

  test "produces a schema the avro gem can parse" do
    schema = AvroSchema.derive("tags" => %w[a b], "address" => { "city" => "POA" })
    parsed = Avro::Schema.parse(schema.to_json)
    assert_kind_of Avro::Schema::RecordSchema, parsed
  end

  private
    def record_names(node, names = [])
      return names unless node.is_a?(Hash)

      if node["type"] == "record"
        names << node["name"]
        node["fields"].each { |field| record_names(field["type"], names) }
      elsif node["type"] == "array"
        record_names(node["items"], names)
      end
      names
    end
end
