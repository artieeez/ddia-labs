class EncodingsController < ApplicationController
  def new
  end

  def create
    encoding = params.require(:encoding)
    @payload = EncodedPayload.build(
      json_text: encoding[:json_text],
      repeats: encoding[:repeats],
      format: encoding[:format]
    )
    response.set_header("X-Encode-Ms", @payload.encode_ms.to_s)
    response.set_header("X-Schema-Ms", @payload.schema_ms.to_s)
    send_data @payload.bytes,
              type: @payload.content_type,
              filename: @payload.filename,
              disposition: "attachment"
  rescue ActionController::ParameterMissing, EncodedPayload::Error, AvroSchema::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
