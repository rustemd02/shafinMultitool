# Camera Coach backlog — wave M0

Волна создаёт проверяемую производственную базу. Она не реализует StoreKit, backend или массовый UI-рефакторинг до закрытия соответствующих evidence gates.

## CC-000 — синхронизировать Product и Deep Research

- Lane: Sol.
- State: `accepted`.
- Ownership: `docs/app-store-product-plan.md`, orchestration/tracker docs.
- Result: beachhead narrowed; local core free; public paid model deferred; subscription/credits conditioned on beta; Scene Mode secondary.
- Acceptance: current sections do not require subscription, paid history or paid Scene Mode before evidence.

## CC-001 — Release bundle inventory

- Lane: Luna / Max.
- State: `accepted`.
- Dependencies: bootstrap commit.
- Ownership: create only `docs/implementation/audits/release-bundle-inventory.md`.
- Read: `project.pbxproj`, build phases, asset catalogs, model/resource references, current built app under a fresh worker-derived directory.
- Must report: every file/class over 1 МБ; source path; reason it enters bundle; Debug/Release necessity; license/provenance state; keep/exclude/on-demand/download candidate; exact owning build setting or project reference.
- Must not edit: Xcode project, source, resources or product plan.
- Verification: clean generic Release build with signing disabled if buildable; `du`/bundle inventory commands; `git diff --check`.
- Acceptance: report explains the 1,0 ГБ GGUF, benchmark packs and all material bundle contributors and provides an exact implementation sequence without deleting files.
- Evidence: `docs/implementation/audits/release-bundle-inventory.md`; accepted after correction loop and independent clean/contaminated Release partial-product reconciliation.

## CC-002 — Exclude research assets from Release

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: exact project/resource files named by accepted CC-001; focused regression tests if needed.
- Objective: Release contains only explicitly allowed production resources while DEBUG/device benchmark flows remain reproducible.
- Constraints: no deletion of datasets or models; no loss of test/eval evidence; no change to product behavior beyond resource availability by configuration.
- Verification: Debug build-for-testing; Release build/archive-equivalent; bundle inventory asserts forbidden assets absent and required assets present.
- Acceptance: Release bundle size reduction is measured, resource access fails explicitly outside supported configurations, tests pass.
- Evidence: worker commit `c2b8d4c`, accepted commit `2d7c26e`; parent Release build produced a 72 728 КБ app without `DeviceBenchmark`, `Models` or GGUF, and parent Debug test build retained both nested benchmark manifests plus the Debug marker.

## CC-003 — Privacy and permissions inventory

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/privacy-permissions-inventory.md`.
- Read: usage descriptions, camera/microphone/Speech/Photos call sites, telemetry/offloading code, dependencies and App Store privacy requirements already cited in product docs.
- Must report per permission/data type: trigger, purpose, timing, allowed/denied/restricted behavior, stored/transmitted fields, current user-facing copy, missing tests, privacy manifest/API-reason impact, and exact production owner candidate.
- Must not invent processor, region, retention or legal claims.
- Verification: exhaustive `rg` call-site queries recorded; plist validation; `git diff --check`.
- Acceptance: every permission and external-data path has a disposition and executable follow-up; unknowns are explicit.
- Evidence: `docs/implementation/audits/privacy-permissions-inventory.md`; accepted after path-only diff, plist validation and parent negative/call-site checks.

## CC-004 — Dependency, model and media provenance inventory

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/dependency-provenance-inventory.md`.
- Read: `Podfile`, `Podfile.lock`, vendored frameworks/packages, Core ML packages, GGUF, images, USDZ/Reality Composer assets and acknowledgements.
- Must report: component, version/hash where observable, runtime role, source, license evidence path, redistribution status, privacy/network behavior, bundle impact and disposition `verified / missing / replace / exclude`.
- Must not assert a license from filename or memory.
- Verification: filesystem/hash/package metadata commands and `git diff --check`.
- Acceptance: every shipped third-party binary/model/media family is covered; missing provenance becomes a blocking follow-up rather than guessed approval.
- Evidence: `docs/implementation/audits/dependency-provenance-inventory.md`; accepted after path-only diff inspection, independent SHA-256 spot checks and explicit separation of repository evidence from legal approval.

