#!/usr/bin/env bash
set -euo pipefail

# Rebuild app/assets/javascripts/avrojs.js from the pinned avro-js npm package.
# avro-js ships CJS only; this bundles its container-file decoder (lib/files.js)
# with browserify, polyfills the Node-core Buffer methods it calls, and minifies.
#
# Usage: script/build-avrojs.sh
# Requires: node + npm.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="1.12.2"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
npm init -y >/dev/null 2>&1
npm install --no-audit --no-fund --silent "avro-js@${VERSION}" browserify esbuild >/dev/null

cat > entry.js <<'JS'
'use strict';

var files = require('avro-js/lib/files');
var Buffer = require('buffer').Buffer;

// Node-core-only Buffer methods avro-js relies on, missing from the
// browserify buffer shim. Polyfill them on the bundled Buffer class.
var missing = {
  utf8Slice: function (start, end) { return this.toString('utf8', start, end); },
  utf8Write: function (str, offset, length) {
    var buf = Buffer.from(str, 'utf8');
    buf.copy(this, offset, 0, length === undefined ? buf.length : length);
    return buf.length;
  }
};
Object.keys(missing).forEach(function (name) {
  if (typeof Buffer.prototype[name] !== 'function') {
    Buffer.prototype[name] = missing[name];
  }
});

function toBuffer(bytes) {
  if (Buffer.isBuffer(bytes)) return bytes;
  if (bytes instanceof Uint8Array) {
    return Buffer.from(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  }
  return Buffer.from(bytes);
}

// Decode an Avro object container file into an array of records.
function decodeContainer(bytes) {
  return new Promise(function (resolve, reject) {
    var decoder = new files.streams.BlockDecoder();
    var records = [];
    decoder.on('data', function (record) { records.push(record); });
    decoder.on('error', reject);
    decoder.on('end', function () {
      resolve({ records: records, count: records.length });
    });
    decoder.end(toBuffer(bytes));
  });
}

module.exports = { decodeContainer: decodeContainer };
JS

npx browserify entry.js -o bundle.js --standalone avrojs
npx esbuild bundle.js --minify --outfile="$ROOT/app/assets/javascripts/avrojs.js"

echo "wrote $ROOT/app/assets/javascripts/avrojs.js (avro-js@${VERSION})"