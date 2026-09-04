# M7-003 — serialized audio-session state matrix

Status: **implemented and verified in the isolated recording lane**.

## Ownership and policy

`AudioSessionCoordinator` is the single serialized owner for recording and
recorded-take playback. `LiveAudioSessionPlatform` is the only live type that
calls `AVAudioSession.setCategory`, `setMode`, or `setActive`; tests inject the
small `AudioSessionPlatform` seam. `CameraService` no longer owns an
`AVAudioSession` directly.

| Purpose | Category | Mode | Options | Activation rule |
|---|---|---|---|---|
| recording | `.playAndRecord` | `.videoRecording` | `.allowBluetoothHFP`, `.defaultToSpeaker` | only after the sound-on permission boundary |
| playback | `.playback` | `.moviePlayback` | none | acquired before `AVPlayerViewController` presentation |

No mix, duck, or A2DP preference is added. A recording lease and a playback
lease cannot be live at the same time.

## Lease/state matrix

| Operation or event | State/result | Platform effect |
|---|---|---|
| acquire with no live lease | new valid lease, nonzero generation, inactive | none |
| acquire by same owner and purpose | same lease (idempotent) | none |
| acquire by another owner or purpose | typed `.busy` | none |
| configure/activate | active after exact category → active order | `setCategory`, then `setActive(true)` |
| configuration or activation failure | typed failure; lease cleared | best-effort `setActive(false, .notifyOthersOnDeactivation)` |
| matching deactivate/release | inactive and lease cleared | `setActive(false, .notifyOthersOnDeactivation)` |
| repeated release of the just-released lease | idempotent no-op | none |
| stale release after replacement | typed `.staleLease` | none; replacement remains active |
| interruption began | `.interrupted` | no automatic reconfiguration |
| interruption ended (`shouldResume`) | inactive plus typed event | reports the flag; never auto-resumes |
| route change | typed new/old/category/override/wake/no-suitable/configuration/unknown reason | no implicit resume |
| media-services reset | lease invalidated and generation advanced | best-effort deactivation only |

`CameraService.prepareRecorder()` fences late coordinator activation with a
preparation UUID and releases the exact matching lease once. Scene recording
uses the coordinator lease only after microphone authorization and releases it
after the awaited recorder stop/finalization. The recorded-take player uses an
owner UUID, cancellation/identity fencing, pause-and-nil teardown, and release
on dismissal, disappearance, replacement, route exit, or failure.

## Verification record

Executed from this worktree on the ordinary iPhone 17 simulator (iOS 26.5;
OS build 23F77):

```text
xcodebuild test -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:shafinMultitoolTests/AudioSessionCoordinatorTests \
  -only-testing:shafinMultitoolTests/SceneRecordingControllerTests \
  -only-testing:shafinMultitoolTests/RecordingStartTeardownRaceTests \
  -derivedDataPath /tmp/setos-m7-003-004-dd-20260904n \
  -resultBundlePath /tmp/setos-m7-003-004-result-20260904n.xcresult
```

Result: **TEST SUCCEEDED**, 26/26 passed, 0 failed, 0 skipped:
6 `AudioSessionCoordinatorTests`, 18 `SceneRecordingControllerTests`, and 2
`RecordingStartTeardownRaceTests`. The result bundle summary reports one
device, `iPhone 17`, iOS 26.5, and `totalTestCount: 26`.

The first pre-seam run was a real 16/18 regression: the two authorized
recorder tests attempted live simulator audio-session activation and therefore
never reached the recorder. The tests now inject the platform seam; the
assertions were preserved, and both tests pass in the 26/26 run. This is not a
claim that simulator audio hardware or a physical microphone was qualified.

The owner search was also run:

```text
rg -n "AVAudioSession|setCategory|setMode|setActive" shafinMultitool --glob '*.swift'
```

Only `AudioSessionCoordinator.swift` contains the direct AVAudioSession
mutator calls; other matches are protocol/configuration references or
unrelated `setActiveModule`/overlay APIs.

The iPhone 17 Pro and all physical devices were not targeted. Physical route,
Bluetooth, interruption, microphone, A/V-sync, and thermal qualification are
outside this simulator evidence.
