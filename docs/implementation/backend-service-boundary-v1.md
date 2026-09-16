# backend-service-boundary-v1 — M12-002 locked service boundary

Status: **locked boundary (v1). Local-only service preparation exists;
no backend is deployed and no live app endpoint is enabled. This document
remains the authority the service must satisfy before the M5-025 client
may point at it.**

## Single-service ownership

One backend service owns exactly: App Attest auth, request validation
(schema/model/provider versions, request hash, idempotency key, server
time), provider calls, job state (create/poll/clarify-answer/cancel),
quota, retention, and observability. No second service, proxy, or
client-side fallback may share these responsibilities.

## Repository and deployment

The service lives outside the app repository. The current local preparation
workspace is `/Users/unterlantas/Documents/XCode/setos-backend`; no Git or
remote repository has been initialized or published for it. D2 hosting,
domain, billing and deployment approval remain open. Deployment manifests
(environment, secrets management, rollout/rollback) belong with the service,
never in the app bundle.

### Local preparation — 2026-09-11 working tree

- One FastAPI/Uvicorn process, loopback only, SQLite transactional job
  persistence with installation-scoped create-key uniqueness. This is the
  §24.5 A1 local adapter, not production deployment or complete R07–R09.
- The app repository still owns the frozen request/job schemas and the
  request validator. The service imports the existing validator through an
  explicit local `PYTHONPATH`; portable deployment packaging is unresolved.
  No copied request schema or second admission implementation is introduced.
- Real protected requests are always denied until App Attest verification
  exists. Tests may supply synthetic identities only through in-process
  dependency overrides; there is no environment token or public bypass.
  Health/readiness distinguish a live local process from usable cloud AI.
- Only create/poll/cancel persistence is implemented in this preparation.
  Accepted-job quota is now enforced in the create transaction:10 per rolling
  3600 seconds and20 per rolling86400 seconds per installation. Existing
  owner-scoped jobs are the ledger; replay/conflict precedes quota, and
  cancellation does not refund acceptance. HTTP429 carries a fixed error and
  bounded Retry-After hint, not a slot reservation. The client surfaces a typed
  quota error without automatic retry. Fractional storage timestamps preserve
  boundary precision; wire server_time remains whole-second UTC.
  Local schema v2 separates a six-field response-metadata allowlist from raw
  screenplay/marked-object content. A pending job reaches `failed(timeout)` at
  60 seconds; timeout and cancellation purge the raw request. DELETE preserves
  an already-terminal outcome. Owner/key/hash metadata expires at 30 days from
  acceptance, after which polling returns404 and the old key is no longer
  remembered. Raw deletion does not refund the rolling accepted-job quota.
  Maintenance shares the jobs transaction on every store operation and runs at
  service startup and in one lifespan-owned background task. A maintenance
  failure closes admission. The known v1 migration is transactional; validation
  rejects unknown schemas instead of rebuilding them. Existing user databases
  have not been migrated or cleaned as part of this implementation.
  SQLite secure deletion is enabled on service connections; this is not a
  guarantee about SSD remnants, backups, provider copies, host downtime or
  production-scale sweep latency. Only synthetic local lifecycle evidence is
  admissible for this package, as recorded in the execution checkpoint.
  Provider execution, clarification, monetary reservation/accounting, production
  retention and operational qualification remain open. Store only synthetic
  development inputs until those gates are met; no production-data retention
  promise follows from these local records.
