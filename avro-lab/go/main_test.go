package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"reflect"
	"strconv"
	"strings"
	"testing"

	"github.com/linkedin/goavro/v2"
)

const testSource = `{"title":"x","score":3.14,"count":2,"tags":["a","b"],"ok":true,"note":null}`

func newServer(t *testing.T) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(newMux())
	t.Cleanup(srv.Close)
	return srv
}

func postEncode(t *testing.T, srv *httptest.Server, source string, repeats int, codec string) *http.Response {
	t.Helper()
	body, err := json.Marshal(map[string]interface{}{
		"source":  json.RawMessage(source),
		"repeats": repeats,
		"codec":   codec,
	})
	if err != nil {
		t.Fatalf("marshal request: %v", err)
	}
	resp, err := http.Post(srv.URL+"/v1/encode", "application/json", bytes.NewReader(body))
	if err != nil {
		t.Fatalf("post encode: %v", err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}

func postRaw(t *testing.T, srv *httptest.Server, body string) *http.Response {
	t.Helper()
	resp, err := http.Post(srv.URL+"/v1/encode", "application/json", bytes.NewBufferString(body))
	if err != nil {
		t.Fatalf("post encode: %v", err)
	}
	t.Cleanup(func() { resp.Body.Close() })
	return resp
}

func decodeRecords(t *testing.T, data []byte) []interface{} {
	t.Helper()
	reader, err := goavro.NewOCFReader(bytes.NewReader(data))
	if err != nil {
		t.Fatalf("open container: %v", err)
	}
	var records []interface{}
	for reader.Scan() {
		record, err := reader.Read()
		if err != nil {
			t.Fatalf("read record: %v", err)
		}
		records = append(records, record)
	}
	if err := reader.Err(); err != nil {
		t.Fatalf("container reader error: %v", err)
	}
	return records
}

func expectedNative() map[string]interface{} {
	return map[string]interface{}{
		"title": "x",
		"score": 3.14,
		"count": int64(2),
		"tags":  []interface{}{"a", "b"},
		"ok":    true,
		"note":  nil,
	}
}

// GO-01/GO-03/GO-04: direct endpoint, both timing headers, records round-trip.
func TestEncodeDecodesToRepeatsRecords(t *testing.T) {
	srv := newServer(t)
	resp := postEncode(t, srv, testSource, 3, "deflate")

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status = %d, body = %s", resp.StatusCode, body)
	}
	for _, header := range []string{"X-Schema-Ms", "X-Encode-Ms"} {
		ms, err := strconv.ParseFloat(resp.Header.Get(header), 64)
		if err != nil || ms < 0 {
			t.Fatalf("%s = %q, err = %v", header, resp.Header.Get(header), err)
		}
	}
	if got := resp.Header.Get("Content-Type"); got != "application/octet-stream" {
		t.Fatalf("content type = %q", got)
	}
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatalf("read body: %v", err)
	}

	records := decodeRecords(t, data)
	if len(records) != 3 {
		t.Fatalf("record count = %d, want 3", len(records))
	}
	for i, record := range records {
		if !reflect.DeepEqual(record, expectedNative()) {
			t.Fatalf("record %d = %#v, want %#v", i, record, expectedNative())
		}
	}
}

// GO-02: nested records, arrays of records, int/double/bool/null round-trip.
func TestNestedRecordsAndRecordArraysRoundTrip(t *testing.T) {
	source := `{"user":{"name":"x","score":1.5},"tags":[{"k":"a"},{"k":"b"}],"active":true,"note":null}`
	srv := newServer(t)
	resp := postEncode(t, srv, source, 2, "null")
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status = %d, body = %s", resp.StatusCode, body)
	}
	data, _ := io.ReadAll(resp.Body)
	want := map[string]interface{}{
		"user":   map[string]interface{}{"name": "x", "score": 1.5},
		"tags":   []interface{}{map[string]interface{}{"k": "a"}, map[string]interface{}{"k": "b"}},
		"active": true,
		"note":   nil,
	}
	records := decodeRecords(t, data)
	if len(records) != 2 {
		t.Fatalf("record count = %d, want 2", len(records))
	}
	for i, record := range records {
		if !reflect.DeepEqual(record, want) {
			t.Fatalf("record %d = %#v, want %#v", i, record, want)
		}
	}
}

// Deflate produces a smaller container than null on repetitive data.
func TestDeflateContainerSmallerThanNull(t *testing.T) {
	srv := newServer(t)
	null := postEncode(t, srv, testSource, 200, "null")
	nullData, _ := io.ReadAll(null.Body)
	deflate := postEncode(t, srv, testSource, 200, "deflate")
	deflateData, _ := io.ReadAll(deflate.Body)

	if len(deflateData) >= len(nullData) {
		t.Fatalf("deflate container = %d bytes, not smaller than null = %d", len(deflateData), len(nullData))
	}
	if len(decodeRecords(t, deflateData)) != 200 {
		t.Fatal("deflate container record count != 200")
	}
}

