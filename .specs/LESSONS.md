# LESSONS - auto-maintained by scripts/lessons.py

> Machine-owned. Do NOT hand-edit. Changes are overwritten on the next `lessons.py` write.
> Canonical state lives in `.specs/lessons.json`. Edit lessons only via the script.
> promote_threshold=2 distinct features · window_days=45 · quarantine_threshold=2

## Confirmed (load these at Specify/Design)

Corroborated across multiple features. Safe to apply as guidance.

_none_

## Candidates (under observation - do NOT load as guidance yet)

Seen once or not yet corroborated. Tracked, not trusted.

### L-001 - When a code layer's approved test type is manual browser E2E, the discrimination sensor must scope mutants to automated layers; a JS-layer surviving mutant is expected, not a defect.
- signal: `surviving_mutant` · recurrence: 1 feature(s) · scope: `javascript` · harmful: 0
- features: go-avro-endpoint
- evidence: encoder_controller.js: encodeGo() fetch URL mutation (JS layer), sanctioned manual E2E (javascript)
- last seen: 2026-09-14T21:38:06Z

## Quarantined (failed when applied - ignore)

A confirmed lesson that recurred alongside failure. Kept for the maintainer to review.

_none_
