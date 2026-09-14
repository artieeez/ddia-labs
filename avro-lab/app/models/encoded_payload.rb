class EncodedPayload
  class Error < StandardError; end

  FORMATS = %w[json avro].freeze
  CODECS = %w[null deflate].freeze
  MIN_REPEATS = 1
  MAX_REPEATS = 100_000

  attr_reader :bytes, :content_type, :filename, :encode_ms, :schema_ms, :records, :codec, :naive

  def self.build(json_text:, repeats:, format:, codec: nil, naive: false)
    new(json_text:, repeats:, format:, codec:, naive:).build
  end

  def initialize(json_text:, repeats:, format:, codec: nil, naive: false)
    @source = parse_json(json_text)
    @repeats = validate_repeats(repeats)
    @format = validate_format(format)
    @codec = validate_codec(codec)
    @naive = validate_naive(naive)
  end

  def build
    if json?
      @schema_ms = 0
      started = monotonic_ms
      encode_json
      @encode_ms = monotonic_ms - started
    else
      @schema_ms = derive_schema
      started = monotonic_ms
      encode_avro(@schema)
      @encode_ms = monotonic_ms - started
    end
    self
  end

  def schema
    AvroSchema.derive(@source) if avro?
  end

  private
    def parse_json(json_text)
      JSON.parse(json_text.to_s)
    rescue JSON::ParserError, TypeError => e
      raise Error, "invalid JSON: #{e.message.lines.first.to_s.strip}"
    end

    def validate_repeats(repeats)
      value = repeats.is_a?(String) ? Integer(repeats, 10) : Integer(repeats)
      unless value.between?(MIN_REPEATS, MAX_REPEATS)
        raise Error, "repeats must be between #{MIN_REPEATS} and #{MAX_REPEATS}"
      end
      value
    rescue ArgumentError, TypeError
      raise Error, "repeats must be an integer between #{MIN_REPEATS} and #{MAX_REPEATS}"
    end

    def validate_format(format)
      unless FORMATS.include?(format)
        raise Error, "format must be one of #{FORMATS.join(", ")}"
      end
      format
    end

    def validate_codec(codec)
      codec = codec.to_s.empty? ? "null" : codec.to_s
      unless CODECS.include?(codec)
        raise Error, "codec must be one of #{CODECS.join(", ")}"
      end
      codec
    end

    def validate_naive(naive)
      naive = %w[1 true].include?(naive.to_s)
      raise Error, "naive encoding is only supported for the avro format" if naive && json?
      naive
    end

    def json?
      @format == "json"
    end

    def avro?
      @format == "avro"
    end

    def encode_json
      @records = Array.new(@repeats) { @source }
      @bytes = JSON.pretty_generate(@records)
      @content_type = "application/json"
      @filename = "payload-#{@repeats}.json"
    end

    def derive_schema
      started = monotonic_ms
      @schema = Avro::Schema.parse(AvroSchema.derive(@source).to_json)
      monotonic_ms - started
    end

    def encode_avro(schema)
      @records = Array.new(@repeats) { @source }
      @bytes = if @naive
        write_container_naive(schema, @records)
      else
        write_container_file(schema, @records, @codec)
      end
      @content_type = "application/octet-stream"
      suffix = @naive ? "-naive" : (@codec == "deflate" ? "-deflate" : "")
      @filename = "payload-#{@repeats}#{suffix}.avro"
    end

    # Deliberately naive implementation of the same container: re-derives and
    # re-parses the schema for every record, although the source never changes.
    # Pure-Ruby schema derivation is then paid O(records) times, so the encode
    # bar explodes — the point of this arm is to show how a naive
    # implementation can make encoding cost outweigh its benefits.
    def write_container_naive(schema, records)
      io = StringIO.new(+"", "wb")
      io.set_encoding(Encoding::BINARY)
      writer = Avro::DataFile::Writer.new(io, Avro::IO::DatumWriter.new(schema), schema, "null")
      records.each do |record|
        Avro::Schema.parse(AvroSchema.derive(record).to_json)
        writer << record
      end
      writer.close
      io.string
    end

    def write_container_file(schema, records, codec)
      io = StringIO.new(+"", "wb")
      io.set_encoding(Encoding::BINARY)
      writer = Avro::DataFile::Writer.new(io, Avro::IO::DatumWriter.new(schema), schema, codec)
      records.each { |record| writer << record }
      writer.close
      io.string
    end

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000.0
    end
end
