# M12-004 — request limits/redaction evidence

Status: CLOSED on the current store.

## Enforced allowlist

Accepted create-job payload is limited to: UTF-8 screenplay text
(≤4000 chars / ≤64 KiB), locale (`ru`/`en`), marked-object
identifiers (`canonical_id`, optional `name`, ≤32 entries),
constraints (`maximum_scenes` 1…8), client/build/schema metadata,
request hash, version triple. Camera frames, audio, contacts, device
advertising IDs, file uploads, and unknown fields are rejected.

## Delivered

- `backend/scene_request_limits.py`: fail-closed reference validator
  (never raises; unknown fields rejected, media/personal-data field
  names rejected with explicit reason, text/locale/marked/constraints/
  hash bounds enforced) + deterministic canonical JSON for
  request-hash computation.
- `backend/tests/test_scene_request_limits.py`: 9 tests + 5 subtests
  (valid RU/EN, oversize text, unknown field, 5 media/personal fields,
  unsupported locale, marked overflow, constraints bound, bad hash,
  canonical determinism) — all PASS.
- `shafinMultitool/SceneGeneratorModule/Services/
  SceneCreateJobRequestBuilder.swift`: client builder constrained by
  construction to the same allowlist — no parameter exists for media
  or personal data; computes lowercase-hex SHA-256 over canonical
  JSON. One real defect caught by the narrow suite: the constraints
  guard compared against the passed value instead of the static cap
  (fixed; `1...Self.maximumScenes`).
- `shafinMultitoolTests/SceneCreateJobRequestBuilderTests.swift`:
  6/6 PASS on permitted iPhone 17e
  (`/private/tmp/m12004-tests.xcresult`).

## Boundaries

Reference validator + builder only; the deployed backend must enforce
the identical gate (M12-008 owns the server-side proof). No network
code, no credentials, no host selection in this task.
