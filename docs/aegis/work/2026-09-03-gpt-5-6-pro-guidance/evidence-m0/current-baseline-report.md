# M0-014 Current-State Baseline (replaces stale HEAD/file-count assumptions)

Source: M0-001…M0-013 receipts in this directory. Historical claims kept as historical only.

## Checkout truth
- Branch `store` @ `c61e988886499c84c9ff9ec760f9ace5759db001`, upstream in sync, no active Git op, 1 untouched stash.
- Dirty: ~75 modified (tracked) + ~29 untracked-new paths; 0 `unknown` (104/104 classified, M0-003).
- Handoff == working tree: 253/253 snapshot files byte-identical (M0-004). The dirty state IS the baseline; git-modified files are owner/working state, not drift.

## What exists (source-backed)
- Camera capture/analysis/presentation, Library (VIPER + SET production view), Generator (parser/pipeline/llama path + workspace), AR container/anchors/teardown, Storyboard tray/editor/trace, recording (serialized recorder, adapters, artifact store, controller), CommercialShell single-active-route + awaited teardown (confirmed M0-008), SET OS v2.6 DesignSystem + production views, RU/EN xcstrings, 5 OFL fonts, privacy manifest.

## Test-contract-only (not freshly executed)
- 50 unit files / 811 methods; 6 UI files / 39 methods; release/provenance shell tests; benchmark python tests.

## Fixture/mock-only
- DEBUG gallery + camera/library/decision-trace fixtures; SETCameraFrame.png; DeviceBenchmark packs; in-memory providers.

## Historical (stale, not current claims)
- CC-007B 30/30 + 6/6 (functional only; landscape captures invalidated); CC-007C blocked_by_host_capture; 2026-08-25 xcresults in build/Logs; all prior pass rates.

## Simulator-only / device-only / signed-only
- Simulator: all saved test results. Device: none current. Signed/ASC/TestFlight: none (MISSING).

## Unknown / open before source edits
- Orientation-during-transition policy; NavigationOwner mapping; Legacy-naming vs deletion; History product intent; DEBUG-vs-UITesting precedence; generator teardown retry split; backup/protection flags; worldMap:nil dual meaning; dangling-reference GC; absent-vs-zero defaults; legacy filename sanitization.

## Blocking defects confirmed at baseline
- Deployment targets disagree (project 16.2 / app 17.0 / tests 17.2 / UI 17.0; Podfile 14.0) — BL-P1-06 live.
- No schema version anywhere; no durable pending journal (BL-P0-12/16 evidence); deleteMap path traversal; cross-store promotion non-transactional.
- Toolchain floor OK: Xcode 26.6 + iPhoneOS26.5 SDK + iOS 26.5 sim (meets 2026-09-03 Apple upload floor).

## Deviations recorded (not scope cuts)
- D1: evidence under `evidence-m0/` (durable) instead of gitignored `build/release-evidence/`.
- D2: `*.index.json` absent → bundle `===== FILE:` markers used as handoff index.
- D3: fixture-count and orientation-capture defects from plan confirmed live, not fixed in M0 (read-only phase).
