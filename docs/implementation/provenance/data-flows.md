# S07 — real data flows (local / conditional cloud) and log boundary

- Updated: 2026-09-16. Branch `store`, HEAD `c5eb957975cb4f2ee1beb98df49572ec806dd520`, dirty worktree. The 2026-09-13 / `0733df2` description is historical; the source owners below were re-read for this update.
- Scope: what actually leaves the device, when, to whom, how long it is kept, how it is
  deleted, how consent is withdrawn — derived from source at the paths below, not from
  the phrase "on-device ML".
- The latest examined engineering archive is `20260916T195158920366Z`, source fingerprint `3931df3de95e7fcd2542a1fea4ead2edf7254099f58ab2d02cde7b41f9c79200`; its `SETOSSceneBaseURL` is empty. Later HTTP hardening exists in the working tree and is not evidence about that archive's bytes. This is not a signed or admitted Release.
- The selected-still Camera client and endpoint were applied to app/backend source at 23:05–23:06 UTC on 2026-09-16. The checked Debug/Release build settings still have an empty `SETOS_SCENE_BASE_URL`; source `Info.plist` contains no Camera provider/policy fields. This source review does not establish performed production egress or a fresh archive. After the Cloud and intent additions, the catalog contains 656 keys; the older 638-key technical proof must fail until reviewed against fresh compiler products.
- Not covered here: deployed operator/provider retention, processing region and
  live service qualification. Implemented deletion and consent controls below do
  not establish those facts. The provider part remains **C09-dependent**.
- Provider/hosting/retention/region decisions are prepared for the owner in
  `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-release/S07-rights-privacy-packet.md`.

## 1. Flows in the examined Release configuration (developer backend disabled)

| # | Flow | What is sent | When | Recipient | Storage / deletion | Consent and withdrawal |
|---|---|---|---|---|---|---|
| L1 | Live camera analysis | nothing off device | every analysed frame | none | frame buffers only in memory; no frame persistence by the coach | camera permission; denial keeps the app in a blocked state with a Settings deep link |
| L2 | Recording with sound | nothing off device | while the user records | none | `AVCapture` movie + audio written to the app container by `RecordingArtifactStore`; deleted by the app's artifact lifecycle | camera + microphone permission |
| L3 | Photos export | finished movie written to the photo library | only on explicit user export action | user's photo library (Apple Photos) | owned by Photos; the app requests **add-only** access | `NSPhotoLibraryAddUsageDescription`; add-only request |
| L4 | Spoken scene input | **audio may leave the device** | only while the user holds/activates the speech phrase flow | **Apple Speech servers** | the app does not persist the audio buffer; retention is Apple's Speech service, outside app control | Speech permission; `NSSpeechRecognitionUsageDescription`; denial disables the feature |
| L5 | Scene parsing (default) | nothing off device | on scene-text parsing | none, when no remote endpoint is configured | scene text and generated bundle stored in the app container | no account; no consent object because no egress |
| L6 | App Attest enrollment and assertions | none in this configuration; configured Scene/Camera transfers require enrollment/assertion payloads | lazily, after acceptance of the exact request content and its public transfer policy | Apple's App Attest service and configured developer backend when enabled | installation key id/token and deletion recovery record in the Keychain | request approval precedes token acquisition; installation deletion has a separate explicit confirmation |

### L4 is the load-bearing privacy fact

`shafinMultitool/Services/SpeechRecognitionService.swift` builds an
`SFSpeechAudioBufferRecognitionRequest` and never sets
`requiresOnDeviceRecognition = true` (request construction at lines 23–66).
This source does not guarantee local recognition: audio **may** be processed by
Apple. It also does not prove that every recognition request uses a server.
The active RU/EN purpose strings are in `shafinMultitool/Resources/InfoPlist.xcstrings`;
their compilation is checked against the app. An empty developer backend URL must
not be described as a guarantee that every feature is offline. App Privacy answers
and the hosted privacy policy still need to describe the actual enabled Speech flow.

## 2. Conditional cloud flows (not active in the examined configuration)

