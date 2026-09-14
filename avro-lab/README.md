# Avro Lab

A small Rails app to benchmark Avro vs JSON for the same payload over HTTP:
server-side encoding (Apache `avro` gem), client-side decoding back to JSON
(Apache `avro-js`), and honest timing for both.

## What it does

- Paste a JSON object, pick a **repeat size** (1–100 000), and encode it three ways:
  - **JSON**: `POST /encoding` returns `payload-<n>.json` — an array with the
    object repeated `n` times.
  - **Avro (null codec)**: the same payload written as an Avro object container
    file (`payload-<n>.avro`, one record per repeat), blocks un-compressed.
  - **Avro (deflate)**: the same container with zlib-compressed blocks
    (`payload-<n>-deflate.avro`) — smaller transfer, more encode/decode CPU.
  The browser decodes both Avro variants back to JSON with `avro-js`, logs the
  decode time, and offers the decoded JSON for download.
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