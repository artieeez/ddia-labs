# Dev-only passthrough to the Go encoder sidecar, so the browser can exercise
# the same /go/v1/encode URL locally that production routes straight to the Go
# process at the ingress. Registering the route for dev/test prevents the
# client code from needing env-specific URLs.
class GoProxyController < ApplicationController
  # The /go/v1/encode route exists only in dev/test; in production the ingress
  # sends the path straight to the Go process, where this controller does not
  # exist. Same-origin passthrough, so no CSRF token is expected.
  skip_forgery_protection

  UPSTREAM = "http://127.0.0.1:8081".freeze
  TIMEOUT = 30

  @net_http = Net::HTTP
  class << self
    attr_accessor :net_http
  end

  def create
    payload = request.body.read
    parsed = JSON.parse(payload)
    unless parsed.is_a?(Hash)
      render json: { error: "body must be a JSON object" }, status: :bad_request
      return
    end

    uri = URI(UPSTREAM)
    http = self.class.net_http.new(uri.hostname, uri.port)
    http.read_timeout = TIMEOUT
    upstream = http.post("/v1/encode", JSON.generate(parsed), "Content-Type" => "application/json")

    if upstream.code.to_i.between?(200, 299)
      response.set_header("X-Schema-Ms", upstream["X-Schema-Ms"].to_s)
      response.set_header("X-Encode-Ms", upstream["X-Encode-Ms"].to_s)
      send_data upstream.body.to_s.b,
                type: upstream["Content-Type"] || "application/octet-stream",
                disposition: "attachment"
    else
      render json: upstream_error(upstream), status: upstream.code.to_i
    end
  rescue JSON::ParserError
    render json: { error: "invalid JSON body" }, status: :bad_request
  rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
    render json: { error: "go encoder unavailable: #{e.class}" }, status: :service_unavailable
  end

  private
    def upstream_error(response)
      parsed = JSON.parse(response.body.to_s)
      parsed.is_a?(Hash) && parsed["error"] ? parsed : { error: "go encoder returned HTTP #{response.code}" }
    rescue JSON::ParserError
      { error: "go encoder returned HTTP #{response.code}" }
    end
end
