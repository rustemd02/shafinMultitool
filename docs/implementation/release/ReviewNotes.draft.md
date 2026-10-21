# Review notes (draft, not submitted)

Status, 2026-09-17: technical draft, **NOT READY** to paste into App Store
Connect. The unsigned engineering artifact below is bound to completed archive,
post-archive and corrupted-copy control receipts. The signed build, configured service, Camera quality and physical
acceptance remain open. Four component provenance rows remain PENDING; the six
scoped resource decisions do not admit the complete app. Nothing here has been
submitted and no App Store Connect action was performed.

## What the app does

Shafin Multitool is a camera coach. In Camera mode it analyses the live frame on
device and presents a coaching suggestion when the available evidence supports it.
The intended Scene flow turns a written description into a staged shot list that
the user can save and work with locally. Configured cloud Scene generation uses
the app's backend and provider; local fallback is a separate capability and does
not establish equivalent generation quality. There is no user-account sign-in;
backend access uses installation authentication through App Attest.

## What the reviewer needs

1. **Camera.** The camera is the core surface; the app asks for camera access on
   first use of Camera mode and explains why in the system prompt. Microphone,
   Speech and Photos (add-only) are requested only for their own features
   (recording with sound, spoken scene input, saving a finished video).
2. **No account.** Every feature is reachable without sign-in. Nothing needs to be
   purchased to reach the coaching surface.
3. **Processing and network use.** Ambient Camera analysis uses Vision, the
   bundled Core ML baselines and the local planner. The legacy remote-evidence
   factory remains Debug-only. The separate explicit selected-still Camera path
   is implemented in source and needs a configured backend, matching public
   provider policy, installation authorization and approval of the exact image,
   request and policy. It sends one prepared JPEG and analysis context; it is
   not an automatic video-stream upload. This artifact's actual backend URL is
   `"" (empty)`; the current unconfigured profile does not enable this path.
   Spoken scene input may use Apple's Speech service. Configured Scene requests
   likewise require their request/policy approval. Actual deployment/provider
   retention and deletion disclosures need qualification before enabling either
   developer cloud path; metadata removal does not anonymize image content.
4. **Insufficient evidence.** The intended behaviour is to withhold advice when
   the available evidence does not support a specific action. Final acceptance
   must distinguish justified silence from unavailable perception or a broken
   pipeline; lack of advice by itself does not establish correct behaviour.

## Current engineering artifact and local placement flow

This is an unsigned engineering artifact, not an admitted submission build:
`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/source-resource-admission-20260917/final-verification/archives/20260917T050524112755Z-release-archive/SETOS.xcarchive`. Baseline `c5eb957975cb4f2ee1beb98df49572ec806dd520`, branch
`store`; 667 input files, fingerprint
`d974816b880e3df4f762e72dd9ffe1f7c7bbd5697f58bb388a344f7e1c6adaba`. The actual source patch and 39
untracked inputs are required to restore its dirty snapshot. The actual arm64
compile list contains 213 app Swift files, including the
image-placement feature. Native build/wrapper/validation exits are
0/2/1; status `engineering_archive_built_release_validation_failed`.
`release_ready=false`; signing and service/device acceptance are separate gates.

In Camera Pause, Position in Frame opens the accepted image. The user can select
an available region or draw/edit an image-space region, cancel the draft, save
an image-space centering preference and reset it. The accepted pause shows a
reference region and a next-take instruction; Resume clears this frame-bound
goal. This does not establish identity tracking in a new live frame.
Saving does not claim that the
object moved physically or that the image improved. Final UI evidence:
`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-execution-20260916/20260917T045712379671Z-camera-image-placement-content-start-iphone`, 2/2 PASS; RU/EN simulator fixture journeys with runtime binary identity bound, receipt SHA
`82b99e16128769fab5dba38a3864c26ff9f8c6122e432336aa384e6d1c7d8fd4`. Real-camera and subjective usefulness acceptance
remain open even when these simulator controls pass.

The source and compiled weight bytes were actually compared:

| Bundle model | Observed source/bundle weight SHA256 |
| --- | --- |
| `DETRResnet50SemanticSegmentationF16P8.mlmodelc` | `8e0a22ecc1921f81611864434714ae1989f3e992ec04994ed22a8ead6deccce7` |
| `aesthetic_nima_mobilenet_fp16.mlmodelc` | `198486adb600611945b067dd77c1ceb65f3ac5ad19733ace4deed5d7587fd717` |

The corrected NIMA FP32 candidate remains external and is not admitted or
substituted here. The production NIMA conversion defect and broader quality
gates remain open. DETR public-source correspondence and complete notices do
not by themselves admit the entire model chain. `llama.framework` retains its
independent unresolved row and replacement acceptance dependencies.

Actual new localization results: 682 Localizable keys and
5 InfoPlist keys per language, 12/12 corrupted-copy controls rejected with expected reasons.
Detailed identities and fresh receipt links are in `ReproducibleBuild.md`.
The four remaining component rows are `detr-segmentation-model`, `llama-framework`,
`nima-aesthetic-model` and `resource-assets-catalog`. The default endpoint is
unconfigured; local Scene fallback does not establish the required server path.

