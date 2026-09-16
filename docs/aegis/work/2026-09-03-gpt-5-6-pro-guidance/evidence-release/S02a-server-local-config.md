# S02a — server local config + operations packet (2026-09-13)

Package: S02a of `docs/aegis/plans/2026-09-13-setos-release-execution.md` §6.
Scope owner: external service `/Users/unterlantas/Documents/XCode/setos-backend`
(app repository remains the frozen contract owner).

## 1. Status

**needs_review** — local source/config/HTTP/deploy preparation is implemented
and verified live. Application to staging/production is **blocked_external**:
no hosting/account/egress authorization exists (section 5). S02b (physical
App Attest device roundtrip) is out of scope here and untouched.

No production authentication was bypassed, no mock attestation was used in a
deployed path, and no check was weakened for a PASS.

## 2. Files changed (sha256 — one-line reason)

External service `/Users/unterlantas/Documents/XCode/setos-backend`:

- `service.py` `8cb6fc79fa283d1056a673aa15de50ef38637bc0cd0df28243d6f4a943a0353a`
  — config-file/env resolution, canonical clarification validator, id/epoch
  binding, round-cap wiring, honest `/readyz`.
- `store.py` `763938fd3c1f47005c3d80e4d5b60b0b9dd5d01ea462119bf98def3d99ddf2ac`
  — durable clarification-round cap + stale-clarification rejection.
- `test_local_config.py` `6263652907dc7040ed8ad9b4aa07ca05ccec57d0a73ef833420396041e459263`
  — pins config precedence and fail-closed config parsing.
- `test_clarification_admission.py` `b7c8f4f7aaf77d1aa4977e23ba22c127375c9bc98298b3ab16bb5f4b84800fc8`
  — pins validator, binding, cap, restart durability.
- `config.example.json` `f1bc90ce79cb18f0bd0bcfbdd3eda026aab0a1ec3c7535bd36403733c3998111`
  — no-secret config template.
- `run-local.sh` `b20f047abdaef072a9ed95772e109fa0482d3cc89615037045d235343edda7ac`
  — reproducible local bring-up.
- `scripts/local_roundtrip.py` `44a320d6828847ae9a62658084bb7b286e931d7dd129993402d4e875fb89a28e`
  — real live-process HTTP roundtrip with test-only identity.
- `scripts/local_verify.sh` `fe35769f844835cc3cf53ff87e7ad4a0c3d230e64edd06c713e1b2b4a41710e9`
  — one-command from-scratch verification.
- `OPERATIONS.md` `2a31c1435d526c3e6f2ecb18cbd0a7ee2c561f90b857f1a1f516cebccac4728d`
  — operations packet (run/health/limits/retention/external deps/rollback).
- `README.md` `7d30336260cf94380c267ff1754e0f91595dc0996f350b13a5a90371b436e7f0`
  — run/config/health/limits docs; corrected stale "clarification not
  executed"/"not wired" statements.

App repository (allowed set only):

- `docs/implementation/backend-service-boundary-v1.md`
  `055b3a0436aca6379bbea6ff4d3bf87fdb9d25afb16a102607358b9e81c9ade7`
  — records that the external service now meets the clarification integration
  requirements.

No app Swift/camera, `docs/cameraanalysis/*.json`, `datasets/**` or `tools/**`
file was touched.

## 3. Commands, exit codes, actual output

Run from `/Users/unterlantas/Documents/XCode/setos-backend`:

1. `./scripts/local_verify.sh` → **exit 0**
   - stage 1 targeted backend suites: `Ran 57 tests ... OK` (includes the new
     `test_clarification_admission` 8 tests and `test_local_config` 12 tests),
     stage1 exit=0.
   - stage 2 app-repo contract suites (pytest):
     `55 passed, 34 subtests passed in 0.53s`, stage2 exit=0.
   - stage 3 live HTTP roundtrip, stage3 exit=0, `RESULT: PASS`.
2. Full backend discovery
   `PYTHONPATH=<app>/backend .venv/bin/python -m unittest discover -p 'test_*.py'`
   → `Ran 115 tests ... OK` (baseline before this package was 95).
3. `PYTHONPATH=<app>/backend .venv/bin/python -m unittest test_clarification_flow -v`
   → included in the green suites above (the S01 loop still passes unchanged).

