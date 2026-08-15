# Camera Coach release evidence

## Current orchestration evidence

- Sol Advisor `get_setup_status`: `ready` on 15 August 2026.
- Sol Advisor `validate_configuration`: `valid: true`.
- Codex project ID: `ac45e24e-80ce-4fad-803a-731a0a84ee27`; `isGitRepository: true`.
- Luna app-task toolchain exposed: list/create/wait/read/send tools; host advertises `gpt-5.6-luna` with `max`.
- Saved project profile: orchestrator inherits parent; app-task lane is enabled at `gpt-5.6-luna` / `max`; fallback policy is fail-closed.
- Main branch after the accepted reliability batch: `store` at `b76f217`; one untracked Core ML research draft remains outside accepted evidence pending recommendation reconciliation.

## Accepted product and release evidence

- Product/research baseline: `docs/app-store-product-plan.md`, CC-000 accepted.
- Release inventory and isolation: CC-001/CC-002 accepted; Release excludes GGUF, DeviceBenchmark and development `Resources/Models` payloads.
- Privacy and permissions inventory: `docs/implementation/audits/privacy-permissions-inventory.md`, CC-003 accepted.
- Test topology and runtime entry: CC-005/CC-006 accepted; true UI-test target and Camera Coach default route remain future gated work.
- Privacy manifest and bundle gate: CC-011A/CC-011B accepted.
- Provenance gate: worker `4802b9c`, accepted `7891fec`; full clean-main gate passed with Debug/Release builds, 2 privacy manifests, 2 offline provenance validators, 5 material contributors, 5 known blockers and 6/6 contamination fixtures. Release size was 71,968 KiB.
- Dependency cleanup: ARVideoKit removed; SnapKit 5.7.1 privacy bundle retained and validated.
- llama record: worker `ac97f6e`, accepted `d7fff1b`; 15 fixtures and offline/optional-upstream checks passed. Traceability is proven, clean rebuild and legal approval are not.
- Circle record: worker `81f50c2`, accepted `c8601ba`; 10 fixtures and real offline validator passed. Repository correlation is proven, source-to-export causality and rights are not.

## Accepted camera foundation evidence

- CC-009 camera/session ownership audit accepted.
- CC-010A capture lifecycle: accepted `e0bd423`; generic build and 7/7 focused simulator tests passed.
- CC-010B scheduler/pipeline release: accepted `79f7d1d`; generic build and 23/23 focused simulator tests passed.
- CC-010C-A serialized recorder core: worker `d1277ca`, accepted `9b41adf`; canonical generic build-for-testing and 29/29 `SerializedMediaRecorderTests` passed on iPhone 17 Pro.
- CC-003A permission foundation: worker `322faeb`, accepted `f246ada`; exact three-file scope, integrated generic build and 10/10 `PermissionFoundationTests` passed.
- CC-010B1 latest-frame evidence: worker `b38ef12`, accepted `8b20380`; correction worker `772fe33`, accepted `ee019f0`. Integrated generic build and 12/12 focused release/store tests passed.
- CC-010A2 atomic motion snapshot: worker `9fb974e`, accepted `caef74b`; correction worker `f80e1a3`, accepted `b76f217`. Integrated generic build and 4/4 `MotionGateTests` passed, including concurrent tuple coherence.
- Recorder evidence covers an isolated policy-neutral core only; production camera wiring, Photos export and retention/background behavior are not claimed.

## Proposed but not accepted

- CC-008: `docs/implementation/ux/camera-coach-state-spec.md` is proposed for owner acceptance.
- CC-007A/CC-008A: exact shell/live-surface packets exist but source implementation is gated by CC-008.
- CC-013B2: recommended minimal RC excludes DETR, NIMA and compact neural fusion while retaining Apple Vision/saliency and deterministic critique; implementation is gated by owner acceptance.

These records support continued execution. They do not prove App Store readiness, legal redistribution rights, physical-device behavior, external beta quality or completion of the full active goal.
