# Warm up the Avro encode path at boot so YJIT compilation and constant
# autoload cost never land on a user's first run and skew the timeline's
# encode bar (the first bar on a fresh pod used to show ~10x the warm time).
Rails.application.config.after_initialize do
  EncodedPayload.build(json_text: '{"probe":1,"nested":{"ok":true}}', repeats: 1, format: "avro", codec: "deflate")
rescue StandardError => e
  # Never fail boot over a warm-up; the lab still works, first bar may just be noisy.
  Rails.logger.warn("[avro-lab] avro warm-up failed: #{e.message}")
end
