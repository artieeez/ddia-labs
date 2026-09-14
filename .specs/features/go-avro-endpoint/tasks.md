# Go Avro Endpoint Tasks

## Execution Protocol (MANDATORY -- do not skip)

Implement these tasks with the `tlc-spec-driven` skill: **activate it by name and follow its Execute flow and Critical Rules.** Do not search for skill files by filesystem path. The skill is the source of truth for the full flow (per-task cycle, sub-agent delegation, adequacy review, Verifier, discrimination sensor).

**If the skill cannot be activated, STOP and tell the user - do not proceed without it.**

---

**Design**: decision log in `.specs/STATE.md` (no formal design.md — Medium scope)
**Status**: In Progress (T1-T4 done)

---

## Test Coverage Matrix

> Generated from codebase sampling (`avro-lab/go/**` to be created, `app/javascript/controllers/encoder_controller.js`, `test/controllers/encodings_controller_test.rb`, `.github/workflows/ci.yml`, `apps/staging/ddia-labs/*` in artr-gitops) - repo has Minitest unit + integration and a new Go suite; presentation verified via browser smoke. Guidelines found: repo tests + artr-gitops lint conventions - strong defaults applied.

| Code Layer | Required Test Type | Coverage Expectation | Location Pattern | Run Command |
| ---------- | ------------------ | -------------------- | ---------------- | ----------- |
| Go service (schema derive + encode) | unit | 1:1 to spec ACs; every listed edge case; round-trip + precision | `avro-lab/go/*_test.go` | `cd avro-lab/go && go vet ./... && go test ./...` |
| Client JS (go arm) | e2e (browser smoke) + integration (view test) | Button 5 present in order; direct `/go/v1/encode` fetch; bar segments render; error path | `app/javascript/controllers/encoder_controller.js` + `test/controllers/encodings_controller_test.rb` | `cd avro-lab && mise exec -- bin/rails test` + `playwright-cli` |
| GitOps manifests | none (lint gate only) | kubeconform + repo lint clean | `apps/staging/ddia-labs/*` (artr-gitops) | artr-gitops lint scripts |
| Build/entry (Dockerfile, bin/start) | none (build gate only) | image builds; both processes up | `avro-lab/Dockerfile` | `docker build` + smoke |
| CI | none (config) | workflow well-formed; go job runs | `.github/workflows/ci.yml` | passes in CI |

## Gate Check Commands

> Generated from codebase - confirm before Execute.

| Gate Level | When to Use | Command |
| ---------- | ----------- | ------- |
| Quick | After rails-only tasks | `cd avro-lab && mise exec -- bin/rails test` |
| Full | After Go/client tasks | quick + `cd avro-lab/go && go vet ./... && go test ./...` + `cd avro-lab && mise exec -- bin/rubocop` |
| Build | After image tasks | full + `docker build -t ddia-lab:test ./avro-lab` |

---

## Execution Plan

### Phase 1: Go endpoint end-to-end

```
T1 → T2 → T3 → T4 → T5
```

---

## Task Breakdown

### T1: Go encoder service with schema derivation ✅ COMPLETE

**What**: Rewrite `avro-lab/go/` endpooint as the direct, self-contained encoder: request `{source, repeats, codec}` (no schema from the client), Go derives the Avro schema mirroring `AvroSchema.derive` (ordered JSON walk, `Root_<path>` record names, global uniqueness suffixing, shape-signature homogeneity, long-range and name validation), times `X-Schema-Ms` (derive) and `X-Encode-Ms` (OCF writer + record loop + close), writes the container (goavro, null/deflate), binds `0.0.0.0:8081` (`GO_ENCODER_ADDR`), `GET /healthz`, JSON errors.
**Where**: `avro-lab/go/main.go`
**Depends on**: None
**Reuses**: `app/models/avro_schema.rb` rules mirrored 1:1; `convertValue`/ordered-walk helpers
**Requirement**: GO-02, GO-03, GO-04, GO-06, GO-09, GO-10, GO-11

**Done when**:

- [ ] `go vet ./... && go test ./...` pass: round-trip records == source (GO-04), long >2^53 exact (GO-06), deflate < null on repetitive data, name/long-range/homogeneity errors mirror Ruby messages, uniqueness suffixing `name`,`name_2`,`name_3`, repeats/codec bounds, missing source 400, `/healthz` 200, GET /v1/encode 405
- [ ] Both timing headers returned and non-negative

**Tests**: unit
**Gate**: full
**Commit**: `feat(go): add self-contained avro encoder endpoint with schema derivation`

---

### T2: Client go arm (direct fetch) + dev proxy ✅ COMPLETE

**What**: `encoder_controller.js` — `encodeGo()` fetches `/go/v1/encode` directly (`{source, repeats, codec:"deflate"}`, no CSRF), reads `X-Schema-Ms`/`X-Encode-Ms`, renders `AVRO·GO` bar with schema/encode/download/decode; button 5 in `new.html.erb`; `.lab__button--go` accent + legend note in `application.css`; dev-only route + tiny controller proxying `/go/v1/encode` → `127.0.0.1:8081`; view test asserts button order.
**Where**: `app/javascript/controllers/encoder_controller.js`
**Depends on**: T1
**Reuses**: Existing Timeline/segments/legend machinery; `errorMessage` parsing
**Requirement**: GO-01, GO-05, GO-08