| # | Flow | What is sent | Activation | Recipient | Retention / deletion | Status |
|---|---|---|---|---|---|---|
| C1 | Remote Scene generation | scene text, canonical marked-object IDs, version/request metadata, clarification answers; App Attest enrollment/assertion payloads for authorization | valid HTTPS configuration from `SETOS_SCENE_BASE_URL` or built `SETOSSceneBaseURL`, supported App Attest, complete endpoint/provider-bound public policy, and explicit approval of this request/content/policy before token acquisition | configured developer backend; its separately configured Scene provider | local server content purge and installation-revocation protocol implemented; provider copies, deployment backups and final retention durations not qualified | not enabled in the examined archive; local protocol/UI implementation is distinct from deployed service/device qualification |
| C2 | Legacy remote visual-evidence adapter | would JSON-encode structured context and an optional `VLMVisualInput` reference/metadata; this is not a qualified redacted-pixel upload path | factory selection by `CAMERA_VLM_VISUAL_EVIDENCE_PROVIDER=remote` + endpoint exists only in Debug; the actual ambient pipeline uses structured-only context, nil visual input and a non-explicit trigger, with remote consent false by default | explicit evaluation endpoint if independently constructed and authorized | no deployed provider/retention qualification | dormant in the current production caller; no performed image egress is established by this code |
| C3 | Explicit selected-still Camera analysis | one JPEG plus local entity references/regions, detector labels, issue/strength IDs, intent answers and request/frame correlation metadata; shared installation authorization | configured Scene API root and App Attest owner, complete matching Camera public policy, accepted paused frame, user action and approval of the exact prepared image/body/policy | same developer backend, `/v1/camera/evidence`; separately configured Camera provider | image/context in active request memory; bounded expiring response cache; durable quota/spend/cancellation metadata retained separately; no provider retention qualification | implemented and connected in current source; default configuration disabled and no real-provider execution established |

The factory's remote-selection branch is guarded by `#if DEBUG` in
`shafinMultitool/Multitool2Module/Services/Reasoning/VisualSemanticEvidenceCoordinator.swift`
and pinned by `tools/tests/test_release_metadata.py::test_remote_visual_evidence_stays_debug_only`.
The adapter type itself is compiled; a disabled factory branch is not the absence
of that type. Its request encoder at lines 364–377 sends a JSON reference/metadata
contract and does not prove pixel preparation, EXIF removal or actual redaction.
The API-key input is `CAMERA_VLM_VISUAL_EVIDENCE_API_KEY`; this review does not read
secret values or make a live request.

The ambient request owner `AnalysisPipeline.makePauseVisualEvidenceRequest(...)`
sets `.structuredOnly`, `visualInput=nil`, trigger `.ambiguousLocalCase`. The
designated `AnalysisPipeline.init(...)` creates `visualSemanticEvidenceCoordinator`
without overriding its default-false consent closure.
`VisualSemanticEvidenceCoordinator.swift:113–150` rejects a remote-capable provider
without an explicit user request and current consent, and rechecks consent after
the response. These are current caller guardrails, distinct from a separately
constructed diagnostic adapter or the separate selected-still path below.

C1 owners: `SceneRemoteServiceComposition.swift:34–84`,
`SceneRemoteTransferConsent.swift:6–111,114–141`, and
`SceneGenerationClient.swift:194–235`. Constructing a configured client alone does
not authorize a transfer. The acceptance is bound to request ID, request hash and
policy fingerprint; it is not persisted as blanket permission for another job.

C3 uses the existing service/installation owners. `SceneRemoteServiceComposition.swift:149–160`
configures `CameraCloudServiceBootstrap` only after the Scene client is created.
`SceneGenerationClient.swift:638–647` additionally requires the Camera policy to
match the actual endpoint, operator, security/spend retention and deletion procedure
of the Scene policy. Missing policy data leaves the Camera client absent.

`CameraViewModel.swift:1005–1060` permits a separate user action on one accepted
paused frame; preparing it does not acquire a token. `CameraCloudReviewControls.swift:107–147,194–256`
previews the exact prepared JPEG and displays the operator/provider, region,
retention, deletion and policy URL/version before approval. `CameraCloudTransferConsent.swift:114–139`
binds approval to request ID, body hash and policy fingerprint. The client checks
that approval before token acquisition (`CameraCloudAnalysisClient.swift:160–193`).
There is no automatic video upload or continuous camera-stream request path here.

`CameraCloudFramePreprocessor.swift:65–133,194–295` prepares an oriented still with
long edge at most 1024 pixels and JPEG size at most 512 KiB. It creates a fresh
raster, removes EXIF/XMP/IPTC header segments and rejects forbidden decoded
metadata. Faces and visible text remain: `redaction=none`. Resizing and metadata
removal are not anonymization. The wire request also sends local analysis context
and correlation metadata (`CameraCloudAnalysisClient.swift:119–154`).

Client cancellation invalidates the local request token, stops prepared-state use
and cancels transport. Backgrounding, route exit, resume and intent changes fence
late results. The client bounds token acquisition plus analysis to 20 seconds and
can attempt a separate three-second DELETE using an already obtained token
(`CameraCloudAnalysisClient.swift:160–258`). A failed network cancellation is not a
promise to erase data already received by a provider.

