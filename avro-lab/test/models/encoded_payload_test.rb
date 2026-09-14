require "test_helper"

class EncodedPayloadTest < ActiveSupport::TestCase
  def build_payload(source_json, repeats: 3, format: "json")
    EncodedPayload.build(json_text: source_json, repeats: repeats, format: format)
  end

  test "encodes json as an array of repeats" do
    payload = build_payload('{"a":1}', repeats: 3, format: "json")

    assert_equal "application/json", payload.content_type
    assert_equal "payload-3.json", payload.filename
    assert_equal [ { "a" => 1 }, { "a" => 1 }, { "a" => 1 } ], JSON.parse(payload.bytes)
    assert_operator payload.encode_ms, :>=, 0
    assert_equal 0, payload.schema_ms
    assert_equal 0, payload.schema_ms
  end

  test "encodes avro as a container file with one record per repeat" do
    payload = build_payload('{"a":1,"b":"x"}', repeats: 3, format: "avro")

    assert_equal "application/octet-stream", payload.content_type
    assert_equal "payload-3.avro", payload.filename
    assert_operator payload.encode_ms, :>=, 0
    assert_operator payload.schema_ms, :>, 0
    assert_operator payload.schema_ms, :>, 0
    assert_equal [ { "a" => 1, "b" => "x" }, { "a" => 1, "b" => "x" }, { "a" => 1, "b" => "x" } ], read_records(payload.bytes)
  end

  test "avro round-trips nested values and floating point" do
    source = { "score" => 3.14, "active" => true, "tags" => %w[a b], "note" => nil,
               "address" => { "city" => "POA" } }
    payload = build_payload(source.to_json, format: "avro")

    assert_equal source, read_records(payload.bytes).first
  end

  test "embeds the derived schema in the avro container" do
    source = { "name" => "x", "age" => 42 }
    payload = build_payload(source.to_json, format: "avro")

    meta_schema = read_container_meta(payload.bytes)["avro.schema"]
    assert_equal AvroSchema.derive(source).to_json, meta_schema
  end

  test "rejects repeats outside 1..100_000" do
    [ 0, -1, 100_001 ].each do |repeats|
      error = assert_raises(EncodedPayload::Error) { build_payload('{"a":1}', repeats: repeats) }
      assert_match(/repeats must be between/, error.message)
    end
  end

  test "rejects non-integer repeats" do
    error = assert_raises(EncodedPayload::Error) { build_payload('{"a":1}', repeats: "abc") }
    assert_match(/repeats must be an integer/, error.message)
  end

  test "rejects invalid json" do
    error = assert_raises(EncodedPayload::Error) { build_payload("{nope") }
    assert_match(/invalid JSON/, error.message)
  end

  test "rejects unknown formats" do
    error = assert_raises(EncodedPayload::Error) { build_payload('{"a":1}', format: "xml") }
    assert_match(/format must be one of/, error.message)
  end

  private
    def read_records(bytes)
      io = StringIO.new(bytes.b, "rb")
      reader = Avro::DataFile::Reader.new(io, Avro::IO::DatumReader.new)
      reader.map(&:to_h)
    end

    def read_container_meta(bytes)
      io = StringIO.new(bytes.b, "rb")
      meta = Avro::DataFile::Reader.new(io, Avro::IO::DatumReader.new).meta
      meta.transform_values(&:to_s)
    end
end