- Dependencies live only in the external `.venv`. The standard ASGI choice
  follows [FastAPI deployment guidance](https://fastapi.tiangolo.com/deployment/manually/).
  SQLite uses rollback journal, not WAL: the local 3.45.1 runtime falls in
  the version range discussed by the current [SQLite WAL-reset advisory](https://www.sqlite.org/wal.html).
  Single-host storage is a deliberate local ceiling, not an HA design.
- Verification/review status and exact commands are recorded in the canonical
  `EXECUTION_STATE.md` large-batch checkpoint; do not infer qualification
  merely from the workspace's existence.

## App Attest certificate implementation boundary — 2026-09-11

Implementation evidence: external `app_attest_certificates.py` is frozen with10/10 focused checks and26/26 existing service regression checks passing. Independent SPEC and QUALITY reviews passed within certificate-only scope. Exact hashes and protocol-source caveats: EXECUTION_STATE.md, App Attest credential-certificate package; thesis evidence `EV-SG-ATTEST-CERT-001`. The component is not wired to service admission.

The implemented local security component is credential-certificate validation, not
authentication admission. Its internal inputs are DER certificates, a nonce and
key hash computed/selected by trusted server logic, and server verification time.
It must validate the ordered chain to the bundled, fingerprint-pinned Apple App
Attestation Root CA; certificate validity and leaf key usage; a P-256 key; the
canonical nonce extension; and the X9.62 public-key hash. Chain validation belongs
to the pinned cryptography library, not a hand-written signature-only traversal.
The implementation and exact test/review status live in the execution checkpoint.

This component does **not** establish one-time challenge freshness, RP/App ID,
environment/aaguid, attestation counter, COSE/CBOR binding, receipt validity,
assertion signatures/replay counters, installation ownership or token issuance.
Those checks must compose before `require_installation` can authorize anything.
No certificate-only return value may be treated as a verified installation.
There is no HTTP admission bypass, simulator token or app-side credential change.

The public [Apple validation guide](https://developer.apple.com/documentation/devicecheck/attestation-object-validation-guide)
contains a historical certificate useful for chain-only checks, but its printed
nonce/hash example is internally inconsistent with the
[main validation protocol](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server).
Local calculations and the bounded fixture scope are recorded in the checkpoint.
The fixture is not proof of a complete valid attestation, current certificate
validity or interoperability with this app's Apple account/device. Use the
[official root distribution](https://www.apple.com/certificateauthority/private/),
never roots supplied by an HTTP caller.

## App Attest assertion and receipt boundary — 2026-09-11

External `app_attest_assertions.py` verifies a bounded CBOR assertion signature
against a trusted attested P-256 key, server-computed client-data hash, expected RP
hash and prior counter. It preserves the complete signed authenticator bytes and
returns their counter/flags. Its name and return type intentionally describe
signature verification, not authentication. It neither validates the complete
authenticator profile nor atomically consumes a challenge or persists a counter.
No service endpoint invokes it.

Verification:9 assertion plus10 certificate checks and26 existing service checks
passed. SPEC and QUALITY reviews passed after strengthening two existing negative
tests. Exact hashes and evidence: `EV-SG-ATTEST-ASSERTION-001` and the execution
checkpoint. Counter comparison here is not a substitute for atomic replay state.

The current Apple article and WWDC26 do not provide a consistent precise wire
profile for all new assertion extensions; older public captures also contain a
nonstandard AT flag. A future admission policy must be selected by trusted server
configuration, never an untrusted client OS string or a fallback after a failed
current-profile parse. Signed bytes must not be normalized before verification.
Public and synthetic signature checks do not qualify SET OS device interoperability.

Receipt verification is separate. A parent diagnostic verified the public Apple
receipt's CMS signature with OpenSSL3.6.2 and official Apple Root CA-G3 using
default purpose, without weakening trust settings. This is not a production
receipt validator: exact signer purpose, bounded ASN.1 fields, App ID, freshness,
key binding and operational/runtime packaging remain required. Apple field3 in
that fixture contains a certificate, not raw SPKI. Research and exact evidence
are recorded in EXECUTION_STATE.md under the assertion package.

## Historical app-side guarantees (verified on the locked commit)

These are the original M12-002 evidence, not a fresh working-tree audit.
Subsequent work added `SceneGenerationClient` as an implementation of the
existing provider seam, with endpoint/token admission and response binding;
that client remains separate from real App Attest and production composition.

- `RemoteScenePlanProvider` has zero production implementations.
- `SceneParserService.remoteOffloadEnabled` defaults `false`; no
  production caller enables it.
- No provider credentials, API keys, or tokens exist anywhere in the app
  target (grep-verified: no `sk-`, `Bearer `, or provider host literals on
  production paths).
- The M5-025 client requirements (App Attest, idempotency, timeout,
  validated JSON, kill-switch response) are specified against this
  boundary and remain unimplemented until the service exists.

## Clarification-answer admission contract — 2026-09-13

The repository-owned fail-closed admission now covers the clarification
answer, not only create-job: `backend/scene_request_limits.py` exposes
`validate_clarification_answer(payload)` validating against the frozen
`ClarificationAnswer` component of `openapi-scene-v1.yaml` (required
`clarification_id`/`request_id`/`epoch`, `additionalProperties: false`,
`free_text` ≤ 160 characters) plus one semantic rule the JSON schema cannot
express — an answer carrying neither `selected_option_id` nor `free_text` is
rejected, because it would re-queue the job with no new information and loop
the clarification epoch. Never raises; fails closed when the schema document
or its dependencies are unavailable, matching create-job discipline.

Integration requirements for the external service (outside this repository):
call `validate_clarification_answer` on the decoded body before
`store.answer_clarification`, and keep a server-side cap on clarification
rounds per job (an accepted answer moves `awaiting_clarification → pending`
and re-runs the provider, so an uncapped round count is uncapped provider
spend; the iOS client bounds itself to one round, which is a client courtesy,
not a server control). The client wire shape is pinned test-side:
`SceneGenerationClientTests` asserts the encoded answer contains exactly the
frozen schema keys and omits — never null-encodes — unset option/free-text
fields.

### Implemented in the external service — 2026-09-13 (S02a)

The external `/Users/unterlantas/Documents/XCode/setos-backend` service now
meets both integration requirements above, without changing the frozen
contract or the app-side producer:

- `service.py` imports `validate_clarification_answer` from this repository's
  `backend/scene_request_limits.py` through the explicit local `PYTHONPATH` and
  runs it before touching the store; a missing validator or a rejected body is
  a fail-closed `400` and never changes the job. The legacy `{"answer": {...}}`
  wrapper stays rejected.
- The answer is additionally bound to the clarification the server issued:
  a mismatched `clarification_id` or `epoch` is `409 stale_clarification`
  before any mutation (the `409` path the OpenAPI document already declares).
- Accepted clarification rounds per job are capped server-side
  (`--clarification-round-cap`, default 2, range 1–10); the over-cap answer is
  `409 clarification_rounds_exhausted` and does not mutate the job. The count
  is folded into the stored request so it survives a crash/restart, and is
  stripped before the provider sees the request.

Server-side evidence: `test_clarification_admission.py` plus the live
`scripts/local_roundtrip.py` (real process, test-only seeded identity).


## Verification

Original grep audit: locked commit, M12-001 evidence. Current local preparation
and client evidence: canonical execution checkpoint and service README/tests.
This boundary remains the gate for future backend integration.
