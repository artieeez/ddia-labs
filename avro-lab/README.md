# Avro Lab

A small Rails app to benchmark Avro vs JSON for the same payload over HTTP:
server-side encoding (Apache `avro` gem), client-side decoding back to JSON
(Apache `avro-js`), and honest timing for both.

## What it does

- Paste a JSON object, pick a **repeat size** (1–100 000), and encode it five ways:
  - **JSON**: `POST /encoding` returns `payload-<n>.json` — an array with the
    object repeated `n` times (one C call).
  - **Avro · naive**: the same container written by a deliberately naive
    implementation that re-derives the schema for every record
    (`payload-<n>-naive.avro`) — the pure-Ruby interpreter price balloons,
    showing how a careless implementation can make encoding cost outweigh its
    benefits.
  - **Avro (null codec)**: the same payload as an Avro object container file
    (`payload-<n>.avro`, one record per repeat), blocks un-compressed.
  - **Avro (deflate)**: the same container with zlib-compressed blocks
    (`payload-<n>-deflate.avro`) — smaller transfer, more encode/decode CPU.
  - **Avro (Go endpoint)**: the browser POSTs `{source, repeats, codec}`
    straight to `/go/v1/encode` — the same ingress host, path-routed to a Go
    sidecar process inside the app container (goavro, deflate). The Go process
    derives the Avro schema itself (mirroring `AvroSchema.derive`: int→long,
    float→double, `Root_<path>` record names, homogeneous arrays) and measures
    both `X-Schema-Ms` and `X-Encode-Ms` in-process, so the bar shows pure
    compiled-encoder timing with no Rails hop (`payload-<n>-go.avro`).
  The browser decodes all four Avro variants back to JSON with `avro-js`,
  logs the decode time, and offers the decoded JSON for download.
- The schema is **auto-derived** from the JSON with deterministic rules:
  integer → `long`, float → `double`, string → `string`, boolean → `boolean`,
  null → `null`, array → `array`, object → nested `record`. Invalid Avro field
  names, integers outside the `long` range (±2⁶³), and non-homogeneous arrays
  are rejected with a clear error (a schema editor may come later).
- Timing: the server splits Avro time into schema derivation (`X-Schema-Ms`)
  and container encoding (`X-Encode-Ms`); the client times the download and the
  decode (`avro-js` container decode, or `JSON.parse` for the baseline) and
  draws one segment per phase. Transfer size/latency is visible in the
  browser's network tab.
- **Reading the encode bar honestly**: `X-Encode-Ms` measures the *Ruby
  implementation* of each format, and the two are not symmetric — the JSON arm
  is a single C call (`json` gem), the Avro arm is pure-Ruby per-field encoding
  (`avro-ruby` gem), which shows as roughly a 20x gap on identical records.
  That is a language-binding artifact, not a property of the formats. The Avro
  path is warmed at boot so the first run isn't polluted by autoload/YJIT;
  measurements are still single-shot (expect ±10-15% run-to-run noise).
- **Why deflate looks almost free**: compression runs per 64 KB block during
  the write loop, and zlib crushes small repetitive payloads in ~ms, so the
  encode delta null→deflate is ~2 ms at 10k records — smaller than the noise.
  Where deflate pays off is the bytes column (920 KB → 5 KB), i.e. transfer
  cost, which a localhost lab can't show; on a real network link that gap is
  the whole point.

## Run

```bash
mise install        # Ruby 4.0.5 (pinned in mise.toml / .ruby-version)
bin/rails server    # then open http://localhost:3000
```

## Layout

- `app/models/avro_schema.rb` — schema derivation rules.
- `app/models/encoded_payload.rb` — value object that encodes JSON or Avro bytes.
- `app/controllers/encodings_controller.rb` — `new` (editor) + `create` (file download).
- `app/javascript/controllers/encoder_controller.js` — fetch, download, decode, timing.
- `app/assets/javascripts/avrojs.js` — vendored avro-js browser bundle.

## Client Avro bundle

`app/assets/javascripts/avrojs.js` is built from `avro-js@1.12.2` (CJS) via
browserify: it wraps the container `BlockDecoder`, polyfills the two
Node-core `Buffer` methods avro-js calls, and minifies with esbuild.
Rebuild with `script/build-avrojs.sh` (documented there).

## Tests

```bash
bin/rails test
```

Minitest: model unit tests for schema derivation and payload encoding, and
integration tests covering the `POST /encoding` endpoint (both formats,
validation failures).

## Conventions

Rails code follows the `rails-dev` skill in `.agents/skills/rails-dev`
(models are nouns, thin CRUD controllers, Minitest, errors raised to the
boundary). Rails scaffolding: `~/artieeez` (mise-managed Ruby, no git
commits without asking).