require "test_helper"

class GoProxyControllerTest < ActionDispatch::IntegrationTest
  FakeUpstream = Struct.new(:code, :body, :headers) do
    def [](name)
      headers[name]
    end
  end

  FakeHTTP = Struct.new(:host, :port) do
    cattr_accessor :response, :raised_error
    self.response = nil
    self.raised_error = nil

    def read_timeout=(_value); end

    def post(_path, _body, _headers)
      raise self.class.raised_error if self.class.raised_error
      self.class.response
    end
  end

  setup do
    GoProxyController.net_http = FakeHTTP
  end

  teardown do
    GoProxyController.net_http = Net::HTTP
    FakeHTTP.response = nil
    FakeHTTP.raised_error = nil
  end

  test "relays a successful encode with both timing headers" do
    container = "Obj\x01fake-avro-container".b
    FakeHTTP.response = FakeUpstream.new("200", container, { "X-Schema-Ms" => "0.21", "X-Encode-Ms" => "1.84", "Content-Type" => "application/octet-stream" })

    post go_v1_encode_path, params: { source: { "a" => 1 }, repeats: 2, codec: "deflate" }.to_json,
                            headers: { "Content-Type" => "application/json" }

    assert_response :success
    assert_equal "0.21", response.headers["X-Schema-Ms"]
    assert_equal "1.84", response.headers["X-Encode-Ms"]
    assert_equal "application/octet-stream", response.media_type
    assert_equal container, response.body.b
  end

  test "relays upstream validation errors with their status" do
    FakeHTTP.response = FakeUpstream.new("422", { "error" => "array items are not homogeneous (expected R(k=S))" }.to_json, {})

    post go_v1_encode_path, params: { source: { "x" => [ { "a" => 1 }, { "b" => 2 } ] }, repeats: 1, codec: "null" }.to_json,
                            headers: { "Content-Type" => "application/json" }

    assert_response :unprocessable_entity
    assert_match(/not homogeneous/, JSON.parse(response.body)["error"])
  end

  test "surfaces an unreachable go encoder as 503" do
    FakeHTTP.raised_error = Errno::ECONNREFUSED

    post go_v1_encode_path, params: { source: { "a" => 1 }, repeats: 1, codec: "null" }.to_json,
                            headers: { "Content-Type" => "application/json" }

    assert_response :service_unavailable
    assert_match(/go encoder unavailable/, JSON.parse(response.body)["error"])
  end

  test "rejects non-object payloads" do
    post go_v1_encode_path, params: [ 1, 2 ].to_json, headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
    assert_match(/JSON object/, JSON.parse(response.body)["error"])
  end

  test "rejects invalid JSON bodies" do
    post go_v1_encode_path, params: "{nope", headers: { "Content-Type" => "application/json" }

    assert_response :bad_request
    assert_match(/invalid JSON/, JSON.parse(response.body)["error"])
  end
end