## Historical 2026-09-16 19:51 artifact

The following evidence is retained for that older snapshot only. Its 638-key
catalog, ten historical PENDING rows and compiler counts are not the current
feature or final artifact evidence.

That historical artifact is
`/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/verification/release-next-preflight-20260916-1hb3qbu4/archives/20260916T195158920366Z-release-archive/SETOS.xcarchive`.
Its baseline is `c5eb957975cb4f2ee1beb98df49572ec806dd520`, branch `store`;
634 frozen inputs have fingerprint
`3931df3de95e7fcd2542a1fea4ead2edf7254099f58ab2d02cde7b41f9c79200`.
The saved patch and six untracked inputs are required in addition to the commit.
All 193 app Swift files appear in the actual compilation list, including the
installation-deletion implementation. Source and archive remained unchanged
through post-build checks.

Build exit 0; bundle validation exit 1; wrapper exit 2. The archive is unsigned
and `release_ready=false`. `SETOSSceneBaseURL` is still empty, so remote Scene
generation is unavailable in this artifact. The local fallback does not establish
completion or equivalent quality of the required server flow. The final service
configuration, authorization, privacy policy and end-to-end generation/deletion
behaviour require separate qualification.

The actual bundle contains these two compiled Core ML baselines:

| Bundle model | SHA256 of source and compiled weights |
| --- | --- |
| `DETRResnet50SemanticSegmentationF16P8.mlmodelc` | `8e0a22ecc1921f81611864434714ae1989f3e992ec04994ed22a8ead6deccce7` |
| `aesthetic_nima_mobilenet_fp16.mlmodelc` | `198486adb600611945b067dd77c1ceb65f3ac5ad19733ace4deed5d7587fd717` |

Weight identity and compiled membership do not admit model quality or rights.
The research composition checkpoint, GGUF and DeviceBenchmark are excluded;
`llama.framework` remains present and has an unresolved provenance row.

Both source localization catalogs equal their actual compiled EN/RU resources:
638 Localizable keys and five InfoPlist keys per language. The current
`remote_disabled` privacy manifest equals the source baseline; root and SnapKit
are the only two privacy manifests. All 12 corrupted-copy controls are rejected.
These technical checks do not change the ten PENDING legal/provenance statuses.

Detailed receipts and SHA values are in `ReproducibleBuild.md`. The aggregate
receipt is
`../setos-backend/local-data/SETOS/verification/release-next-preflight-20260916-1hb3qbu4/final-release-archive-verification.json`
(SHA256 `13198b3aa57582c95c0a4026f4788c3118341d663c34e9b855da475563d4c75b`).

Historical evidence remains unchanged:
`../setos-backend/local-data/SETOS/verification/release-execution-20260916/20260916T152044616359Z-release-archive/`
and `20260916T152455588085Z-archive-validator-repair/`. That older archive predates
the Camera recording/current-pixel tracking package; its 11 controls and old
localization inventory qualify only that preserved artifact.

## Known limitation to verify before writing final notes

The simulator has no camera feed, so the full camera flow cannot be exercised
there. The owner still has to run the physical-device pass (first launch,
permission denial, offline, recording, thermal and background behaviour) before
any submission; gate 11 of the product plan is open and is not substituted by
simulator evidence.

The actual device Debug build
`../setos-backend/local-data/SETOS/verification/physical-command-package-20260916-m1z9o3ub/20260916T195715143150Z-debug-ieqgn7wo/`
failed with native exit 65: the selected Personal Development Team `5NAKQ28539`
does not support the required App Attest capability. The source stayed unchanged;
the app was neither installed nor launched. Its `build-receipt.json` SHA256 is
`e24dbdf485728927a7f5f5ca9ebbfc29c9371b28526480008b7def0bfdf6e055`.
The owner's selection of a suitable App Attest-capable signing team remains
separate. The repository ExportOptions currently names that Personal team and
is an unqualified template, not a working signing recipe. Later diagnostic
results, if any, stay in the canonical tracker and its receipts; a diagnostic Debug app does not
close intended App Attest signing or physical acceptance.

## Open items before this draft can be submitted

- Support URL, marketing URL and the hosted privacy policy (gate 5).
- Screenshots for the required sizes, captured after the flows are final.
- Name and subtitle: owner decisions held until beta evidence.
- Qualified backend URL, provider/retention/deletion disclosures and successful
  generation-to-saved-scene acceptance on the final configured build.
- Matching signing team/profile, physical-device acceptance and admitted Camera
  model quality.
- Four unresolved component provenance rows in the canonical
  `docs/implementation/provenance/release-component-status.json`, plus unchanged
  replacement and model-quality gates. Source/bundle equality does not grant admission.
- A signed submission artifact after the remaining requirements are closed.
  This unsigned snapshot has completed identity and 12 corrupted-copy controls;
  changed build inputs require a new archive and related validation.

StoreKit, subscriptions, credits and IAP are outside the approved 1.0 scope under
master plan §3.9; this draft introduces no paid feature or App Store Connect SKU.
