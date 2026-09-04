# M7-004 — microphone permission and explicit sound matrix

Status: **implemented and verified in the isolated recording lane**.

The reachable Scene/AR shell defaults to `recordingSoundEnabled == true`. The
setting is exposed as the existing capture chip style with the sole new
accessibility identifier `generator_recording_sound_button`; its localized
action and localized `SOUND ON`/`SOUND OFF` value are both exposed to
accessibility and its hit frame is at least 44 pt. The error band is inset below
the fixed toolbar so the control remains reachable while an inline error is
visible.

## Decision matrix

| Sound choice / microphone state | Snapshot | Request | Audio lease/activation | Recorder policy and result | Recovery surface |
|---|---:|---:|---|---|---|
| sound off | 0 | 0 | none | `.disabled` + `.explicitVideoOnlySelection`; start video-only attempt | no permission action |
| sound on, available + authorized | 1 | 0 | recording lease, exact recording policy | `.required` + `.failRecording`; start with sound | none |
| sound on, available + not determined | 1 | 1 | recording lease only after authorized response | `.required` + `.failRecording`; start with sound | none if authorized |
| sound on, denied | 1 | 0 | none | no recorder | localized Denied + Open Settings + explicit “Record without sound” |
| sound on, restricted | 1 | 0 | none | no recorder | localized Restricted + Recheck + explicit “Record without sound” |
| sound on, unavailable or unknown reason | 1 | 0 | none | no recorder | generic recorder error + explicit “Record without sound” |
| authorized but audio-session activation fails | 1 (and no request when already authorized) | 0 | failed lease is cleared by coordinator | no recorder; required path never downgrades | generic recorder error + explicit silent retry |
| recorder start fails after activation | as above | as above | matching lease released after the failure | no recorder | generic recorder error + explicit silent retry |

Microphone permission is snapshotted/requested only for the sound-on required
path. The silent retry is a new attempt: it changes the policy to
`.disabled + .explicitVideoOnlySelection`, performs no second permission
request, and does not infer a downgrade from the failed required attempt.
Changing the chip is rejected while a take is starting, recording, or
finalizing. Teardown cancels the start identity, awaits any stop, and leaves no
audio lease behind.

## Test evidence

The focused unit run recorded in
`M7-003-audio-session-state-matrix.md` passed 26/26, including:

- sound-off zero snapshot/request/coordinator calls and disabled recorder
  configuration;
- denied microphone with Open Settings state and an explicit silent retry;
- restricted, unavailable, and unknown microphone outcomes;
- authorized retry, recorder-start cleanup, and both teardown/permission
  races.

The production-route accessibility fixture was run with parallel simulator
clones disabled:

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -parallel-testing-enabled NO \
  -only-testing:shafinMultitoolUITests/SETGeneratorProductionUITests/testRecordingSoundControlIsExplicitAndAccessible \
  -derivedDataPath /tmp/setos-m7-003-004-ui-dd-20260904m \
  -resultBundlePath /tmp/setos-m7-003-004-ui-result-20260904m.xcresult
```

Result: **TEST SUCCEEDED**, 1/1 passed, 0 failed, 0 skipped on the ordinary
iPhone 17 simulator, iOS 26.5. The test reaches the commercial Scenes route,
checks the identifier, enabled state, 44 pt frame, localized action/value,
toggles OFF and ON, and exits through the route-owned back action.

An earlier complete attempt was 0/1 because the pre-fix error band covered the
toolbar and made the button non-hittable; that was corrected in the production
layout by reserving the toolbar's 44 pt region. Earlier clone-launch output
was incomplete and is not counted as evidence.

## Catalog and device boundary

`InfoPlist.xcstrings` was left byte-identical because its existing English and
Russian microphone descriptions already say access is needed only when the
user chooses video recording with sound. Both catalogs are valid JSON and
`xcrun xcstringstool compile --dry-run` succeeded for all four locale outputs:

```text
xcrun xcstringstool compile --dry-run \
  --output-directory /tmp/setos-m7-003-004-xcstrings-20260904a \
  shafinMultitool/Resources/Localizable.xcstrings
xcrun xcstringstool compile --dry-run \
  --output-directory /tmp/setos-m7-003-004-xcstrings-20260904a \
  shafinMultitool/Resources/InfoPlist.xcstrings
```

The requested direct `plutil -lint` invocations were also attempted, but
macOS `plutil` treats `.xcstrings` as a property-list input and returned
`Unexpected character { at line 1` for each JSON catalog. JSON parsing and the
Xcode string-catalog compiler are the format-correct checks; the Xcode build
also compiled both catalogs successfully.

No iPhone 17 Pro or physical device was targeted. This evidence makes no
physical microphone, route, Bluetooth, interruption, or performance claim.