## CC-005 — Test topology and UI-test target plan

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/test-topology.md`.
- Read: Xcode targets/schemes, all test files, test host settings, benchmark/UI-labelled tests and existing test documentation.
- Must report: which tests compile/run under which target; UI tests incorrectly living in unit target; conditional skips/false-green risks; simulator/device requirements; exact new UI-test target/file membership/scheme plan; minimal CI matrix.
- Verification: `xcodebuild -list`; build-for-testing; targeted dry enumeration where supported; `git diff --check`.
- Acceptance: report provides a mechanical implementation packet for a true UI-test target and separates unit, integration, benchmark and device-only gates.
- Evidence: `docs/implementation/audits/test-topology.md`; accepted after path-only diff, generic iOS test build and parent workspace enumeration.

## CC-006 — Runtime entry and legacy route audit

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/runtime-entry-routing.md`.
- Read: `AppDelegate`, `SceneDelegate`, `SOModuleBuilder`, scene overview/stage selection, `ContentView`, camera shell entry points and benchmark environment route.
- Must report: launch graph, navigation owners, orientation assumptions, camera owners created per route, persistent-state dependencies, candidate commercial shell seam, routes safe to retire later and required negative tests.
- Must not change navigation or delete legacy code.
- Verification: call graph searches, compile baseline reference and `git diff --check`.
- Acceptance: one lowest-risk seam for Camera Coach default entry is recommended with explicit compatibility and retirement boundaries.
- Evidence: `docs/implementation/audits/runtime-entry-routing.md`; accepted after `git diff --check`, source-citation spot checks and generic iOS `build-for-testing` (`** TEST BUILD SUCCEEDED **`).

## CC-007 — Commercial shell and Camera Coach default route

- Lane: Luna / Max after Sol architecture packet.
- State: `draft`.
- Dependencies: CC-006 and CC-008.
- Ownership: exact shell/entry files selected after audit; no camera/session internals.
- Objective: app opens Camera Coach by default and exposes secondary Scene Mode without duplicating camera ownership.
- Verification: unit/navigation tests, true UI smoke when target exists, portrait/landscape launch checks and Scene Mode saved-project access.
- Acceptance: no scene-first onboarding, no dead end, no regression in opening existing scenes, no vibe-code navigation patterns.

### CC-007A — Single-active-route shell contract

- Lane: Luna / Max after CC-008 owner acceptance.
- State: `ready_after_CC-008`.
- Dependencies: CC-006, CC-008.
- Ownership: create only `shafinMultitool/CommercialShell/CommercialShellViewController.swift` and `shafinMultitoolTests/CommercialShellRoutingTests.swift`.
- Non-edits: `SceneDelegate`, `ContentView`, camera/session internals, Scene Mode routers, recorder, project file and existing UI. This slice does not change the launch graph.
- Contract: `CommercialSection` has exactly `camera`, `scenes`, `history`; `CommercialRoute` exposes one `viewController` and awaited `deactivateAndWait()` returning a typed released/blocked result.
- Behavior: custom single-child container with a system `UITabBar`; Camera selected by default; Scenes and History are lazy; exactly one active child and retained route; selection is disabled during teardown; a blocked teardown retains the current child and selection; rapid taps coalesce to the last pending section; repeated current selection is a no-op.
- Focused tests: default selection, lazy construction, one-child invariant, teardown-before-create ordering, blocked rollback, interaction lock, rapid-tap coalescing, repeat-selection no-op, child containment lifecycle and route release on container teardown.
- Acceptance: deterministic routing contract passes focused tests and generic iOS build-for-testing without changing runtime launch behavior.
- Rollback: remove the two owned files; no production route is connected by this slice.