Live HTTP evidence from the real subprocess (`scripts/local_roundtrip.py`,
127.0.0.1, seeded test-only identity):

```
GET  /healthz  -> 200 {"status":"local_foundation","authentication":"configured","provider":"disabled"}
GET  /readyz   -> 200 {"status":"ready"}
POST /v1/jobs (no bearer)                          -> 401 {"code":"unauthorized",...}
POST /v1/jobs (test identity)                      -> 201 status=pending
GET  /v1/jobs/{id}                                 -> awaiting_clarification clar_no_subject epoch 0
POST /v1/jobs/{id}/clarification-answer {answer:…} -> 400 invalid_request (legacy wrapper rejected)
POST /v1/jobs/{id}/clarification-answer (unwrapped)-> 200 status=pending
GET  /v1/jobs/{id}                                 -> 200 completed, actors=["МАРИНА"]
```

## 4. Verified live vs static

Live (real process, real socket, real store, real auth path):

- create → awaiting_clarification → unwrapped answer → completed;
- deny-by-default `401` without a token;
- legacy wrapped clarification body `400`;
- `/healthz` `200`, `/readyz` `200` when attestation is configured.

Static / in-process only (TestClient, unit tests):

- config precedence and fail-closed config parsing;
- canonical validator rejects missing field / oversized `free_text` and leaves
  the job unchanged;
- stale `epoch` and wrong `clarification_id` → `409`, job unchanged;
- round cap (`409 clarification_rounds_exhausted`) and its durability across an
  app restart;
- quota, retention, 60 s deadline, body-size, attestation-state behavior
  (pre-existing suites, re-run green).

Not device/provider evidence: the seeded identity is local scaffolding created
through `AttestationState`, and the provider is the deterministic local
baseline. Neither is a real App Attest nor a cloud provider qualification.

## 5. External owner steps (action → path/screen → expected result → rollback)

1. **Hosting/account/egress authorization.** Action: choose hosting
   account/region and authorize ingress+egress for the service.
   Path: hosting provider console → new service/account. Expected: a deploy
   target exists. Rollback: do nothing (service stays local; current state).
2. **Domain + TLS.** Action: register/point the API domain, provision TLS.
   Path: DNS + hosting TLS settings. Expected: HTTPS endpoint. Rollback:
   remove DNS record; no local change.
3. **Apple Developer App ID/environment.** Action: confirm the real
   `TEAMID.bundle.id` and provisioning used by App Attest.
   Path: Apple Developer portal → Identifiers/App Attest. Expected: server
   `--attest-app-id` matches the device RP hash. Rollback: leave
   `--attest-app-id` unset (routes stay 401).
4. **Secret store.** Action: choose the server-side secret manager for any
   future provider credential. Path: hosting secret manager. Expected: secrets
   never enter `config.example.json`, env files or the app bundle. Rollback: N/A.
5. **Provider account/model revision/quota agreement.** Action: bind a real
   provider revision matching `provider_name`/`provider_version`.
   Path: provider console. Expected: real generation behind the same job
   contract. Rollback: keep the deterministic local provider.
6. **Device App Attest qualification (S02b/Q04).** Action: run
   challenge/enroll/assert on real hardware. Path: physical device + staging
   endpoint. Expected: real attested roundtrip. Rollback: revoke the
   installation in the attest DB.

## 6. Honestly NOT done

- No staging/production deployment, DNS, TLS, or secret store exists — the
  service is hard-pinned to `127.0.0.1` and no one was asked to authorize
  infrastructure.
- No real App Attest device roundtrip (S02b/Q04); the live test uses a seeded
  test identity, which is explicitly not device evidence.
- No real neural provider: only the deterministic local baseline is attached;
  provider quality, cost reservation and provider-outage behavior against a
  real provider are unverified.
- Portable packaging is still open — the service still imports the app
  repository's validator through `PYTHONPATH`, so the two repositories must sit
  side by side. A deployable artifact/container is not produced.
- The clarification round cap marks the job's accepted-answer count inside the
  stored request JSON (server-side lifecycle metadata stripped before the
  provider); a dedicated column was not added to avoid a schema migration in a
  preparation package.
- Backup/restore was documented but not exercised end to end.
