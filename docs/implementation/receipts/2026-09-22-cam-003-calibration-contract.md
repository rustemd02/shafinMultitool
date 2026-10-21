# CAM-003 — typed production calibration artifact contract and fail-closed loading

Date: 2026-09-22. Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`).
The working tree was already dirty (pre-existing CAM-009 diff in
`AnalysisPipeline.swift` + `AnalysisPipelinePresentationTests.swift` +
`CameraCloudPauseIntegrationTests.swift` + `CameraCoachClosedLoopTests.swift`,
plus docs/admission/ and other untracked files). No commit, push, PR, reset,
stash, or foreign file was touched; no constant was substituted for an
artifact; docs/admission/ untouched; the canonical tracker row was left for
the orchestrator.

## Task

CAM-003 (tracker §9): typed production calibration artifact contract +
fail-closed loading for the `CameraConfidenceCalibrator` path. Check/Done
when: missing/invalid hash → unavailable; valid fixture → deterministic
calibrated outputs. Aligned with ML-002 H7 (`calibration_artifact`,
`ml/camera_coach/contracts/camera_production_heads_v1.md`) and built on top
of DATA-001/ML-002 contracts.

## Changes (files and symbols)

1. `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraConfidenceCalibrator.swift`
   (the owned calibrator file; additive only — existing consumers unchanged):
   - `CameraConfidenceCalibrator` gained additive `Equatable` conformance
     (schema compare; no behavior change).
   - NEW `CameraProductionCalibrationHeadV1` — the six ML-002 v1 production
     tensor heads exactly as named in the ML-002 machine-readable block
     (`good_frame_probability`, `issue_logits`, `action_utility_logits`,
     `continuous_target_deltas`, `risk_probability`,
     `abstention_probability`). `scene_class_logits`,
     `subjectness_roi_agreement_logits`, `embedding` are not representable.
   - NEW `CameraCalibrationShowSilentThresholdsV1` — ML-002 H7 show/silent
     thresholds for one covered head; valid only when finite, in [0, 1], and
     `silent <= show`. No runtime consumer yet (CAM-012 owns wiring); the
     artifact carries them so no future consumer can invent thresholds
     outside the admitted artifact.
   - NEW `CameraProductionCalibrationArtifactV1` — typed `Codable`/`Equatable`/
     `Sendable` envelope: `schemaVersion` (fixed `"1"`), `artifactVersion`
     (>= 1), `coveredHeads` (non-empty, duplicate-free subset of the six
     heads), `payload` (the EXISTING `CameraActionCalibrationSchemaV1`
     "cal1" curve schema — deliberately no parallel payload format),
     `payloadSHA256` (SHA-256 lowercase hex over canonical payload bytes =
     decoded payload re-encoded with `JSONEncoder` `.sortedKeys`; envelope
     whitespace/key order cannot affect verification), `thresholds` (per
     covered head id). Strict decode rejects a foreign `schemaVersion`.
   - NEW `CameraCalibrationArtifactFailure` — typed fail-closed reasons:
     `missingResource`, `unreadableResource`, `emptyData`, `malformedJSON`,
     `unsupportedSchemaVersion(String)`, `unsupportedArtifactVersion(Int)`,
     `emptyCoverage`, `duplicateCoverage`, `payloadHashMalformed`,
     `payloadHashMismatch(expected:actual:)`, `emptyPayload`,
     `invalidCurve(actionID:)`, `missingProducerProvenance(actionID:)`,
     `invalidThreshold(headID:)`, `thresholdForUncoveredHead(headID:)`.
   - NEW `CameraCalibrationArtifactLoadResult` / `CameraCalibrationArtifactLoadOutcome`
     — only `.loaded` exposes a calibrator (`outcome.calibrator` is `nil` on
     every failure path by construction); the loaded result carries a
     deterministic `reference` `"camera_calibration_artifact.v1:<payloadSHA256>"`
     binding the runtime calibrator to the verified payload digest.
   - NEW `CameraCalibrationArtifact.load(from:)` / `.loadBundledResource(named:extension:in:)`
     — the single fail-closed entry points. Validation order: coverage →
     integrity (hash) → payload curve validity + producer provenance →
     thresholds. Provenance rule mirrors the existing `calibratedEvidence`
     handoff: a curve without `inputVersion` cannot be admitted inside a
     production artifact. No default table, no substitution, no crash.
   - The production runtime default is unchanged and remains
     `CameraConfidenceCalibrator.unavailable` (empty schema); no artifact
     resource ships in this build (ML-002 GAP-4; ML-007/ML-015/CAM-011 own
     the future admitted artifact). Nothing in `AnalysisPipeline.swift` or
     `HybridFusionService.swift` was modified; both keep their current
     fail-closed behavior (`calibration_unavailable`).

2. `shafinMultitoolTests/CameraConfidenceCalibratorTests.swift`
   (the owned focused test file): +7 methods (13 → 20) with fixture helpers
   that pin the canonical-hash rule independently via CryptoKit
   (`import CryptoKit` added).

## Contract

- Envelope: `camera_calibration_artifact` schema `1`; fields listed above.
- Integrity: `payloadSHA256` = SHA-256 over the canonical payload bytes
  (`JSONEncoder` `.sortedKeys` re-encoding of the decoded payload); ML-007
  producers must compute the digest over the same canonical form.
- Alignment with ML-002 H7: per-head calibration mapping (isotonic-style
  piecewise-linear curves + show/silent thresholds) over covered production
  heads; head ids are exactly the ML-002 production set; payload curves are
  keyed by the existing consumer id space (action ids for
  `action_utility_logits`-family consumers in `AnalysisPipeline`, head ids
  for `HybridFusionService`) and remain app-verifiable (monotonic, in-domain,
  versioned, provenance-bound).
- Fail-closed: every invalid state maps to `CameraConfidenceCalibrator.unavailable`
  semantics through `outcome.calibrator == nil`; callers cannot fall back to
  defaults through this path.

## Validation commands and results

Focused batch only (no full suite), per the tracker protocol:

```bash
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /private/tmp/setos-cam003/dd \
  -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 \
  -collect-test-diagnostics never \
  -only-testing:shafinMultitoolTests/CameraConfidenceCalibratorTests test
