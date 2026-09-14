// Command goavro-lab serves the lab's Go Avro encoder as a sidecar HTTP
// endpoint inside the Rails app's container. Unlike the pure-Ruby arms, the
// browser posts {source, repeats, codec} straight to this endpoint via the
// /go path route; this service derives the Avro schema itself (mirroring the
// Rails AvroSchema.derive rules), writes the Object Container File with the
// requested codec, and returns the container bytes with X-Schema-Ms (schema
// derivation) and X-Encode-Ms (container write) measured in-process.
package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"math/big"
	"net/http"
	"os"
	"regexp"
	"strings"
	"time"

	"github.com/linkedin/goavro/v2"
)

const (
	maxRepeats = 100_000
	maxBody    = 32 << 20 // 32 MiB request ceiling

	rootName  = "Root"
	longMin   = -(1 << 63)
	longMax   = (1 << 63) - 1
	nameRegex = `^[A-Za-z_][A-Za-z0-9_]*$`
)

var (
	codecs = map[string]string{
		"null":    goavro.CompressionNullLabel,
		"deflate": goavro.CompressionDeflateLabel,
	}
	namePattern = regexp.MustCompile(nameRegex)
)

type encodeRequest struct {
	Source  json.RawMessage `json:"source"`
	Repeats int             `json:"repeats"`
	Codec   string          `json:"codec"`
}

// jObject keeps object entries in source order, mirroring Ruby Hash
// iteration, so record field order and shape signatures match the Rails
// derivation exactly.
type jField struct {
	name  string
	value interface{}
}

type jObject []jField

func parseOrdered(data []byte) (interface{}, error) {
	dec := json.NewDecoder(bytes.NewReader(data))
	dec.UseNumber()
	value, err := parseValue(dec)
	if err != nil {
		return nil, err
	}
	// Reject trailing garbage after the top-level value.
	if _, err := dec.Token(); err != io.EOF {
		if err == nil {
			return nil, fmt.Errorf("unexpected trailing data after JSON value")
		}
		return nil, err
	}
	return value, nil
}

func parseValue(dec *json.Decoder) (interface{}, error) {
	tok, err := dec.Token()
	if err != nil {
		return nil, err
	}
	switch t := tok.(type) {
	case json.Delim:
		switch t {
		case '{':
			var obj jObject
			for dec.More() {
				keyTok, err := dec.Token()
				if err != nil {
					return nil, err
				}
				key, ok := keyTok.(string)
				if !ok {
					return nil, fmt.Errorf("object key is not a string")
				}
				child, err := parseValue(dec)
				if err != nil {
					return nil, err
				}
				obj = append(obj, jField{name: key, value: child})
			}
			if _, err := dec.Token(); err != nil { // consume '}'
				return nil, err
			}
			return obj, nil
		case '[':
			var items []interface{}
			for dec.More() {
				child, err := parseValue(dec)
				if err != nil {
					return nil, err
				}
				items = append(items, child)
			}
			if _, err := dec.Token(); err != nil { // consume ']'
				return nil, err
			}
			return items, nil
		}
		return nil, fmt.Errorf("unexpected delimiter %v", t)
	default:
		return tok, nil // string, json.Number, bool, nil
	}
}

// deriveState mirrors AvroSchema.derive from the Rails app 1:1: one shared
// used-names set for the whole tree, path-concatenated record names, ordered
// field lists, and the same validation errors.
type deriveState struct {
	usedNames map[string]bool
}

// integerLiteral reports whether the JSON number is written as an integer
// literal (no decimal point or exponent), mirroring Ruby's distinction between
// Integer and Float values.
func integerLiteral(n json.Number) bool {
	return !strings.ContainsAny(string(n), ".eE")
}

func deriveSource(data []byte) (schema interface{}, native interface{}, err error) {
	value, err := parseOrdered(data)
	if err != nil {
		return nil, nil, fmt.Errorf("invalid JSON: %v", err)
	}
	state := &deriveState{usedNames: map[string]bool{}}
	return state.build(value, rootName)
}