## CC-008 — UI/UX state specification

- Lane: Sol owns decisions; bounded Luna tasks may produce artifacts after specification.
- State: `proposed_for_owner_acceptance`.
- Ownership: `docs/implementation/ux/**` only until implementation packets are approved.
- Must specify: onboarding, permissions, live Coach, one-tip lifecycle, tap-to-clarify, action detected, before/after verification, keep-as-is, abstention, pause summary, recording, offline, thermal, server consent/timeout/quota, History if retained, Scene Mode entry and both orientations.
- Visual constraints: native hierarchy, semantic system materials/colors, restrained motion/haptics, no dashboard-card grid, gradient-everything, fake AI glow, oversized marketing hero inside tools, decorative glass stacks or arbitrary pill overload.
- Acceptance: every state has entry/exit, primary action, recovery, accessibility, analytics event and screenshot acceptance criteria; no open decision is delegated to Luna.

### CC-008A — Truthful production live coaching surface

- Lane: Luna / Max after CC-008 owner acceptance.
- State: `ready_after_CC-008`.
- Dependencies: CC-008, CC-010B.
- Ownership: `CameraOverlayUXPresentation.swift`, `SuggestionChip.swift`, `OverlayView.swift`, `ZoomControlView.swift`, `CameraOverlayUXPresentationTests.swift` and at most one narrow rendering test under existing target membership.
- Non-edits: `ContentView`, `CameraViewModel`, `CameraManager`, `AnalysisPipeline`, `RealtimeScheduler`, `SuggestionListView`, `SceneDelegate`, Scene Mode, recorder, Deep Review, persistence and `project.pbxproj`.
- Supported product states: only live seeking S04, stable tip S06, explanation S07 and keep-as-is S10c, mapped from existing `LiveHint` data. Incomplete payload degrades to one safe line.
- Explicitly unsupported in this slice: onboarding/permissions, subject clarification, action observation, before/after verification, pause summary, recording/save, Deep Review, thermal/offline policy, shell/history and paid state. UI and copy must not imply these exist.
- Surface: one lower-third hierarchy with observation, one physical action and inline `Почему?`; no permanent grid/bounding box, confidence percentage, reserve badge, raw trace/pipeline terms, GOOD/REVIEW labels, card stack, fake AI glow or decorative gradients. Guides appear only when tied to the current action. Debug UI is compiled only under `#if DEBUG`.
- Accessibility: stable identifiers, preview hidden from VoiceOver, icon controls labelled, 44×44 pt targets, Dynamic Type, Reduce Motion and Reduce Transparency behavior.
- Tests: exhaustive presentation mapping, incomplete-payload fallback, negative forbidden-copy assertions (`%`, trace, semantic, reserve, GOOD/REVIEW), deterministic portrait/landscape rendering attachments and focused build/test verification.
- Acceptance: the live surface communicates only evidence the current pipeline actually owns, remains legible in both orientations and passes the banned-pattern/screenshot gates from CC-008.
- Rollback: revert only the owned presentation/UI files and focused tests; no camera lifecycle rollback is required.

## CC-009 — Camera/session owner and lifecycle audit

