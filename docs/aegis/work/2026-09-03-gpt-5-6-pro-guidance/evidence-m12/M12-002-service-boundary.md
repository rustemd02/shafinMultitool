# M12-002 — backend service boundary

Status: **closed on the current store**.

## Boundary document

`docs/implementation/backend-service-boundary-v1.md` locks the single-service
ownership (auth, validation, provider call, job state, quota, retention,
observability), the out-of-app-repo deployment rule, and the app-side
guarantees.

## Real finding closed in this task

The audit found a live remote path: `RemoteVLMVisualEvidenceProvider`
(env endpoint + Bearer key) reachable from production via
`VisualSemanticEvidenceProviderFactory.makeDefaultProvider()` when the
environment requests `remote`. The factory now gates the `remote` branch
behind `#if DEBUG` — Release builds can never construct it; the mock and
nil paths are unchanged. No credentials exist in the app target; the key
travels only via explicit environment injection in DEBUG evaluation.

## Verification

`VisualEvidenceProviderFactoryTests` 2/2 on permitted iPhone 17e
(`/private/tmp/m12-002-tests-r3.xcresult`).
