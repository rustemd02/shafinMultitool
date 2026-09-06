# backend-decision-v1 — M12-001 locked backend boundary

Status: **locked decision (v1). No backend provider is integrated; every
remote seam defaults to off and the local path owns the behavior.**

## Decision matrix (locked)

| Capability | Decision | Enforcement |
|---|---|---|
| Live Camera (Coach advice, detection, tracking) | `LOCAL_ONLY` | `AnalysisPipeline` + on-device Vision/CoreML; no network call exists on the frame path |
| Scene Generator (parse/plan/commit) | `BACKEND_REQUIRED` with local structural fallback | `SceneParserService.remoteOffloadEnabled` defaults `false`; `RemoteScenePlanProvider` has no production implementation; local `ruleBasedParse` owns the result |
| Deep Review (second-pass critique) | `POST_1_0` | no Deep Review surface ships; `SceneBundleContracts` marks it planned |
| Camera model delivery | `LOCAL_ONLY` bundled | `CameraModelRegistry.approved` is nil until M4-016 conversion lands; no download/hot-swap path exists |
| Telemetry / quality feedback | `OPTIONAL_REMOTE` only under approved policy | no remote telemetry call exists in the app target; benchmark harnesses are explicit lanes |

## Kill-switch and auth posture

No remote kill-switch is required because no remote capability is live.
When the M5-025 generation client lands, it must carry App Attest auth,
idempotency keys, timeouts, and a server-driven kill-switch response —
tracked there, not here.

## Verification

Grep-verified on the locked commit: `RemoteScenePlanProvider` has zero
production implementations; `remoteOffloadEnabled` defaults false with no
production caller enabling it; no `URLSession` POST to a backend exists on
any production advice/generation path.