- Lane: Luna / Max audit; implementation may route to Terra / High.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/camera-session-ownership.md`.
- Read: `CameraManager`, `CameraViewModel`, recording service, AR camera shell/container, overlays and app lifecycle/orientation hooks.
- Must report: session creation/destruction, queues/actors, frame consumers, record/save owner, background/foreground behavior, rotation path, permission assumptions, thermal/memory controls, duplicated ownership and concurrency risks.
- Verification: call-site graph with exact paths/symbols, current build evidence and `git diff --check`.
- Acceptance: identifies canonical owner candidate and separates mechanical fixes from high-complexity migration work.
- Evidence: `docs/implementation/audits/camera-session-ownership.md`; accepted after path-only diff inspection and parent generic iOS `build-for-testing` (`** TEST BUILD SUCCEEDED **`).

## CC-010 — Camera foundation migration program

- Lane: Luna / Max for bounded mechanics; Terra / High only for recorder/route integration proven wide-blast-radius by CC-009.
- State: `decomposed`.
- Dependencies: CC-009; individual slices below add their own gates.
- Objective: one camera/session owner with reliable lifecycle, recording, rotation and resource cleanup.
- Boundary: saved Scene Mode data remains compatible; no StoreKit/backend/UI redesign.
- Verification: focused unit/integration tests, simulator lifecycle tests and required physical-device smoke matrix.

### CC-010A — Awaitable Coach capture lifecycle

- Lane: Luna / Max.
- State: `accepted`.
- Ownership candidate: `CameraManager.swift`, `CameraViewModel.swift`, minimal `OverlayView.swift` call-site changes and focused lifecycle tests selected in the task packet.
- Objective: serialize capture start/stop, make completion awaitable and idempotent, publish typed failure/state, drain/detach the video delegate before stop returns, and prevent post-release frames from reaching the scheduler.
- Non-goals: permissions UI, recording, Scene Mode, route shell, orientation redesign and scheduler/pipeline unregister.
- Acceptance: repeated/racing start-stop tests pass; generic iOS test build passes; existing Camera Coach frame flow remains intact.
- Evidence: worker commit `b93e4aa`, accepted commit `e0bd423`; generic build-for-testing passed, and Sol independently reran `CameraManagerLifecycleTests` on iPhone 17 Pro simulator with 7/7 passing.

### CC-010B — Scheduler and pipeline release

- Lane: Luna / Max.
- State: `accepted`.
- Objective: own registration tokens, unregister deterministically, cancel/await outstanding analysis work and fence stale presentation updates.
- Acceptance: register/release/re-register and stale-result tests pass without changing recommendation semantics.
- Evidence: worker commit `1926988`, accepted commit `79f7d1d`. `AnalysisPipeline` owns the three scheduler tokens; registration is rejected during release; unregister, queue/task draining and generation fences make release terminal. Sol independently passed generic simulator `build-for-testing` and 23/23 focused tests across `AnalysisPipelineReleaseTests`, `RealtimeSchedulerTests` and `CameraManagerLifecycleTests`.

### CC-010C — Serialized recorder ownership

- Lane: Sol decomposes; Luna / Max owns isolated mechanics; one-time production migration remains high-complexity review because `CameraService.shared` crosses current Scene Mode, legacy CameraScreen, audio capture, AR pixel buffers, `AVAssetWriter` and Photos.
- State: `partially_in_progress`; production wiring waits for recording/save/retention policy accepted from CC-008/CC-003.
- Objective: one serialized recorder state machine, awaited finalization, stopped audio capture, typed local-file/Photos result and deterministic cleanup.

#### CC-010C-A — Policy-neutral serialized recorder core

- Lane: Luna / Max, Sol verification and acceptance.
- State: `in_progress`.
- Task: `01a00609-a689-7373-b2d4-d0eb245a6c66`.
- Ownership: create only `shafinMultitool/Services/Recording/RecorderContracts.swift`, `shafinMultitool/Services/Recording/SerializedMediaRecorder.swift` and `shafinMultitoolTests/SerializedMediaRecorderTests.swift`.
- Non-edits: current `CameraService`, Scene/legacy Camera call sites, AR container, Camera Coach, lifecycle delegates, project/plist/privacy files, Photos and permissions.
- Contract: typed idle/prepared/recording/finishing/finished/failed/released state; caller-supplied UUID/output URL/audio policy; one serial queue; generation fence for late frames; shared in-flight awaited finish; idempotent release; separate export protocol with no Photos implementation.
- Focused tests: transition validity, writer/audio single start, required/disabled audio, queue confinement, late-frame fence, concurrent/repeated stop, finish failure, no-video result, prepared/recording release, waiter cancellation and absence of automatic re-prepare/export.
- Acceptance: focused tests and generic iOS build-for-testing pass; the owned files have no dependency on current recorder/call sites or Photos; no runtime behavior changes.
- Boundary: this foundation is not production recording. CC-010C remains incomplete until owner-approved save/retention/background/route-exit policy and a separately reviewed production migration.

### CC-010D — Scene route teardown

- Lane: Luna / Max after CC-010C exposes a stable interface.
- State: `draft`.
- Objective: Scene back/disappear/background awaits recorder policy, pauses/releases AR, then persists through the existing unified project/world-map path.

### CC-010E — Exclusive route lease integration

- Lane: Terra / High for the one-time cross-route migration; subsequent shell slices return to Luna.
- State: `blocked_by_CC-007`.
- Objective: commercial shell owns a serialized `none / cameraCoach / sceneMode` lease and never activates a new route before the previous owner releases.

### CC-010F — Orientation continuity

- Lane: Luna / Max after CC-008 and CC-010A.
- State: `blocked_by_CC-008`.
- Objective: portrait/landscape reflow and capture/writer/AR transforms change in place without session, analysis, recording or settings reset.

## CC-011 — Reproducible release gates

- Lane: Luna / Max.
- State: `decomposed`.
- Dependencies: CC-001, CC-005.
- Objective: documented local commands and CI-ready scripts for Debug test build, focused unit suites, Release build, bundle allowlist, privacy manifest and true UI smoke.
- Ownership: new scripts/config/docs selected after audits; no product behavior.
- Acceptance: a clean checkout can run gates with deterministic pass/fail and without relying on generated files in the developer's home directory.

### CC-011A — App privacy manifest and validation

- Lane: Luna / Max after CC-013A.
- State: `accepted`.
- Ownership candidate: one app-owned `PrivacyInfo.xcprivacy`, focused validation script/tests and exact target membership only.
- Repository evidence: production code uses app-local `UserDefaults`; no app manifest exists; no active analytics SDK, tracking domain or production remote endpoint is configured.
- Required baseline: `NSPrivacyTracking=false`, no tracking domains, app-local UserDefaults category with approved reason `CA92.1`; collected-data declarations must remain evidence-based and must not guess server/provider retention.
- Apple authority: [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files), [required-reason APIs](https://developer.apple.com/documentation/BundleResources/describing-use-of-required-reason-api), [adding a manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk).
- Acceptance: `plutil` validation, Release bundle contains exactly the intended app manifest at its root, UserDefaults reason matches executable use, unknown provider/retention decisions remain blocked rather than encoded as false facts.
- Evidence: worker commit `a49c234`, accepted commit `c1e6646`; app manifest declares tracking false, empty tracking domains/collected data and only UserDefaults `CA92.1`. Sol independently rebuilt Release, validated exactly the root app manifest plus SnapKit nested manifest, and passed positive plus missing-root/wrong-reason/unexpected-extra fixtures.

### CC-011B — Deterministic build and bundle gate script

- Lane: Luna / Max after CC-002 and CC-011A.
- State: `accepted`.
- Objective: one documented command produces Debug test build and Release build, validates privacy manifests, checks the release allowlist/denylist, reports material size contributors and fails on DeviceBenchmark, GGUF, unknown model/media families or missing acknowledgements.
- Acceptance: a clean checkout and a deliberately contaminated checkout produce deterministic pass/fail; output paths stay under an explicit derived-data root.
- Evidence: worker commit `1223e01`, accepted commit `f56b7b7`. Public command `scripts/run_release_gates.sh --derived-data-root <explicit-root>` owns only a validated child and runs privacy self-tests, Debug `build-for-testing`, Release build, exact bundle/acknowledgement/provenance/size validation and six copied-app contamination fixtures. Sol independently passed the full command on clean HEAD: Release 71 900 КБ, exactly two privacy manifests, five material contributors, five explicit unresolved provenance blockers and all six negative fixtures.

### CC-011C — Real UI-test target and launch smoke

- Lane: Luna / Max after CC-007/CC-008 commercial shell.
- State: `blocked_by_CC-007_CC-008`.
- Objective: implement the target/file-membership/scheme packet from CC-005 and replace the unit-hosted pseudo-UI smoke with true process-launch tests.
- Acceptance: Camera Coach default launch, permission-state launch arguments, both orientations and Scene Mode entry run in a separate UI-test process.

## CC-012 — Coaching-loop analytics contract

- Lane: Sol defines semantics, Luna / Max implements after UX spec.
- State: `decomposed`.
- Dependencies: CC-008, privacy boundary from CC-003.
- Required events: first verified helpful loop, tip shown/stable/rejected, subject clarification, action detected, verification result, keep-as-is, abstention, record success/failure, Deep Review consent/request/lift/exhaustion, server latency/error/cost and crash/thermal signals.
- Constraints: no raw media or hidden identifier by default; event properties must not claim causality the client cannot observe.
- Acceptance: schema is versioned, testable, privacy-mapped and sufficient for subscription-versus-credits decision after beta.

### CC-012A — Coaching-loop event contract inventory

- Lane: Luna / Max audit; Sol accepts semantics before source implementation.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/coaching-loop-event-contract-inventory.md`.
- Objective: map every accepted/proposed Coach state and observable transition to a low-cardinality, privacy-safe event contract centered on the first verified helpful loop.
- Constraints: no raw media, transcript, free-form user text, hidden persistent identifier, provider/region/retention/legal invention or causal overclaim.
- Acceptance: exact event/property dictionary, deterministic activation derivation, source/test seams, negative privacy tests and bounded Luna implementation slices are all repository-grounded.
- Evidence: worker commit `2c75c53`, accepted commit `7a7c55b`, `docs/implementation/audits/coaching-loop-event-contract-inventory.md`; 12 existing instrumentation owner families, 59 active proposed events, 63 properties and 14 explicit blocker/decision rows. The derived activation event remains unavailable until an observable action seam and independent before/after verifier exist.

