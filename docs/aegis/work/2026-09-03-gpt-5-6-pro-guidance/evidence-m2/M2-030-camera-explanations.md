# M2-030 Camera evidence-linked explanations

- Date: 2026-09-05
- Branch: `codex/set-os-m2-030`
- Scope: deterministic RU/EN Camera Coach explanations from typed action/evidence links only.

## Evidence chain

- Live Camera overlay gates Why on a usable linked issue ID or typed technical observation plus a safe evidence payload; it emits only `set.camera.explanation` catalog copy.
- Decision Trace projects pause issue/strength labels and planned action labels from existing catalog keys. Live trace IDs and linked issue IDs remain metadata; raw hint, verdict, rationale, and expected-outcome text are not rendered.
- `RecommendationAction`/`CritiqueReport` validation accepts only linked issues with non-empty non-neural structured evidence; missing/unlinked evidence returns no explanation.
- KEEP and the planner fail-closed WAIT / SELECT_SUBJECT / ABSTAIN paths retain no corrective explanation/action in the Camera overlay.

## Verification

Command:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool -destination 'platform=iOS Simulator,name=iPhone 17e,OS=26.5' -parallel-testing-enabled NO -maximum-parallel-testing-workers 1 -collect-test-diagnostics never -only-testing:shafinMultitoolTests/DecisionTracePresentationTests -only-testing:shafinMultitoolTests/CameraOverlayUXPresentationTests -derivedDataPath /private/tmp/setos-m2-030-explanations-dd-run3 -resultBundlePath /private/tmp/setos-m2-030-explanations-run3.xcresult CODE_SIGNING_ALLOWED=NO
```

- Result: **TEST SUCCEEDED**, 27 tests, 0 failures (24 CameraOverlayUXPresentationTests + 3 DecisionTracePresentationTests).
- Result bundle: `/private/tmp/setos-m2-030-explanations-run3.xcresult`
- `git diff --check`: passed.
- `python3 -m json.tool shafinMultitool/Resources/Localizable.xcstrings`: passed.
- Forbidden-style grep for blur/material/shadow/gradient in changed production/catalog files: no matches.
- Device boundary: iPhone 17e Simulator, iOS 26.5 only; no physical device or iPhone 17 Pro run.

Known boundary: M2-031 pause/resume ownership remains separate.
