# M5-025 — production generation client evidence

Status: CLOSED on the current store.

## Delivered

- `shafinMultitool/SceneGeneratorModule/Services/SceneGenerationClient.swift`:
  the single typed client for the first-party Scene backend. Implements
  the existing `RemoteScenePlanProvider` seam (create → bounded poll →
  structural bridge to `ScenePlanIR`); clarification/failure surface
  as nil so the coordinator keeps the honest local result — no fake
  plan is ever synthesized. Hard boundaries: auth is an injected
  short-lived token (App Attest wiring is M12-005), baseURL defaults
  to the M12-003 placeholder host, transport is injected for
  URLProtocol tests, every decoded status passes `SceneJobValidation`
  (kill-switch aborts immediately, cancellation throws), request
  bodies come from the M12-004 allowlist builder, provider called at
  most once per accepted job (server idempotency, M12-007).
- `shafinMultitoolTests/SceneGenerationClientTests.swift`: 8/8 PASS
  on permitted iPhone 17e (`/private/tmp/m5025-tests.xcresult`) —
  idempotency-key + Bearer headers on create, complete/clarification/
  failure terminal outcomes, malformed payload rejection, 410
  kill-switch abort, DELETE cancel, end-to-end remote-plan bridge
  (`remote_plan_used`, non-empty beats).

## Composition note

The client is implemented and tested but NOT wired into
`SceneParserService.configureRemoteOffload` (the seam defaults off
per M12-001/M12-002): wiring it to a live backend requires a
deployed service, App Attest tokens (M12-005), and a non-placeholder
host from deployment config — all external. The coordinator offload
path (`parseAsync` → `generateRemotePlan`) is unchanged and keeps
returning the local result until that wiring lands with its own
evidence.

## Boundaries

No provider selected, no host live, no credentials in the app. This
unblocks M5-026 (validate the client's outputs) without authorizing
a fake backend or a silent local-behavior change.