```

Environment note (honesty record): the machine's Xcode was updated to
`Xcode 27.0 (27A266a)` / iOS SDK 27.0 since CAM-001/CAM-004 (recorded
Xcode 26.6 / SDK 26.5). The canonical `-workspace` lane now fails BEFORE any
compilation because the checked-in Pods project pins
`IPHONEOS_DEPLOYMENT_TARGET` 12.0/14.0 (SnapKit / Pods aggregate) while the
27.0 SDK supports 15.0–27.0.x. Resolved without changing any repository
file: the Pods targets were prebuilt once into the scratch derived-data path
with a command-line-only override

```bash
xcodebuild -workspace shafinMultitool.xcworkspace -scheme Pods-shafinMultitool \
  -sdk iphonesimulator -destination 'id=1F680A42-CEB3-43E8-9CED-52F874962A62' \
  -derivedDataPath /private/tmp/setos-cam003/dd \
  IPHONEOS_DEPLOYMENT_TARGET=15.0 build     # BUILD SUCCEEDED
```

and the focused test run then used the `-project` lane (same lane as
CAM-009's accepted 2026-09-22 receipt) against the prebuilt Pods framework,
so the app/test targets compile with their own real deployment target
(17.0). The override touched no tracked file and no product binary settings.
This toolchain change is itself a build-input change the owner should know
about (previous receipts record SDK 26.5); it does not alter CAM-003's
result.

Result (first run had 2 test-file compile errors — missing `payload:`
argument and a missing `try`; fixed in the same file, then re-run):

```text
Test Suite 'CameraConfidenceCalibratorTests' passed
Executed 20 tests, with 0 failures (0 unexpected) in 0.026 (0.037) seconds
** TEST SUCCEEDED **
```

New focused methods (all passed; existing 13 also passed — no test weakened,
no skip, zero-test invariant satisfied):

- `testArtifactLoadMissingDataAndMissingResourceAreUnavailable` — empty bytes
  → `.emptyData`; absent bundle resource → `.missingResource`; failure path
  exposes no calibrator.
- `testArtifactLoadRejectsMalformedAndIncompatibleSchemas` — non-JSON →
  `.malformedJSON`; `schemaVersion:"2"` → `.unsupportedSchemaVersion("2")`;
  `artifactVersion:0` → `.unsupportedArtifactVersion(0)`.
- `testArtifactCoverageMustBePresentAndUnique` — `[]` → `.emptyCoverage`;
  duplicate head → `.duplicateCoverage`.
- `testTamperedPayloadHashIsUnavailable` — one flipped knot under the
  original digest → `.payloadHashMismatch(expected:actual:)` with the exact
  recomputed digest, and no calibrator exposed; short hash →
  `.payloadHashMalformed`.
- `testInvalidOrProvenancelessPayloadEntriesAreUnavailable` — mismatched
  curve key, non-monotonic curve, version 0 → `.invalidCurve(actionID:)`;
  historical provenance-less curve → `.missingProducerProvenance(actionID:)`;
  empty payload → `.emptyPayload`.
- `testInvalidOrUncoveredThresholdsAreUnavailable` — `silent > show`,
  non-finite-range value → `.invalidThreshold(headID:)`; uncovered head and
  non-head key → `.thresholdForUncoveredHead(headID:)`.
- `testValidFixtureLoadsAndCalibratesDeterministically` — two loads are
  `Equatable`-identical with identical `camera_calibration_artifact.v1:<digest>`
  references; thresholds travel with the artifact; calibrated outputs across
  a 21-point grid are byte-identical between the two loads and equal the pure
  piecewise payload interpolation (0.25 → 0.335, 0.8 → 0.848 ± 1e-12);
  out-of-domain → `.outOfDomain`; unknown id → `.unavailable`;
  `calibratedEvidence` keeps the existing producer-provenance contract
  (`cal1:` reference for the matching `inputVersion`, `nil` otherwise).

## Limits / what this does NOT claim

- No production calibration artifact exists or is admitted (ML-002 GAP-4);
  the runtime default stays `.unavailable` and the closed-loop suite's
  `calibration_unavailable` fail-closed behavior is untouched.
- The loader is typed plumbing for ML-007/ML-015/CAM-011: it defines HOW an
  artifact may enter, not THAT one is valid. ECE/reliability evidence
  remains ML-007/ML-006 work; bundle admission remains ML-015/SEC-007.
- Thresholds are carried and validated but consumed by no runtime code yet
  (CAM-012).
- Environment drift: Xcode 27.0 / SDK 27.0 vs SDK 26.5 recorded by GOV-001;
  full-suite baseline (CAM-001) has not been re-run on the new toolchain and
  CAM-003 does not claim it.
- Scratch derived data lived only under `/private/tmp/setos-cam003/` and was
  removed after the run.