The applied backend owns authenticated POST/DELETE at `service.py:1306–1313`.
`camera_evidence_routes.py:40–68,225–283` limits cached responses to 64 entries with
60-second expiry and access/maintenance cleanup; image/context are not stored in a
durable image database. `provider_budget.py:79–117,129–218` retains dispatch/body/owner
digests, timestamps, status, charges, owner-quota rows and cancellation tombstones
without automatic expiry. These metadata are not erased by content deletion. The
provider is still unconfigured for real use; source limits and synthetic/local
integration evidence do not establish external provider or hosting retention.

## 3. Inspected diagnostic boundary

- No API key, bearer token, App Attest token, or assertion payload is printed. The
  token/network files (`AppAttestServiceTokenProvider.swift`, `SceneGenerationClient.swift`,
  `VisualSemanticEvidenceCoordinator.swift`) contain no `print`/`os_log` of credentials.
- No camera frame or pixel buffer is logged by the network or coaching code. The one
  `os_log` that touches detection output (`DETRDetector.swift`) prints labels/confidence,
  not pixels.
- `SpeechRecognitionService.swift:42,61` contains audio-engine error and recognition
  error diagnostics. These calls do not explicitly include recognised text or audio;
  that observation does not qualify arbitrary framework error descriptions as safe
  telemetry or establish a collection policy.
- The earlier Scene payload finding is corrected in current source:
  `SceneGeneratorViewModel` and `SceneParserService` diagnostics use fixed messages,
  counts, known enum values and numeric error codes instead of complete screenplay,
  marker/entity names, live-hint text or response/error bodies. The content was
  removed at call sites, including Debug; it was not merely hidden behind a build flag.
  `SceneGeneratorDiagnosticsLogger.swift:10–23` also provides the existing Release
  print suppression and Debug-only lazy logger. This is a scoped source review,
  not a statement about arbitrary OS, proxy or future provider logs.
- `SceneGenerationClient`, `AppAttestServiceTokenProvider` and
  `InstallationDeletionTransport` use the shared `BoundedServiceHTTPTransport` for
  bounded responses, cancellation and redirect rejection. Those controls do not
  imply that a deployed backend's request logging has been qualified.

## 4. Retention, deletion, consent withdrawal (facts)

- Local scene/recording data: removed by the app's project and recording artifact
  lifecycle (`RecordingArtifactStore`, `DBService`). No cloud copy exists in the
  examined developer-backend-disabled configuration.
- Speech: the app cannot delete what Apple's Speech service retains. Withdrawal means
  revoking Speech permission (or the microphone), which disables the feature; the
  privacy policy must state that Apple may process the audio remotely.
- Scene approval is per request; declining a new transfer stops it before enrollment
  or token acquisition (`SceneGenerationClient.swift:220–235`). This is separate
  from deleting data from an earlier accepted request.
- The Privacy sheet now exposes installation deletion with an explicit destructive
  confirmation (`SETPrivacyInformationView.swift:159–223`). Opening it reads local
  state only. After a confirmed operation, the presentation can perform up to five
  receipt checks two seconds apart; reopening the sheet does not silently resume
  network polling (`SETInstallationDeletionPresentation.swift:22–59,87–113,163–181`).
- `AppAttestServiceTokenProvider.swift:538–651,736–752` persists deletion intent and
  receipt recovery state, blocks enrollment/token refresh, and reports completion
  only after a validated unexpired complete receipt and local credential cleanup.
  Missing/expired receipts and uncertain outcomes remain explicit. Closing the
  sheet stops its observation; it does not undo the server deletion request.
- The backend implements authenticated challenge, deletion submission and receipt
  routes (`../setos-backend/service.py:1075–1170`). Its owner fence and
  `store.py:1072–1114` purge request/result/clarification content; completion waits
  for cancelled local Scene and Camera body-intake/provider tasks; Camera cache is
  purged before completion (`service.py:777–803`). The existing receipt scope is
  `local_scene_content_and_auth_material`, with `policy_qualification=not_asserted`.
  Security/replay identity, job quota/idempotency metadata and provider spend records
  are expressly retained (`app_attest_state.py:88–96`), not represented as erased.
- This local deletion protocol cannot attest deletion of a provider's independent
  copies, operational logs, backups or snapshots. Final durations, backup recovery
  behavior, operator identity, region, provider policy and a public deletion contact
  remain required deployment facts; none is inferred from receipt expiry.

## 5. Honest boundary

This is source and configuration evidence, **not** a legal privacy notice or proof
of a deployed provider's retention. C1/C2/C3 deployment
remain C09-dependent. Operator/provider identity, region, duration for each retained
category, backup/log policy, deletion procedure and policy URL/version must be
supplied from the actual service. A technical pass for exact localization or privacy
manifest bytes does not approve those disclosures or close physical-device checks.
