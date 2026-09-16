# S07 — real data flows (local / conditional cloud) and log boundary

- Date: 2026-09-13. Branch `store`, HEAD `0733df2cb83c8e3687c31251e11e5d0747052602`, dirty worktree.
- Scope: what actually leaves the device, when, to whom, how long it is kept, how it is
  deleted, how consent is withdrawn — derived from source at the paths below, not from
  the phrase "on-device ML".
- Not covered here: provider account/retention/region decisions and a real backend
  qualification. The provider part is **C09-dependent** and is named as such below.
- Provider/hosting/retention/region decisions are prepared for the owner in
  `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/S07-rights-privacy-packet.md`.

## 1. Flows that exist in the shipping (Release) configuration

| # | Flow | What is sent | When | Recipient | Storage / deletion | Consent and withdrawal |
|---|---|---|---|---|---|---|
| L1 | Live camera analysis | nothing off device | every analysed frame | none | frame buffers only in memory; no frame persistence by the coach | camera permission; denial keeps the app in a blocked state with a Settings deep link |
| L2 | Recording with sound | nothing off device | while the user records | none | `AVCapture` movie + audio written to the app container by `RecordingArtifactStore`; deleted by the app's artifact lifecycle | camera + microphone permission |
| L3 | Photos export | finished movie written to the photo library | only on explicit user export action | user's photo library (Apple Photos) | owned by Photos; the app requests **add-only** access | `NSPhotoLibraryAddUsageDescription`; add-only request |
| L4 | Spoken scene input | **audio may leave the device** | only while the user holds/activates the speech phrase flow | **Apple Speech servers** | the app does not persist the audio buffer; retention is Apple's Speech service, outside app control | Speech permission; `NSSpeechRecognitionUsageDescription`; denial disables the feature |
| L5 | Scene parsing (default) | nothing off device | on scene-text parsing | none, when no remote endpoint is configured | scene text and generated bundle stored in the app container | no account; no consent object because no egress |
| L6 | App Attest key material | nothing until a remote endpoint is configured | lazily | none by default | App Attest key id/token in the Keychain (`KeychainAppAttestSecretStore`) | n/a until egress is enabled |

### L4 is the load-bearing privacy fact

`shafinMultitool/Services/SpeechRecognitionService.swift` builds an
`SFSpeechAudioBufferRecognitionRequest` and never sets
`requiresOnDeviceRecognition = true`. Apple's Speech framework sends that audio to
Apple's servers in this configuration. The app's own purpose string already says so:
`INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` = "…необходимы права на отправку
звука на сервера Apple" (`shafinMultitool.xcodeproj/project.pbxproj`). Any statement
that "no server dependency exists in the shipping configuration" is therefore only
true for the developer's own backend, not for the Speech path. This must be reflected
in the App Privacy answers and in the hosted privacy policy.

## 2. Conditional cloud flows (not active in the shipping configuration)

| # | Flow | What is sent | Activation | Recipient | Retention / deletion | Status |
|---|---|---|---|---|---|---|
| C1 | Remote Scene generation | scene text + App Attest assertion/enrollment payloads | `SETOS_SCENE_BASE_URL` (valid https) **and** a real App Attest device token; otherwise `SceneRemoteServiceComposition.makeRemoteProvider` returns nil | owner-selected backend | server-side job store; retention/deletion documented in the S02a operations packet, not verified end-to-end | fail-closed; deployment `blocked_external` (S02a); device qualification S02b/Q04 |
| C2 | Remote visual evidence (VLM) | structured local context **plus** a redacted, EXIF-stripped visual input reference (`VLMVisualInput.mediaRef`, `longEdgePx ≤ 1024`, `exifStripped == true`, `redactionApplied == true`) | `CAMERA_VLM_VISUAL_EVIDENCE_PROVIDER=remote` + `CAMERA_VLM_VISUAL_EVIDENCE_ENDPOINT`, all inside `#if DEBUG` only | a VLM provider endpoint | unknown; provider not chosen | **not constructible in Release**; DEBUG evaluation seam only |

The remote VLM seam is guarded by `#if DEBUG` in
`shafinMultitool/Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift`
and pinned by `tools/tests/test_release_metadata.py::test_remote_visual_evidence_stays_debug_only`.
The API key is read from `CAMERA_VLM_VISUAL_EVIDENCE_API_KEY` at runtime and is never
in the bundle.

## 3. What does NOT leak into logs (checked)

- No API key, bearer token, App Attest token, or assertion payload is printed. The
  token/network files (`AppAttestServiceTokenProvider.swift`, `SceneGenerationClient.swift`,
  `VisualSemanticEvidenceCoordinator.swift`) contain no `print`/`os_log` of credentials.
- No camera frame or pixel buffer is logged by the network or coaching code. The one
  `os_log` that touches detection output (`DETRDetector.swift`) prints labels/confidence,
  not pixels.
- `SpeechRecognitionService` prints only `error.localizedDescription`; it does not print
  recognised text or audio.
- Residual risk (release hygiene, not a secret leak): `SceneGeneratorViewModel` and
  `SceneParserService` contain unguarded `print` statements. Verified unguarded at
  `SceneGeneratorViewModel.swift:3429,5723,5791,6528,6530` (outside every `#if DEBUG`
  range) and throughout `SceneParserService.swift`; they can emit scene/entity text
  (`placedEntities.keys`, `liveHint.text`, critique text) to the system log in Release.
  These are user-authored scene contents, not identifiers, but a release should either
  remove them or route them through a Release-silent logger. This is the owner of the
  Scene logging path, not S07.

## 4. Retention, deletion, consent withdrawal (facts)

- Local scene/recording data: removed by the app's project and recording artifact
  lifecycle (`RecordingArtifactStore`, `DBService`). No cloud copy exists in the
  shipping configuration.
- Speech: the app cannot delete what Apple's Speech service retains. Withdrawal means
  revoking Speech permission (or the microphone), which disables the feature; the
  privacy policy must state that the audio is processed by Apple.
- Consent revocation for the backend (C1) is not implemented as a user control in the
  app today; the remote path is fail-closed off, so there is nothing to revoke in the
  shipping build. A real revocation/deletion UX is required before C1 can be enabled.

## 5. Honest boundary

This document proves what the source currently sends. It is **not** a legal privacy
notice, and it does not verify a deployed provider's retention. C1/C2 remain
C09-dependent; the provider choice, region, retention and deletion policy are listed as
owner decisions in the S07 packet.