## CC-013 — Dependency and provenance remediation

- Lane: Luna / Max for bounded dependency mechanics; Sol/owner for provenance and keep/replace decisions.
- State: `decomposed`.
- Dependencies: CC-004.
- Objective: every executable third-party SDK/framework/model/media family is either supported by concrete release evidence or excluded/replaced.

### CC-013A — Remove ARVideoKit and update SnapKit privacy support

- Lane: Luna / Max.
- State: `accepted`.
- Repository evidence: no production `import ARVideoKit`, `RecordAR` or `RenderAR` call site exists; current SnapKit 5.6.0 has no `PrivacyInfo.xcprivacy`.
- Decision: remove unused ARVideoKit from app dependency graph; update both SnapKit declarations to 5.7.1, whose official release states CocoaPods privacy-manifest support.
- Apple authority: SnapKit appears in Apple’s [SDKs requiring a privacy manifest and signature](https://developer.apple.com/support/third-party-SDK-requirements/).
- Ownership: `Podfile`, `Podfile.lock`, generated CocoaPods workspace/project/support/acknowledgement state only; no app feature source.
- Acceptance: no ARVideoKit link/embed/copy input remains; SnapKit 5.7.1 manifest is present in the built framework/bundle privacy report surface; acknowledgements match; Debug/Release builds and focused camera tests pass.
- Evidence: worker commit `3a7731f`, accepted commit `c4275da`. Debug build-for-testing, Release build and 7/7 `CameraManagerLifecycleTests` passed; Sol independently rebuilt Release on main (71 848 КБ) and confirmed `Frameworks/SnapKit.framework/SnapKit_Privacy.bundle/PrivacyInfo.xcprivacy` plus the absence of ARVideoKit, DeviceBenchmark, Models and GGUF.

### CC-013B — Model/framework provenance decisions

- Lane: Sol/owner decision, then bounded implementation.
- State: `blocked_by_provenance_owner_decisions`.
- Scope: `llama.xcframework`, GGUF release candidate, `compact_neural_evidence_net`, DETR and NIMA.
- Acceptance: each retained component has exact upstream source/checkpoint, conversion/build recipe, checksum and applicable licence/NOTICE evidence; otherwise its consumer and bundle payload are excluded or replaced.

#### CC-013B1 — llama framework technical provenance

- Lane: Luna / Max, Sol verification and acceptance.
- State: `in_progress`.
- Task: `01a00603-9514-7ea0-81f3-21361862bc87`.
- Scope: exact upstream URL/commit, build recipe metadata, sorted file-hash record, MIT notice evidence, offline validator and contamination-style fixture tests for `Frameworks/llama.xcframework`.
- Boundary: technical identity and reproducibility may become complete; legal/redistribution owner approval, GGUF selection and all Core ML keep/replace decisions remain open. The task must not claim App Store readiness.

#### CC-013B2 — Exclude unproven third-party Core ML from minimal RC

- Lane: Sol decision packet, owner acceptance, then Luna / Max implementation.
- State: `proposed_for_owner_acceptance`.
- Decision: Camera Coach RC ships without DETR object-aware labels, NIMA aesthetic score and compact neural fusion. Apple Vision subject/saliency and deterministic critique remain production signals; absence is represented as unavailable, never fabricated zero/positive confidence.
- Evidence: DETR and NIMA live below `Multitool2Module/Models/CoreML`, compile to app-root `.mlmodelc` and are currently required by the Release validator. The absent compact model already defaults unavailable. DETR has a no-crash nil fallback but an insufficiently proven output/confidence contract; NIMA nil/zero/fallback semantics can change preserve/correct decisions inconsistently, and a thrown Vision request can omit its callback and leave pause analysis waiting indefinitely.
- Ownership after acceptance: exact two model exclusions in `project.pbxproj`; explicit nil/off production dependencies in `AnalysisPipeline.swift`; zero-Core-ML Release allowlist and DETR/NIMA/compact contamination fixtures; focused presentation/domain/neural/fusion/critique tests.
- Non-goals: replacement model search, network inference, provenance/legal approval, new advice semantics or removal of Apple Vision/saliency.
- Acceptance: default pipeline requests none of the three models; missing aesthetic/object/neural signals remain unavailable; hard deterministic technical advice is not suppressed by fake scores; Vision subject/saliency paths survive; Release contains zero `.mlmodelc`/`.mlpackage`; focused suites and full release gate pass.
- Owner gate: accept the trade-off that minimal RC has no object-aware DETR labels, no model aesthetic score and no neural fusion. If object-aware coaching is mandatory, DETR needs a separate provenance, output-contract and calibration program instead of this slice.

### CC-013C — Product media provenance or replacement

- Lane: Sol design packet, Luna implementation, owner approval.
- State: `blocked_by_asset_owner_decisions`.
- Scope: material app icon/logo/background images and Person/Circle USDZ assets.
- Acceptance: source/creation/export and permission record per retained asset, or provenance-cleared replacement plus archive allowlist proof.

#### CC-013C1 — Circle source/export technical linkage

- Lane: Luna / Max, Sol verification and acceptance.
- State: `in_progress`.
- Task: `01a00603-9514-7ea0-81f3-2140ad032657`.
- Scope: machine-checkable hashes and shared identifiers linking tracked `Circle.rcproject` to runtime `Circle.usdz`, plus offline validator and fixture tests.
- Boundary: the packet must preserve the runtime asset, must not invent a deterministic export command, author or rights claim, and must leave creator/rights approval, Person provenance and image-family provenance open.
