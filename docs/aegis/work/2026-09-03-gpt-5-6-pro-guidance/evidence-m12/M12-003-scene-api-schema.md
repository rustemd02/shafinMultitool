# M12-003 — Scene API schema v1 evidence

Status: CLOSED on the current store.

## Frozen surface

- `backend/openapi-scene-v1.yaml` (OpenAPI 3.0.3): create/poll/
  clarification-answer/cancel for one Scene service, App Attest Bearer
  token, mandatory Idempotency-Key, version triple
  (schema/model/provider) + request hash on every status, terminal
  exclusivity, 410 kill-switch, placeholder host
  (`https://scene-generation.set-os.local/v1`) — the M5-025 client
  must not point at a real backend until deployment config replaces it.
- `backend/schemas/scene-job-v1.schema.json` (Draft 2020-12): job
  envelope reusing the frozen M3-023 `scene-contract-v1` defs
  (scene_script, scene_clarification_payload, identifiers); terminal
  branches mutually exclusive via `allOf`; schema/model/provider
  versions, lowercase-hex request hash, idempotency key, server time.
- `backend/schemas/validate_scene_job.py`: mandatory Draft 2020-12
  validation + stdlib semantic checks (request/epoch binding between
  envelope and embedded clarification, result version-triple equality,
  clarification option uniqueness, size bounds). Fail-closed when
  `jsonschema` is unavailable.
- `shafinMultitool/SceneGeneratorModule/Services/
  SceneGenerationAPIContracts.swift`: Swift mirror of the frozen API
  (status/failure/result/create/clarification types + fail-closed
  `SceneJobValidation` incl. kill-switch terminal rejection). No
  network code, no credentials, no live host. Media fields are
  unrepresentable by construction (no image/audio/video member).

## Fixtures

`backend/schemas/fixtures/`: 6 positive
(pending/running/complete/awaiting-clarification/failed/cancelled) +
5 negative (complete missing result, complete with failure, wrong
backend version, malformed hash, stale clarification binding).
Complete/awaiting fixtures reuse the M3-023 valid output/clarification
with aligned version triples.

## Verification

- `python3 backend/schemas/validate_scene_job.py` → PASS (6 positive
  + 5 negative).
- `SceneGenerationAPIContractsTests` 11/11 PASS on permitted iPhone
  17e (`/private/tmp/m12003-tests.xcresult`): pending/running carry no
  terminal payload, complete binds version-matched result with
  non-empty beats, clarification binds the same request UUID,
  failed/cancelled surface typed codes, all 5 negatives reject with
  the exact typed reason, kill-switch failure is a terminal rejection.

## Boundaries

No provider is selected, no host is live, no credentials exist in the
app (unchanged from M12-001/M12-002). This schema unblocks M12-004…
M12-009 (request limits, auth, quota, idempotency, lifecycle,
timeouts) and M5-025 (client) — none of which may invent a live
backend or fake provider responses.
