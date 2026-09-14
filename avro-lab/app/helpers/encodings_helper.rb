module EncodingsHelper
  def default_sample_json
    JSON.pretty_generate(
      "id" => 42,
      "name" => "Artur Webber",
      "active" => true,
      "score" => 3.14,
      "tags" => %w[avro json rails],
      "address" => { "city" => "Porto Alegre", "zip" => "90000-000" },
      "note" => nil
    )
  end
end
