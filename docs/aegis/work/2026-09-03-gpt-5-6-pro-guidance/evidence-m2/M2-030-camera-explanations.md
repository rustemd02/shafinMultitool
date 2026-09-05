# M2-030 Camera evidence-linked explanations

- Date: 2026-09-05
- Branch: `codex/set-os-m2-030`
- Scope: deterministic RU/EN Camera Coach explanations from typed action/evidence links only.

## Evidence chain

- `RecommendationAction` + `CritiqueReport` now produce a typed same-frame `CameraLinkedEvidenceProjection`; only one known linked issue with non-neural, non-summary structured evidence can reach the live hint.
- Camera overlay and live Decision Trace consume that projection for short issue-specific RU/EN catalog copy. Opaque IDs, free-form supporting/action text, technical-only hints without provenance, stale-frame projections, and unknown links hide Why/evidence.
- Decision Trace no longer fabricates evidence rows from IDs. Pause rows currently lack a typed same-frame provenance handoff, so pause Why/evidence and linked-evidence metadata remain empty until M2-031 owns that contract; deterministic action labels remain available.
- Explicit `LiveHintPresentation.semanticActionType` wins over coarse `ActionTypeV1` in Decision Trace action rows, including object-vs-frame mismatches. Raw `critique.assumptions` are omitted rather than rendered.
- KEEP and the planner fail-closed WAIT / SELECT_SUBJECT / ABSTAIN paths retain no corrective explanation/action in the Camera overlay.

## Verification

Focused simulator commands (serial, iPhone 17e / iOS 26.5):

```text
xcodebuild test ... -only-testing:shafinMultitoolTests/CameraOverlayUXPresentationTests ... -derivedDataPath /private/tmp/setos-m2-030-explanations-dd-correction -resultBundlePath /private/tmp/setos-m2-030-explanations-camera-run4.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild test ... -only-testing:shafinMultitoolTests/DecisionTracePresentationTests ... -derivedDataPath /private/tmp/setos-m2-030-explanations-dd-correction -resultBundlePath /private/tmp/setos-m2-030-explanations-trace-run7.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild test ... -only-testing:shafinMultitoolTests/CameraAnalysisDomainContractsTests ... -derivedDataPath /private/tmp/setos-m2-030-explanations-dd-correction -resultBundlePath /private/tmp/setos-m2-030-explanations-domain-run6.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild test ... -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testLiveStructuredPathPublishesMatchingHintAndExpandedCritique ... -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testTextOnlyLiveRefreshKeepsStableIdentityButUpdatesCurrentPayload ... -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testLivePositiveConfirmationWaitsForGroundedSubjectEvidence ... -only-testing:shafinMultitoolTests/AnalysisPipelinePresentationTests/testCriticalHorizonLegacyFallbackStillPublishesLiveHint ... -derivedDataPath /private/tmp/setos-m2-030-explanations-dd-correction -resultBundlePath /private/tmp/setos-m2-030-explanations-pipeline-run8.xcresult CODE_SIGNING_ALLOWED=NO
```

- Results: **TEST SUCCEEDED**, 50 tests, 0 failures (25 CameraOverlayUXPresentationTests + 5 DecisionTracePresentationTests + 16 CameraAnalysisDomainContractsTests + 4 AnalysisPipelinePresentationTests).
- Result bundles: `/private/tmp/setos-m2-030-explanations-camera-run4.xcresult`, `/private/tmp/setos-m2-030-explanations-trace-run7.xcresult`, `/private/tmp/setos-m2-030-explanations-domain-run6.xcresult`, `/private/tmp/setos-m2-030-explanations-pipeline-run8.xcresult`
- One combined retry attempt was terminated by simulator process `signal kill` before XCTest bootstrap (0 tests); split clean runs above are the final evidence.
- `git diff --check`: passed.
- `python3 -m json.tool shafinMultitool/Resources/Localizable.xcstrings`: passed.
- Forbidden-style grep for blur/material/shadow/gradient in changed production/catalog files: no matches.
- Device boundary: iPhone 17e Simulator, iOS 26.5 only; no physical device or iPhone 17 Pro run.

Known boundary: M2-031 pause/resume ownership remains separate.
