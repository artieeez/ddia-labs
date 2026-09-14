# go-avro-endpoint Validation

**Date**: 2026-09-14
**Spec**: `.specs/features/go-avro-endpoint/spec.md`
**Diff range**: `f13b1a1..HEAD` (feature commits `9624d67`..`62e4007`)
**Verifier**: independent sub-agent (author ≠ verifier)

---

## Task Completion

| Task | Status | Notes |
| ---- | ------ | ----- |
| T1 | ✅ Done | Go endpoint + derive mirror; 14 Go tests |
| T2 | ✅ Done | JS arm + dev proxy; 5 proxy tests + view test |
| T3 | ✅ Done | GitOps manifests prepared (kubeconform 0 invalid, yamllint clean); human push pending |
| T4 | ✅ Done | Multi-stage image + bin/start; container smoke OK |
| T5 | ✅ Done | CI go job + README |

All tasks marked complete in `tasks.md`. Baseline porcelain clean before validation.

---

## Spec-Anchored Acceptance Criteria

| Criterion (GO-x) | Spec-defined outcome | `file:line` + assertion | Result |
| --- | --- | --- | --- |
| GO-01: browser POSTs `{source, repeats, codec:"deflate"}` to `/go/v1/encode`, renders AVRO·GO bar with 4 segments | button exists in order; bar renders on click | `avro-lab/test/controllers/encodings_controller_test.rb:13` — `assert_select "button[data-action='encoder#encodeGo']"`; `:14` — `assert_match(/baseline.*naive.*null codec.*deflate.*Go endpoint/m, response.body)`. **Fetch URL, payload shape, 4-segment render: no automated assertion (manual browser E2E per approved matrix — passed in-session; JS layer has no test infra).** | ⚠️ Partial — button/order automated; client fetch+render manual only |
| GO-02: derive mirrors AvroSchema.derive (int→long, float→double, string, bool, null, `Root_<path>` records, homogeneous arrays); container with requested codec | decoded records carry int64 longs, float64 doubles, exact nulls; nested path names present; deflate works | `avro-lab/go/main_test.go:113` — `reflect.DeepEqual(record, expectedNative())` (int64(2), 3.14, "x", true, nil); `:120` — nested records + record arrays DeepEqual; `:147-158` — deflate < null sizes; `:197` — `"name":"Root_user"` / `"name":"Root_tags_item"` preserved; `:243` — homogeneity error. Byte-for-byte schema identity Ruby↔Go verified ad hoc (not a committed test). | ✅ PASS |
| GO-03: X-Schema-Ms = derive wall time; X-Encode-Ms = encode wall time | both headers present, non-negative | `avro-lab/go/main_test.go:95` — `strconv.ParseFloat(resp.Header.Get(header), 64)` with `ms < 0` fatal, loop over both headers. Exact wall-time values untestable; presence+positivity is the feasible assertion. | ✅ PASS (assertion is presence/≥0 — strongest feasible for timing) |
| GO-04: decoded records == source, count == repeats (✓ badge) | exact equality + counts | `avro-lab/go/main_test.go:109` — `len(records) != 3`; `:113` — DeepEqual per record; `:124` — `len(records) != 2`; `:158` — `!= 200` for deflate. Client ✓ badge: manual E2E (JS layer). | ✅ PASS (server); ✓ badge manual |
| GO-05: client shows error message without downloading | 422/503 relayed with legible message | `avro-lab/test/controllers/go_proxy_controller_test.rb:53-54` — `assert_response :unprocessable_entity` + `/not homogeneous/` on body; `:63-64` — `:service_unavailable` + `/go encoder unavailable/`. Client-side display: manual E2E. | ✅ PASS (proxy relay automated); client display manual |
| GO-06: longs >2^53 preserved exactly (within ±2^63) | exact int64 | `avro-lab/go/main_test.go:172` — `got != int64(9007199254740993)` | ✅ PASS |
| GO-07: bin/start waits for Go /healthz before Rails | Go up before Rails serves | No automated test. Evidence: `avro-lab/bin/start` wait loop + `exec bin/rails server`; container smoke (manual, in-session): rails `/up` 200 AND go `/healthz` 200 after boot. | ⚠️ Manual/container-smoke only — no automated assertion |
| GO-08: same avro-js client decode path as other arms | decode segment from shared decodeAvro | `avro-lab/app/javascript/controllers/encoder_controller.js:132` — decode branch gated on `format === "avro" \|\| format === "go"` with shared `decodeAvro`. No automated test; manual E2E ✓. | ⚠️ Manual + inspection |
| GO-09 (edge): repeats outside 1..100_000 rejected 422 | 422 + "repeats" message | `avro-lab/go/main_test.go:270` — `repeats` 0/100001 → `status != 422 \|\| !strings.Contains(error,"repeats")` fatal | ✅ PASS |
| GO-10 (edge): invalid Avro name / long-range / non-homogeneous arrays error like Ruby | 422 + mirror messages | `avro-lab/go/main_test.go:215` — `"outside Avro long range"`; `:229` — `"invalid Avro field name"`; `:243` — `"not homogeneous"` | ✅ PASS (substring match; name regex rendering differs cosmetically from Ruby's — ⚠️ minor precision note) |
| GO-11 (edge): 3 colliding names → name, name_2, name_3 | suffixing mechanism | `avro-lab/go/main_test.go:202` — asserts one `Root_a_b` and one `Root_a_b_2`. The `_3` case is not directly asserted (loop is generic: `suffix++` while used). | ⚠️ Partial — `_2` proven, `_3` implied by generic loop |
| GO-11b (edge): dev proxy unavailable → surfaces connection error | 503 + message | `avro-lab/test/controllers/go_proxy_controller_test.rb:63-64` | ✅ PASS |

**Status**: ✅ All ACs covered at the level the approved Test Coverage Matrix defines. For GO-01/05/07/08 the automated layer covers the server contracts; the client/entry behaviors are covered by manual browser E2E + container smoke exactly as the matrix mandates ("presentation = e2e browser smoke, manual; build/entry = none"). ⚠️ Noted: no automated frontend or shell-level assertions exist for the JS layer or bin/start (repo-wide: no JS test infra for any of the five arms).

---

## Discrimination Sensor

Run in a throwaway git worktree at `/tmp/verif-scratch` (HEAD 62e4007); real tree untouched (porcelain 0 == pre-sensor baseline; worktree removed).

| Mutation | File:line | Description | Killed? |
| -------- | --------- | ----------- | ------- |
| 1 | `avro-lab/go/main.go` uniqueName | Removed record-name uniqueness suffixing (always return the base name) | ✅ Killed — `TestRecordNameUniquenessSuffixing` FAILs |
| 2 | `avro-lab/go/main.go` handleEncode | Removed `X-Encode-Ms` header write | ✅ Killed — `TestEncodeDecodesToRepeatsRecords` FAILs (empty header) |
| 3 | `avro-lab/go/main.go` build (integer literal) | Long-range check removed (2^63 accepted) | ✅ Killed — `TestLongRangeError` FAILs |
| 4 | `avro-lab/go/main.go` buildArraySchema | Homogeneity comparison removed | ✅ Killed — `TestNonHomogeneousArrayError` FAILs |
| 5 | `avro-lab/app/javascript/controllers/encoder_controller.js` | go arm POSTs `/encoding` instead of `/go/v1/encode` | ❌ **Survived** — full Rails suite still passes (44/179): no automated test asserts the fetch URL. This is the sanctioned manual-E2E layer (approved matrix); session E2E verified correct behavior, but nothing automated discriminates a regression here |

**Sensor depth**: standard (lightweight fault-injection, 5 targeted mutations across the highest-risk new code)
**Result**: **4/5 killed — PASS on the automated-testable layers; 1 surviving mutant on the JS layer (documented coverage gap, no repo JS test infra — shared by all five arms)**

---

## Gate Check

- **Gate command**: Full + Build (Go: `go vet ./... && go test ./...` in `avro-lab/go`; Rails: `cd avro-lab && mise exec -- bin/rails test`; lint: `mise exec -- bin/rubocop`)
- **Result**: Go `ok`; Rails **44 runs, 179 assertions, 0 failures, 0 errors**; RuboCop **no offenses**
- **Test count before feature**: rails 39 · go 0
- **Test count after feature**: rails 44 (+5 proxy/controller) · go 14
- **Delta**: +5 rails, +14 Go — zero deletions
- **Skipped tests**: none

---

## Code Quality

| Principle | Status |
| --------- | ------ |
| Minimum code | ✅ Go 449 lines is faithful-mirror length (ordered JSON walker + derive + HTTP); no speculative abstractions (no interfaces/generics/options) |
| Surgical changes | ✅ Diff `f13b1a1..HEAD` touches only feature files (go/, proxy, JS, view, routes, bin/start, Dockerfile, ci.yml, docs, specs) |
| No scope creep | ✅ Dev proxy is the documented dev-test oracle (assumption row, user-confirmed); sniffable `net_http` class attr is a minimal test seam |
| Matches patterns | ✅ Mirrors Rails model semantics; minitest + go stdlib convention; Traefik/GitOps conventions |
| Spec-anchored outcome check | ✅ Server-side asserted values match spec outcomes (substring messages noted) |
| Per-layer Coverage Expectation | ✅ Domain (Go derive/encode): 1:1 AC mapping + every listed edge; Controller (proxy): happy + edge + error; Presentation: manual E2E per approved matrix |
| Every test maps to spec (Check C) | ✅ All Go tests trace to GO-02/03/04/06/09/10/11 + proxy relays to GO-05/11b; no speculative tests |
| Guidelines followed | "none — strong defaults applied" (repo has no separate testing-guideline doc; AGENTS.md conventions followed) |

**Pre-existing nit (outside feature diff, flagged not fixed)**: `encodings_controller_test.rb` JSON test contains a duplicated `X-Schema-Ms` assertion pair (artifact of the earlier schema-segment work, not present in `f13b1a1..HEAD`).

---

## Edge Cases

- [x] Repeats 0/100001 → 422 with "repeats" (`main_test.go:270`)
- [x] Invalid Avro name `a-b` → 422 "invalid Avro field name" (`main_test.go:229`)
- [x] Integer 2^63 → 422 "outside Avro long range" (`main_test.go:215`)
- [x] Non-homogeneous array → 422 "not homogeneous" (`main_test.go:243`)
- [x] Dev proxy unreachable → 503 "go encoder unavailable" (`go_proxy_controller_test.rb:63`)
- [x] Name collision → `name`/`name_2` proven (`main_test.go:202`); `name_3` covered by the generic suffix loop, not directly asserted

---

## Summary

**Overall**: ✅ Ready — with documented manual-layer caveats

**Spec-anchored check**: 7/11 ACs fully automated + 4 ACs/edges automated on their server contracts with client-side behavior verified by manual E2E per the approved matrix; 2 minor precision notes (name-error regex rendering; `_3` suffix not directly asserted)

**Sensor**: 4/5 mutations killed on the automated-testable layers; 1 survivor on the JS layer (no automated frontend test infra in this repo — sanctioned manual E2E; session E2E passed)

**Gate**: Go ok + Rails 44/179 0-fail + RuboCop clean

**What works**: derived schemas byte-identical to Ruby on a gnarly sample; deflate containers smaller; full round-trips (incl. nested records, record arrays, longs >2^53); card-carrying error mirrors; timing headers measured in-process; dev proxy relays errors precisely; image boots Go+Rails with correct port split.

**Issues found** (ranked):
1. (Non-blocking, scope-consideration) No automated assertion exists that the go arm posts to `/go/v1/encode` — the JS layer has no test infra (repo-wide, all five arms). Recommended optional follow-up: a minimal Node-based controller unit test asserting `encodeGo`'s fetch URL + payload, or accept manual E2E per the approved matrix.
2. (Minor) `bin/start` wait-then-exec ordering has no automated test (container smoke only).
3. (Minor, precision) `Root_<name>_3` suffix case not directly asserted; name-error message regex rendering differs cosmetically from Ruby's.
4. (Pre-existing nit, outside this diff) duplicated `X-Schema-Ms` assertions in `encodings_controller_test.rb`.

**Next steps**: orchestrator decides on the JS-layer discrimination follow-up; then the app push (needs explicit user go-ahead) and the GitOps human push (manifest commit message suggested in tasks.md).