// build derives the schema node for value and the goavro-native value in one
// pass: longs become exact int64 (encoding/json's plain float64 decode would
// lose precision above 2^53), doubles become float64, records become
// map[string]interface{}, arrays become []interface{}.
func (s *deriveState) build(value interface{}, name string) (interface{}, interface{}, error) {
	switch v := value.(type) {
	case jObject:
		return s.buildRecord(v, name)
	case []interface{}:
		itemsSchema, err := s.buildArraySchema(v, name)
		if err != nil {
			return nil, nil, err
		}
		itemsNative := make([]interface{}, len(v))
		for i, item := range v {
			native, err := s.nativeOf(item)
			if err != nil {
				return nil, nil, fmt.Errorf("array item %d: %w", i, err)
			}
			itemsNative[i] = native
		}
		return map[string]interface{}{"type": "array", "items": itemsSchema}, itemsNative, nil
	case json.Number:
		if integerLiteral(v) {
			// Ruby JSON.parse turns integer literals into arbitrary-precision
			// Integers; mirror the range check exactly with big.Int.
			big, ok := new(big.Int).SetString(string(v), 10)
			if !ok {
				return nil, nil, fmt.Errorf("unsupported JSON number %s", v)
			}
			if !big.IsInt64() {
				return nil, nil, fmt.Errorf("integer %s is outside Avro long range (%d..%d)", v, longMin, longMax)
			}
			return "long", big.Int64(), nil
		}
		f, err := v.Float64()
		if err != nil {
			return nil, nil, fmt.Errorf("unsupported JSON number %s", v)
		}
		return "double", f, nil
	case string:
		return "string", v, nil
	case bool:
		return "boolean", v, nil
	case nil:
		return "null", nil, nil
	default:
		return nil, nil, fmt.Errorf("unsupported JSON value: %v", value)
	}
}

func (s *deriveState) buildRecord(obj jObject, name string) (interface{}, interface{}, error) {
	schemaFields := make([]map[string]interface{}, 0, len(obj))
	native := make(map[string]interface{}, len(obj))
	recordName := s.uniqueName(name)
	for _, entry := range obj {
		if !namePattern.MatchString(entry.name) {
			return nil, nil, fmt.Errorf("invalid Avro field name %q (must match %s)", entry.name, nameRegex)
		}
		childSchema, childNative, err := s.build(entry.value, nestedName(recordName, entry.name))
		if err != nil {
			return nil, nil, fmt.Errorf("field %q: %w", entry.name, err)
		}
		schemaFields = append(schemaFields, map[string]interface{}{"name": entry.name, "type": childSchema})
		native[entry.name] = childNative
	}
	return map[string]interface{}{
		"type":   "record",
		"name":   recordName,
		"fields": schemaFields,
	}, native, nil
}

// buildArraySchema mirrors the Rails array branch: the schema comes from the
// first item only (its record names are claimed once in the used-names set);
// homogeneity is enforced with order-sensitive shape signatures.
func (s *deriveState) buildArraySchema(items []interface{}, parentName string) (interface{}, error) {
	if len(items) == 0 {
		return "null", nil
	}
	firstShape, err := shapeOf(items[0])
	if err != nil {
		return nil, err
	}
	for _, item := range items[1:] {
		shape, err := shapeOf(item)
		if err != nil {
			return nil, err
		}
		if shape != firstShape {
			return nil, fmt.Errorf("array items are not homogeneous (expected %s)", firstShape)
		}
	}
	schema, _, err := s.build(items[0], nestedName(parentName, "item"))
	return schema, err
}

// nativeOf converts a parsed value to its goavro-native form without touching
// the used-names set (schema derivation already claimed names once, from the
// first array item). longs become exact int64, doubles float64, records maps,
// arrays slices.
func (s *deriveState) nativeOf(value interface{}) (interface{}, error) {
	switch v := value.(type) {
	case jObject:
		out := make(map[string]interface{}, len(v))
		for _, entry := range v {
			child, err := s.nativeOf(entry.value)
			if err != nil {
				return nil, err
			}
			out[entry.name] = child
		}
		return out, nil
	case []interface{}:
		out := make([]interface{}, len(v))
		for i, item := range v {
			child, err := s.nativeOf(item)
			if err != nil {
				return nil, err
			}
			out[i] = child
		}
		return out, nil
	case json.Number:
		if integerLiteral(v) {
			if i, err := v.Int64(); err == nil {
				return i, nil
			}
			return nil, fmt.Errorf("integer %s is outside Avro long range (%d..%d)", v, longMin, longMax)
		}
		f, err := v.Float64()
		if err != nil {
			return nil, fmt.Errorf("unsupported JSON number %s", v)
		}
		return f, nil
	default:
		return value, nil // string, bool, nil
	}
}

