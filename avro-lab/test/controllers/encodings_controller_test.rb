require "test_helper"

class EncodingsControllerTest < ActionDispatch::IntegrationTest
  test "new renders the editor" do
    get new_encoding_path

    assert_response :success
    assert_select "textarea#json_text"
    assert_select "button[data-action='encoder#encodeJson']"
    assert_select "button[data-action='encoder#encodeAvroNaive']"
    assert_select "button[data-action='encoder#encodeAvro']"
    assert_select "button[data-action='encoder#encodeAvroDeflate']"
    assert_select "button[data-action='encoder#encodeGo']"
    assert_match(/baseline.*naive.*null codec.*deflate.*Go endpoint/m, response.body)
    assert_select "div.lab__note", text: /Ruby interpreter price/
    assert_select "div.lab__note--callout", text: /Java or Go/
  end

  test "create encodes and downloads json" do
    post encoding_path, params: { encoding: { json_text: '{"a":1}', repeats: 2, format: "json" } }

    assert_response :success
    assert_equal "application/json", response.media_type
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.headers["Content-Disposition"], "payload-2.json"
    assert response.headers.key?("X-Encode-Ms")
    assert response.headers.key?("X-Schema-Ms")
    assert_equal "0", response.headers["X-Schema-Ms"]
    assert_equal [ { "a" => 1 }, { "a" => 1 } ], JSON.parse(response.body)
  end

  test "create encodes and downloads avro that round-trips to json" do
    post encoding_path, params: { encoding: { json_text: '{"a":1,"b":"x"}', repeats: 2, format: "avro" } }

    assert_response :success
    assert_equal "application/octet-stream", response.media_type
    assert_includes response.headers["Content-Disposition"], "payload-2.avro"
    assert response.headers.key?("X-Encode-Ms")
    assert response.headers.key?("X-Schema-Ms")
    assert_match(/\A\d+(\.\d+)?\z/, response.headers["X-Schema-Ms"])
    assert_operator Float(response.headers["X-Schema-Ms"]), :>, 0

    io = StringIO.new(response.body.b, "rb")
    reader = Avro::DataFile::Reader.new(io, Avro::IO::DatumReader.new)
    records = reader.map(&:to_h)
    assert_equal [ { "a" => 1, "b" => "x" }, { "a" => 1, "b" => "x" } ], records
  end

  test "create rejects invalid json" do
    post encoding_path, params: { encoding: { json_text: "{nope", repeats: 1, format: "json" } }

    assert_response :unprocessable_entity
    assert_match(/invalid JSON/, JSON.parse(response.body)["error"])
  end

  test "create encodes and downloads deflate avro that round-trips to json" do
    post encoding_path, params: { encoding: { json_text: '{"a":1,"b":"x"}', repeats: 2, format: "avro", codec: "deflate" } }

    assert_response :success
    assert_includes response.headers["Content-Disposition"], "payload-2-deflate.avro"
    assert response.headers.key?("X-Encode-Ms")
    assert response.headers.key?("X-Schema-Ms")

    io = StringIO.new(response.body.b, "rb")
    reader = Avro::DataFile::Reader.new(io, Avro::IO::DatumReader.new)
    records = reader.map(&:to_h)
    assert_equal [ { "a" => 1, "b" => "x" }, { "a" => 1, "b" => "x" } ], records
  end

  test "create rejects unknown codecs" do
    post encoding_path, params: { encoding: { json_text: '{"a":1}', repeats: 1, format: "avro", codec: "snappy" } }

    assert_response :unprocessable_entity
    assert_match(/codec/, JSON.parse(response.body)["error"])
  end

  test "create encodes and downloads naive avro that still round-trips" do
    post encoding_path, params: { encoding: { json_text: '{"a":1}', repeats: 2, format: "avro", naive: "true" } }

    assert_response :success
    assert_includes response.headers["Content-Disposition"], "payload-2-naive.avro"

    io = StringIO.new(response.body.b, "rb")
    reader = Avro::DataFile::Reader.new(io, Avro::IO::DatumReader.new)
    assert_equal [ { "a" => 1 }, { "a" => 1 } ], reader.map(&:to_h)
  end

  test "create rejects naive encoding for json" do
    post encoding_path, params: { encoding: { json_text: '{"a":1}', repeats: 1, format: "json", naive: "true" } }

    assert_response :unprocessable_entity
    assert_match(/naive/, JSON.parse(response.body)["error"])
  end

  test "create rejects out-of-range repeats" do
    post encoding_path, params: { encoding: { json_text: '{"a":1}', repeats: 0, format: "json" } }

    assert_response :unprocessable_entity
    assert_match(/repeats/, JSON.parse(response.body)["error"])
  end

  test "create rejects unknown formats" do
    post encoding_path, params: { encoding: { json_text: '{"a":1}', repeats: 1, format: "xml" } }

    assert_response :unprocessable_entity
    assert_match(/format/, JSON.parse(response.body)["error"])
  end

  test "create parses a raw JSON request body" do
    body = { encoding: { json_text: '{"a":1}', repeats: 1, format: "json" } }.to_json
    post encoding_path, params: body, headers: { "Content-Type" => "application/json" }

    assert_response :success
    assert_equal [ { "a" => 1 } ], JSON.parse(response.body)
  end

  test "create rejects missing params" do
    post encoding_path

    assert_response :unprocessable_entity
    assert_match(/param is missing/, JSON.parse(response.body)["error"])
  end
end
