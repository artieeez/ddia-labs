# Project Memory — ddia-labs

## Decisions

| ID | Date | Decision | Rationale |
| -- | ---- | -------- | --------- |
| AD-001 | 2026-09-14 | Go arm routes at the ingress (`PathPrefix("/go")` on the existing ddia.artr.com.br IngressRoute) straight to the sidecar process (Service `ddia-labs-go` → 8081). Rails is out of the loop for the Go arm. | Option B chosen by the user: no Rails-proxy noise, no DNS/cert work (the `*.artr.com.br` wildcard does not cover 3-label subdomains), same Origin so no CORS/CSRF changes. |
| AD-002 | 2026-09-14 | Go encoder library: `github.com/linkedin/goavro/v2` (v2.15.0). | hamba/avro is unmaintained (maintainer warning in repo); goavro supports OCF writer with null/deflate. Its trailer-less OCF output is accepted by avro-js (reader stops at EOF). |
| AD-003 | 2026-09-14 | Go derives the Avro schema itself, mirroring `AvroSchema.derive` (ordered JSON walk, `Root_<path>` record names, global uniqueness suffixing, shape-signature homogeneity, long-range and name validations). | With Rails out of the loop the derive must live in Go; the client ✓ badge is the honesty check between the two implementations. |
| AD-004 | 2026-09-14 | All Go-arm timing measured inside the Go process: `X-Schema-Ms` (derive) and `X-Encode-Ms` (OCF writer + record loop + close). Source→native conversion excluded, mirroring the Ruby arm's constructor parse. | Comparable encoder-only bars; no proxy hops. |
| AD-005 | 2026-09-14 | Sidecar ships inside the same image (multi-stage golang build → ruby final stage); `bin/start` waits for `/healthz` before `exec bin/rails server`; sidecar binds `0.0.0.0:8081` (containerPort) since Traefik must reach it. | One image, one ArgoCD app, honest same-pod timing. |
| AD-006 | 2026-09-14 | Dev-only Rails route proxies `/go/v1/encode` → `127.0.0.1:8081` so the browser exercises the same URL locally; production routes the path straight to Go. | Client code stays env-independent. |

## Interpreter/format findings (from earlier work)

- The Ruby `avro` gem is pure Ruby: the record loop is ~98% of encode time (see `avro-lab/README.md`); JSON's `json` gem is a C call → ≈20x gap. This is a language-binding artifact, not a property of the formats. Write-once/read-many is Avro's scenario; CPU-bound → encode in a compiled language (Java/Go).
- Deflate in the Ruby gem compresses per 64 KB block during the write loop; ~2 ms at 10k records — smaller than single-shot noise (±15%). The lab charts one-shot numbers; the Go arm now demonstrates the compiled-language counterpoint.

## Handoff

Snapshot from Thursday sessions on `ddia-labs` main @ `2cfa933` (pre-Go-arm):

- Deployed and verified live: Landing (`/`) → Avro Lab (`/avro`) at https://ddia.artr.com.br.
- Arms: 1 JSON (baseline), 2 Avro · naive (schema re-derived per record), 3 Avro null, 4 Avro deflate. Timeline appends newer runs at the bottom; schema-segment checkbox; notes under the timeline.
- Pipeline: push main → CI → arm64 image (native runner) → OCIR → gitops tag bump → Argo CD sync. GitOps manifests live in the separate `artr-gitops` repo (human pushes).
- Ship hashes: image `sha-<git>` tags; latest commits pre-Go-arm `2cfa933`, deployed `7209019`.
- **In progress**: `go-avro-endpoint` feature (spec/tasks under `.specs/features/go-avro-endpoint/`, decision log above). Go binary compiled locally on the Mac (go1.25.6); `avro-lab/go` module bootstrapped (goavro v2.15.0).
- **Next**: execute tasks T1→T5 inline; Verifier + `validate_state.py` at the end; then get explicit user go-ahead to push the app repo and prepare/have-the-human-push the GitOps manifests.
- Blast radius: local commits only until the user authorizes push/deploy.