// shapeOf is the order-sensitive structural signature used for homogeneity
// checks, mirroring the Rails shape_of. Record names are deliberately ignored.
func shapeOf(value interface{}) (string, error) {
	switch v := value.(type) {
	case jObject:
		var b strings.Builder
		b.WriteString("R(")
		for i, entry := range v {
			if i > 0 {
				b.WriteByte(',')
			}
			b.WriteString(entry.name)
			b.WriteByte('=')
			child, err := shapeOf(entry.value)
			if err != nil {
				return "", err
			}
			b.WriteString(child)
		}
		b.WriteByte(')')
		return b.String(), nil
	case []interface{}:
		if len(v) == 0 {
			return "A(N)", nil
		}
		child, err := shapeOf(v[0])
		if err != nil {
			return "", err
		}
		return "A(" + child + ")", nil
	case json.Number:
		if integerLiteral(v) {
			return "L", nil
		}
		return "D", nil
	case string:
		return "S", nil
	case bool:
		return "B", nil
	case nil:
		return "N", nil
	default:
		return "", fmt.Errorf("unsupported JSON value: %v", value)
	}
}

func nestedName(parent, key string) string {
	return fmt.Sprintf("%s_%s", parent, key)
}

func (s *deriveState) uniqueName(name string) string {
	base := name
	suffix := 2
	for s.usedNames[name] {
		name = fmt.Sprintf("%s_%d", base, suffix)
		suffix++
	}
	s.usedNames[name] = true
	return name
}

func main() {
	addr := os.Getenv("GO_ENCODER_ADDR")
	if addr == "" {
		addr = "0.0.0.0:8081"
	}
	log.Printf("go avro encoder listening on %s", addr)
	log.Fatal(http.ListenAndServe(addr, newMux()))
}

func newMux() *http.ServeMux {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", handleHealth)
	mux.HandleFunc("POST /v1/encode", handleEncode)
	return mux
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.WriteHeader(http.StatusOK)
}

func handleEncode(w http.ResponseWriter, r *http.Request) {
	var req encodeRequest
	dec := json.NewDecoder(io.LimitReader(r.Body, maxBody))
	if err := dec.Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid request body: "+err.Error())
		return
	}
	if req.Repeats < 1 || req.Repeats > maxRepeats {
		writeError(w, http.StatusUnprocessableEntity, fmt.Sprintf("repeats must be between 1 and %d", maxRepeats))
		return
	}
	codec, ok := codecs[req.Codec]
	if !ok {
		writeError(w, http.StatusUnprocessableEntity, "codec must be one of null, deflate")
		return
	}
	if len(req.Source) == 0 {
		writeError(w, http.StatusBadRequest, "source is required")
		return
	}

	// Schema derivation is timed and reported separately (X-Schema-Ms); the
	// source->native conversion happens inside it, mirroring the Ruby arm
	// whose constructor parses the editor JSON before the encode window.
	deriveStart := time.Now()
	schema, native, err := deriveSource(req.Source)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err.Error())
		return
	}
	schemaJSON, err := json.Marshal(schema)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "cannot serialize schema: "+err.Error())
		return
	}
	schemaMs := time.Since(deriveStart).Seconds() * 1000

	// Validate the derived schema against goavro before writing (mirror
	// output must be a well-formed Avro schema).
	if _, err := goavro.NewCodec(string(schemaJSON)); err != nil {
		writeError(w, http.StatusUnprocessableEntity, "derived schema is invalid: "+err.Error())
		return
	}

	// Timed region: container writer creation + record list + append
	// (compression happens while the block is written).
	encodeStart := time.Now()
	records := make([]interface{}, req.Repeats)
	for i := range records {
		records[i] = native
	}
	var buf bytes.Buffer
	ocfw, err := goavro.NewOCFWriter(goavro.OCFConfig{
		W:               &buf,
		CompressionName: codec,
		Schema:          string(schemaJSON),
	})
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, "cannot create container writer: "+err.Error())
		return
	}
	if err := ocfw.Append(records); err != nil {
		writeError(w, http.StatusInternalServerError, "encode failed: "+err.Error())
		return
	}
	encodeMs := time.Since(encodeStart).Seconds() * 1000

	w.Header().Set("X-Schema-Ms", fmt.Sprintf("%.3f", schemaMs))
	w.Header().Set("X-Encode-Ms", fmt.Sprintf("%.3f", encodeMs))
	w.Header().Set("Content-Type", "application/octet-stream")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(buf.Bytes())
}

func writeError(w http.ResponseWriter, status int, message string) {
	body, _ := json.Marshal(map[string]string{"error": message})
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_, _ = w.Write(body)
}