**Done when**:

- [ ] Rails quick gate + rubocop pass; view test asserts 5th button in story order
- [ ] Browser smoke against local Rails + running Go service: Go bar renders `AVRO·GO ×100 · deflate ✓` with 4 segments; error path shows message when Go is stopped

**Tests**: e2e (browser smoke) + integration (view test)
**Gate**: full
**Commit**: `feat(avro-lab): add go arm with direct /go/v1/encode fetch`

---

### T3: GitOps manifests (prepared for human push) ✅ COMPLETE (push pending, human)

**What**: In the artr-gitops working tree: `deployment.yaml` +containerPort 8081; new `service-go.yaml` (Service `ddia-labs-go` → 8081); new `middleware.yaml` (Traefik StripPrefix `/go`); `ingressroute.yaml` + `PathPrefix("/go")` route to `ddia-labs-go:8081` (same TLS). Left unstaged with a suggested commit message (repo's AGENTS.md: human pushes).
**Where**: `apps/staging/ddia-labs/deployment.yaml`
**Depends on**: T2 (port contract 8081)
**Reuses**: Existing staging app conventions; `ocir-pull`; wildcard TLS
**Requirement**: GO-01 (routing), success criteria #3

**Done when**:

- [ ] kubeconform + repo lint clean on the touched manifests
- [ ] Manifest diff reviewed; suggested commit message provided; NOT pushed (human)

**Tests**: none (lint gate only — matrix)
**Gate**: build (lint)
**Commit**: n/a (human push; suggested: `add ddia-labs go route: Service, strip-prefix middleware, ingress path, containerPort 8081`)

---

### T4: Ship the Go encoder in the app image ✅ COMPLETE

**What**: `avro-lab/Dockerfile` multi-stage — golang build stage (`go vet`, `go test`, `CGO_ENABLED=0 go build`), static binary copied into final stage as UID 1000; new `avro-lab/bin/start` (start sidecar, wait `/healthz`, `exec bin/rails server`); `.dockerignore` keeps `go/` in the build context.
**Where**: `avro-lab/Dockerfile`
**Depends on**: T3 (binary and app code are already in by this point)
**Reuses**: Existing multi-stage pattern
**Requirement**: GO-07

**Done when**:

- [ ] `docker build` succeeds locally; `docker run` → `/up` 200, `/go/healthz` 200 via container, a `/go/v1/encode` POST returns a container (exercises the same paths the ingress route will hit)
- [ ] Build gate passes (`go test` runs inside the image build)

**Tests**: none (build gate only — matrix)
**Gate**: build
**Commit**: `build(avro-lab): ship the go encoder in the app image`

---

### T5: CI go job + docs

**What**: `.github/workflows/ci.yml` — `go` job (`setup-go`, `go vet`, `go test ./...` in `avro-lab/go`); `avro-lab/README.md` — fifth way (direct Go endpoint, mirror rules, timing semantics); legend note already in T2.
**Where**: `.github/workflows/ci.yml`
**Depends on**: T4
**Reuses**: Existing CI job scaffolding
**Requirement**: GO-02 (documentation)

**Done when**:

- [ ] CI workflow well-formed; README documents the Go arm, the routing and the mirror rule; full gate green

**Tests**: none (build/config — matrix)
**Gate**: full
**Commit**: `ci(avro-lab): gate the go module in CI and document the arm`

---

## Phase Execution Map

```
Phase 1:  T1 → T2 → T3 → T4 → T5
```

Execution is strictly sequential - one task at a time. The feature fits a single batch (5 tasks ≤ ~8): **execution is inline, no sub-agents.** The Verifier (author ≠ verifier, spec-anchored + discrimination sensor, `validation.md`) runs automatically after the final commit.

---

## Task Granularity Check

| Task | Scope | Status |
| ---- | ----- | ------ |
| T1: Go endpoint | 1 Go module + handler | ✅ Granular |
| T2: Client go arm | 1 JS controller (view/css/proxy co-edited) | ✅ Cohesive |
| T3: GitOps manifests | 4 manifest files (one concern) | ✅ Cohesive |
| T4: Image + entry | 1 Dockerfile (+ bin/start) | ✅ Granular |
| T5: CI + docs | 1 workflow (+ README) | ✅ Granular |

## Diagram-Definition Cross-Check

| Task | Depends On (body) | Diagram Shows | Status |
| ---- | ----------------- | ------------- | ------ |
| T1 | None | T1 | ✅ Match |
| T2 | T1 | T1→T2 | ✅ Match |
| T3 | T2 | T2→T3 | ✅ Match |
| T4 | T3 (chain) | T3→T4 | ✅ Match |
| T5 | T4 | T4→T5 | ✅ Match |

## Test Co-location Validation

| Task | Code Layer | Matrix Requires | Task Says | Status |
| ---- | ---------- | --------------- | --------- | ------ |
| T1 | Go service | unit | unit | ✅ OK |
| T2 | Client JS + view | e2e smoke + integration | e2e + integration | ✅ OK |
| T3 | GitOps manifests | none (lint gate) | none | ✅ OK |
| T4 | Build/entry | none | none | ✅ OK |
| T5 | CI/config | none | none | ✅ OK |