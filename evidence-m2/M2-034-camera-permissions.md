# M2-034 Camera permission UI receipt

Date: 2026-09-05
Branch: `codex/set-os-m2-034`
Simulator: iPhone 17e, iOS 26.5, `1F680A42-CEB3-43E8-9CED-52F874962A62`
Physical device / iPhone 17 Pro: not used

## Change

- `CameraCoachEntryFlowModel` now fences every async snapshot/request commit
  with cancellation and a monotonic operation generation.
- Foreground rechecks are accepted only from `.blocked` (or an explicit
  ready-state caller); lifecycle callbacks cannot replace intro,
  permission-context, requesting, or initial resolving.
- Existing Camera Coach view, PermissionClient owner, catalog values, Settings
  URL, accessibility IDs, and DEBUG launch fixtures were reused unchanged.
- Focused model coverage now includes intro/recheck gating, canceled resolve
  and request callbacks, plus RU+EN visible/accessibility catalog coverage.

## Verification

- `CameraCoachEntryFlowModelTests`: 15/15 PASS.
- CommercialShell lifecycle/composition plus model integration: 33/33 PASS
  (`/private/tmp/m2-034-integration-r1.xcresult`).
- Entry model + presentation run: 24/25 PASS
  (`/private/tmp/m2-034-unit-final.xcresult`). The one failure is the existing
  `testEntryCommandsUseTheSharedCommandLabelOwner` assertion: its source slice
  spans the unrelated `SETPauseReview` declaration and sees `uiBodyFont`.
- Existing deterministic Camera Coach UI fixtures: 8/9 PASS
  (`/private/tmp/m2-034-ui-r2.xcresult`). The authorized-return test reaches
  the shell and pause IDs but cannot reach live-seeking because its DEBUG root
  intentionally injects `CameraManager(configuration: .failure(.noWideCamera))`.
- `git diff --check`: PASS. Python JSON parsing and Xcode `CompileXCStrings`
  passed for both String Catalogs. Targeted forbidden-style grep in the Entry
  view: no matches. DEBUG fixture state cases remain compile-time guarded.

Boundaries: no Camera overlay, route, AR, recording, Generator, thesis, or
execution-state files changed. Final commit hash is reported in the handoff.