// GO-06: longs beyond 2^53 preserve their exact integer value.
func TestLongPrecisionBeyondTwoToTheFiftyThree(t *testing.T) {
	srv := newServer(t)
	resp := postEncode(t, srv, `{"v":9007199254740993}`, 1, "null")
	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		t.Fatalf("status = %d, body = %s", resp.StatusCode, body)
	}
	data, _ := io.ReadAll(resp.Body)
	record := decodeRecords(t, data)[0].(map[string]interface{})
	if got := record["v"]; got != int64(9007199254740993) {
		t.Fatalf("long = %v (%T), want 9007199254740993", got, got)
	}
}

// GO-02 mirror: the derived schema uses Root_<path> record names and matches
// the Rails derivation structure (only record items get names).
func TestDerivedSchemaUsesPathNames(t *testing.T) {
	schema, _, err := deriveSource([]byte(`{"user":{"name":"x"},"tags":[{"k":"v"}]}`))
	if err != nil {
		t.Fatalf("derive: %v", err)
	}
	raw, _ := json.Marshal(schema)
	text := string(raw)
	if !strings.Contains(text, `"name":"Root_user"`) {
		t.Fatalf("schema lacks Root_user: %s", text)
	}
	if !strings.Contains(text, `"name":"Root_tags_item"`) {
		t.Fatalf("schema lacks Root_tags_item: %s", text)
	}
}

// Uniqueness suffixing mirrors the Rails global used-names set.
func TestRecordNameUniquenessSuffixing(t *testing.T) {
	schema, _, err := deriveSource([]byte(`{"a":{"b":{"z":1}},"a_b":{"c":2}}`))
	if err != nil {
		t.Fatalf("derive: %v", err)
	}
	raw, _ := json.Marshal(schema)
	text := string(raw)
	if got := strings.Count(text, `"name":"Root_a_b"`); got != 1 {
		t.Fatalf("Root_a_b count = %d, want 1: %s", got, text)
	}
	if got := strings.Count(text, `"name":"Root_a_b_2"`); got != 1 {
		t.Fatalf("Root_a_b_2 count = %d, want 1: %s", got, text)
	}
}

// Mirror error: integer beyond the Avro long range.
func TestLongRangeError(t *testing.T) {
	srv := newServer(t)
	resp := postEncode(t, srv, `{"v":9223372036854775808}`, 1, "null")
	if resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", resp.StatusCode)
	}
	var body map[string]string
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if !strings.Contains(body["error"], "outside Avro long range") {
		t.Fatalf("error = %q, want long-range message", body["error"])
	}
}

// Mirror error: invalid Avro field name.
func TestInvalidFieldNameError(t *testing.T) {
	srv := newServer(t)
	resp := postEncode(t, srv, `{"a-b":1}`, 1, "null")
	if resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", resp.StatusCode)
	}
	var body map[string]string
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if !strings.Contains(body["error"], "invalid Avro field name") {
		t.Fatalf("error = %q, want field-name message", body["error"])
	}
}

// Mirror error: non-homogeneous array items.
func TestNonHomogeneousArrayError(t *testing.T) {
	srv := newServer(t)
	resp := postEncode(t, srv, `{"items":[{"a":1},{"b":2}]}`, 1, "null")
	if resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", resp.StatusCode)
	}
	var body map[string]string
	_ = json.NewDecoder(resp.Body).Decode(&body)
	if !strings.Contains(body["error"], "not homogeneous") {
		t.Fatalf("error = %q, want homogeneity message", body["error"])
	}
}

// Repeats bounds mirror the Rails arm (1..100_000).
func TestRejectsOutOfRangeRepeats(t *testing.T) {
	srv := newServer(t)
	for _, repeats := range []int{0, 100_001} {
		resp := postEncode(t, srv, testSource, repeats, "null")
		var body map[string]string
		_ = json.NewDecoder(resp.Body).Decode(&body)
		if resp.StatusCode != http.StatusUnprocessableEntity || !strings.Contains(body["error"], "repeats") {
			t.Fatalf("repeats=%d status=%d error=%q, want 422 with repeats", repeats, resp.StatusCode, body["error"])
		}
	}
}

// GO-09 edge: codec must be null or deflate.
func TestRejectsUnknownCodec(t *testing.T) {
	srv := newServer(t)
	resp := postEncode(t, srv, testSource, 1, "lz4")
	if resp.StatusCode != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, want 422", resp.StatusCode)
	}
}

func TestRejectsMissingSource(t *testing.T) {
	srv := newServer(t)
	resp := postRaw(t, srv, `{"repeats":1,"codec":"null"}`)
	if resp.StatusCode != http.StatusBadRequest {
		t.Fatalf("status = %d, want 400", resp.StatusCode)
	}
}

// GO-07: /healthz answers 200 so the Rails entrypoint can wait on it.
func TestHealthz(t *testing.T) {
	srv := httptest.NewServer(newMux())
	t.Cleanup(srv.Close)
	resp, err := http.Get(srv.URL + "/healthz")
	if err != nil {
		t.Fatalf("get healthz: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("healthz status = %d, want 200", resp.StatusCode)
	}
}

func TestEncodeRejectsGet(t *testing.T) {
	srv := newServer(t)
	resp, err := http.Get(srv.URL + "/v1/encode")
	if err != nil {
		t.Fatalf("get encode: %v", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, want 405", resp.StatusCode)
	}
}
