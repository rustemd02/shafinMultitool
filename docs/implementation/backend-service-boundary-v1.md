# backend-service-boundary-v1 — M12-002 locked service boundary

Status: **locked boundary (v1). No backend service is deployed; no provider
credentials exist in the app. This document is the authority the future
service must satisfy before the M5-025 client may point at it.**

## Single-service ownership

One backend service owns exactly: App Attest auth, request validation
(schema/model/provider versions, request hash, idempotency key, server
time), provider calls, job state (create/poll/clarify-answer/cancel),
quota, retention, and observability. No second service, proxy, or
client-side fallback may share these responsibilities.

## Repository and deployment

The service lives outside the app repository (separate service repo or an
external managed service — the choice is recorded here when made; until
then the decision is "no backend"). Deployment manifests (environment,
secrets management, rollout/rollback) live with the service, never in the
app bundle.

## App-side guarantees (verified on the locked commit)

- `RemoteScenePlanProvider` has zero production implementations.
- `SceneParserService.remoteOffloadEnabled` defaults `false`; no
  production caller enables it.
- No provider credentials, API keys, or tokens exist anywhere in the app
  target (grep-verified: no `sk-`, `Bearer `, or provider host literals on
  production paths).
- The M5-025 client requirements (App Attest, idempotency, timeout,
  validated JSON, kill-switch response) are specified against this
  boundary and remain unimplemented until the service exists.

## Verification

Grep audit on the locked commit (see M12-001 evidence); this document is
the merge gate for any future backend integration PR.
