# CAM-009 — deterministic KEEP restoration

Date: 2026-09-22. Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (working tree intentionally dirty; no commit, reset, stash, or cleanup performed).

## Decision and scope

CAM-009 is complete for the bounded current-diff review. The fix keeps one shared replay/presentation/export KEEP owner, but removes the out-of-scope replay-only family classifier, manual replay confidence floor, and `additionalRecognizedFamily` bypass. The shared owner now requires an eligible `.good` or positive `.mixed` verdict, no non-KEEP correction, and positive evidence where required; the replay presentation selector additionally requires `structuredDecision.isAvailable` before projecting that shared KEEP, so frame identity, confidence, and explainable-content availability remain mandatory. It does not reopen `.needsFix` as `.good` or make an unavailable structured path available. Existing low-key/object/cinematic/numeric preservation owners and ca090/ca232 false-KEEP vetoes remain the only documented family exceptions.

The partial/unavailable boundary remains fail-closed: a measured technical signal without positive confirmation still withholds a generic positive presentation. No new `frameAspectRatio`/family thresholds or manual floors were added; CAM-010 lighting mapping and model-quality claims remain out of scope. Historical perceptual replay discrepancies are recorded as diagnostic evidence for ML-006/010, not as runtime/safety acceptance failures.

The already accepted `CameraCoachClosedLoopTests` fixture change is retained: `Self.supportedCaptureLuma` is passed through the existing `makeFrame` calls in `exerciseProductionEpisode`. That is an exact-contract measured scene setup, not a production gate or a changed KEEP assertion. No additional fixture/test edits were made in this slice.

## Touched production symbols

- `SemanticEvalCandidateOutput.shouldPreserveKeepEvidence(...)`: shared verdict/non-KEEP/positive-evidence gate, documented family owners, and false-KEEP veto.
- Existing `shouldPreserveLowKeyMoodKeepCurrentSetup`, `shouldPreserveReadableObjectInsertKeepCurrentSetup`, `shouldPreserveCinematicEstablishingKeepCurrentSetup`, `shouldPreserveNumericWideGoodEstablishingFrame`, and `shouldSuppressFalseKeepCurrentSetup`: retained; no fixture-ID branches or new thresholds.
- `AnalysisPipeline.shouldPreserveReplayKeep(...)`, `selectPreparedPauseReplayPresentation(...)`, and `makePauseCritiquePresentation(...)`: one shared accepted-policy projection with conservative replay strength handling; the selector requires `structuredDecision.isAvailable` before projection and retains the existing partial/unavailable boundary.
- `shouldPreserveGoodFrameSemanticActions(...)`: mixed-only exception; `.needsFix` is no longer eligible for a good-frame reopening.

## Verification

All commands were serial, used the existing simulator `1F680A42-CEB3-43E8-9CED-52F874962A62`, DerivedData `/private/tmp/setos-cam001/dd`, and `-collect-test-diagnostics never`.

Focused runtime/safety command:

```text
xcodebuild -project shafinMultitool.xcodeproj -scheme shafinMultitool -sdk iphonesimulator -destination id=1F680A42-CEB3-43E8-9CED-52F874962A62 -derivedDataPath /private/tmp/setos-cam001/dd -parallel-testing-enabled NO -collect-test-diagnostics never \
  "-only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testPauseStylePreservationCannotReopenGoodWithoutCurrentTechnicalMeasurement" \
  "-only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplaySuppressesFalseKeepForBadTechnicalFrames" \
  "-only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPreservesLowKeyMoodKeepDespiteTechnicalFuture" \
  "-only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayPreservesReadableObjectInsertDespiteWindowHotspot" \
  "-only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testStillImageReplayDoesNotOvercorrectCinematicGoodObjectInsertFrames" \
  "-only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithExplicitStrengthUsesHighConfidenceFloor" \
  "-only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testGoodPauseVerdictWithoutStrengthKeepsConservativeConfidence" \
  "-only-testing:shafinMultitoolTests/CameraCoachClosedLoopTests/testFreshReplanningPreservesEpisodeThroughVerification" test
```

Result: **8 tests, 0 failures**. This covers the mandatory structured-availability gate, partial/unavailable boundary, false-KEEP controls (including ca090/ca232), retained low-key/object KEEP owners, confidence guards, and closed-loop replanning.

Diagnostic extension (the same invocation with these three historical selectors):

- `AnalysisPipelinePresentationTests/testStillImageReplayPreservesCinematicEstablishingDespiteTechnicalFuture`
- `AnalysisPipelinePresentationTests/testStillImageReplayPreservesNarrativeEstablishingFramesWithKeepCurrentSetup`
- `AnalysisPipelinePresentationTests/testStillImageReplayPromotesWideUnknownGoodEstablishingConfidence`

Result: **11 tests, 8 assertion failures in 3 historical methods**. The failures are preserved diagnostic evidence after removing the out-of-scope replay heuristics: `ca_img_127` loses the cinematic KEEP projection; the narrative set has no KEEP/confidence `0.0` for `ca_img_125`, no KEEP/confidence `0.55` for `ca_img_127`, and confidence `0.55` for `ca_img_132`; the wide `ca_img_010` case has no KEEP and confidence `0.7408873025398988`. These are routed to ML-006/010 and are not claimed as runtime/safety regressions or CAM-010 results.

`testStillImageReplaySuppressesPreservationForReadableSyntheticSmallSubject` was not included because its required external `190.jpg` is absent and unauthenticated. No file was created, downloaded, skipped in production, or used to claim evidence for that case. The full historical perceptual suite was not run; no model-quality or CAM-010 conclusion is implied.

## Evidence snapshot

Captured after the final focused run:

| File | SHA-256 | mtime (Europe/Moscow) |
|---|---|---|
| `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift` | `2d052d6016727688bc31787f0511d438a093e83623987728e28ecce389f0cfe6` | `2026-09-22T17:38:49+0300` |
| `shafinMultitoolTests/CameraCoachClosedLoopTests.swift` | `5a9b8ad932fec3cb03b769c9fabf5fc5c8116810bf83e7771e171f6e349583a0` | `2026-09-22T16:20:17+0300` |
| `docs/implementation/APP_STORE_RELEASE_TRACKER.md` | `231f34ed2bc68a147fc239effce8b2a853db274e752fd3f3f4e46bd0198401b1` | `2026-09-22T17:40:48+0300` |

`git diff --check` passed for the owned production, authorized fixture, tracker, and receipt files. Final receipt SHA-256 is reported in the handoff because editing this table changes the receipt bytes. Remaining work is outside CAM-009: authenticated legacy fixture restoration (including `190.jpg`), model/data evaluation, and CAM-010 lighting integration.
