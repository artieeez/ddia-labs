# Go Avro Endpoint Specification

## Problem Statement

The lab's outline note already claims "CPU-bound on Avro? Encode in a compiled language
instead — Java or Go". A fifth button should make that claim measurable: a real Go HTTP
endpoint that derives the Avro schema itself and encodes the same records with the deflate
codec, routed directly at the ingress — the Rails app is completely out of the loop for
this arm, so the timeline shows pure compiled-encoder timing.

## Goals

- [ ] A fifth arm whose browser request goes straight to a Go endpoint via a `/go/*` path route on the existing IngressRoute, with both schema derivation and encode time measured inside the Go process
- [ ] The Go arm round-trips identically (same records, same count, ✓ badge), including longs beyond 2^53
- [ ] One image, one ArgoCD app: the Go binary ships inside the existing Rails image; one new k8s Service + Traefik route + strip-prefix middleware

## Out of Scope

| Feature | Reason |
| ------- | ------ |
| Separate Go deployment/replica scaling | Sidecar process in the existing pod keeps monitoring/replicas aligned with the Rails app |
| Rails involvement in the Go arm | Option B confirmed: the browser calls `/go/v1/encode` directly; Rails never sees this request |
| Subdomain routing (`go.ddia.artr.com.br`) | The `*.artr.com.br` wildcard does not cover 3-label names; would need DNS record + cert (rejected) |
| Snappy / zstd codecs | Deflate is the requested codec; `null` passes through the same endpoint |
| Java arm | Not requested; Go directly demonstrates the compiled-language claim |

---

## Assumptions & Open Questions

| Assumption / decision | Chosen default | Rationale | Confirmed? |
| --------------------- | -------------- | --------- | ---------- |
| Routing | Traefik `PathPrefix("/go")` route on the existing IngressRoute + StripPrefix middleware → new Service `ddia-labs-go` (port 8081) → the sidecar process | No DNS/cert work; same host/Origin so no CORS/CSRF changes | y (user chose B) |
| Go Avro library | `github.com/linkedin/goavro/v2` (v2.15.0) | hamba/avro is unmaintained (repo warning); goavro OCF writer + null/deflate | y |
| Schema derivation | Go mirrors `AvroSchema.derive` (ordered walk, `Root_<path>` names, global uniqueness suffixing, shape-signature homogeneity, long-range/name errors) | Rails is out of the loop; the ✓ badge is the honesty check between the two implementations | y |
| Timing semantics | Go measures `X-Schema-Ms` around its derive and `X-Encode-Ms` around OCF writer creation + record loop + close; source→native conversion excluded (parity with the Ruby arm's constructor parse) | All timing happens inside the compiled process; no proxy noise | y |
| Go arm codec | Client sends `codec: "deflate"`; endpoint validates `null\|deflate` | Matches the button label | y |
| Bind address | `0.0.0.0:8081` (env `GO_ENCODER_ADDR`), declared as a containerPort | Traefik Service must reach the sidecar from outside the pod | y |
| Filename | `payload-<n>-go.avro` | Distinct per arm so downloads never collide | y |
| Boot ordering | `bin/start` waits for Go `/healthz` before starting Rails | No proxy race on pod start | y |
| Dev oracle | A dev-only Rails route proxies `/go/v1/encode` to `127.0.0.1:8081` so the browser exercises the same URL in dev (prod routes it straight to Go) | Keeps client code env-independent; the proxy exists only in development | y |

**Open questions:** none - all resolved or logged above.

---

## User Stories

### P1: Go Encoder Arm ⭐ MVP

**User Story**: As a lab visitor, I want a Go endpoint that derives the Avro schema and encodes with the deflate codec, so that I can see the compiled-language encode time next to the pure-Ruby arms.

**Why P1**: Makes the page's "Java or Go" callout measurable.

**Acceptance Criteria** (EARS):

1. WHEN a user clicks the Go arm button THEN the browser SHALL POST `{source, repeats, codec: "deflate"}` to `/go/v1/encode` (same origin, no Rails hop) AND SHALL render a `AVRO·GO` timeline bar with schema/encode/download/decode segments. <!-- event-driven -->
2. WHEN the Go endpoint receives a request THEN it SHALL derive the Avro schema mirroring `AvroSchema.derive` (int→long, float→double, string→string, bool→boolean, null→null, object→`Root_<path>` record, homogeneous arrays) AND SHALL write the container with the requested codec. <!-- event-driven -->
3. WHEN the Go endpoint responds successfully THEN `X-Schema-Ms` SHALL be its schema-derivation wall time AND `X-Encode-Ms` SHALL be its container-encode wall time. <!-- event-driven -->
4. WHILE the Go arm is used the decoded records SHALL equal the source records with count == repeats (✓ badge). <!-- state-driven -->
5. IF the Go endpoint errors or is unreachable THEN the client SHALL show the error message without downloading a file. <!-- unwanted-behavior -->
6. IF the source contains integer values beyond 2^53 (within ±2^63) THEN the decoded Go output SHALL preserve the exact values. <!-- unwanted-behavior -->
7. IF the Go process is not yet listening when the pod starts THEN `bin/start` SHALL wait for `/healthz` before starting the Rails server. <!-- unwanted-behavior -->
8. The Go arm SHALL use the same client decode path (avro-js) as the other arms, so its decode segment is comparable. <!-- ubiquitous -->

**Independent Test**: Run 5 arms at ×10,000; the Go bar's encode segment must be visibly smaller than the Ruby null/deflate bars and the round-trip badge must be ✓.

---

## Edge Cases

- IF repeats is outside 1..100_000 on the go arm THEN the endpoint SHALL reject it with a 422-style body.
- IF an object key is not a valid Avro name (`^[A-Za-z_][A-Za-z0-9_]*$`) THEN the Go derive SHALL error with the same message as the Ruby derive.
- IF an integer exceeds the Avro long range (±2^63) THEN the Go derive SHALL error.
- IF an array is non-homogeneous (shape signatures differ) THEN the Go derive SHALL error like the Ruby derive.
- IF three record names collide after uniqueness suffixing THEN the names SHALL be `name`, `name_2`, `name_3`.
- IF the Go endpoint is unavailable in dev THEN the dev-only proxy route SHALL surface the connection error to the client.

---

## Requirement Traceability

| Requirement ID | Story | Phase | Status |
| -------------- | ----- | ----- | ------ |
| GO-01 | P1 | Verifying | Pending |
| GO-02 | P1 | Verifying | Pending |
| GO-03 | P1 | Verifying | Pending |
| GO-04 | P1 | Verifying | Pending |
| GO-05 | P1 | Verifying | Pending |
| GO-06 | P1 | Verifying | Pending |
| GO-07 | P1 | Verifying | Pending |
| GO-08 | P1 | Verifying | Pending |
| GO-09 | Edge | Verifying | Pending |
| GO-10 | Edge | Verifying | Pending |
| GO-11 | Edge | Verifying | Pending |

**Coverage:** 11 total, 11 mapped to tasks, 0 unmapped

---

## Success Criteria

- [ ] At ×10,000 the Go arm's encode segment is a visibly smaller fraction of the bar than the Ruby arms for the same records
- [ ] The Go arm passes all rails and Go tests and round-trips with the ✓ badge on https://ddia.artr.com.br/avro
- [ ] `curl https://ddia.artr.com.br/go/healthz` returns 200 and `POST /go/v1/encode` returns a container (proves ingress-level routing works)