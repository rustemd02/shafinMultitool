# Camera Coach — first-value onboarding and camera permission

## Goal

Ship the first usable Camera Coach path defined by S00–S04 of
`docs/implementation/ux/camera-coach-state-spec.md`: a new user sees a concise
local-value introduction, asks for camera access only after tapping the one
primary action, and receives an honest recovery state when access cannot be
used. A returning user with usable access enters the existing live Camera Coach
without a duplicate camera/session owner. This is a production behaviour slice,
not a mock onboarding or a visual reskin.

## Architecture

`SystemPermissionClient` remains the only system-permission adapter. A new
Camera Coach entry-flow presentation owner maps only the existing
`PermissionSnapshot(camera)` plus the persisted "intro seen" flag into the
product states. `ContentView` composes that entry flow before `OverlayView`.
`OverlayView` remains the sole existing live-camera presentation and starts its
existing `CameraViewModel` only after the entry flow is `.ready`.

There must be no second `CameraManager`, `CameraViewModel`, `AVCaptureSession`,
permission API call, camera-preview placeholder, route shell, tab bar, or
global application delegate state introduced by this work. The commercial shell
continues to own route activation/deactivation; the entry flow only gates the
Camera Coach child it already builds.

## Tech stack

Swift 6 concurrency, SwiftUI, UIKit's existing `openURL` bridge, AVFoundation
through `SystemPermissionClient`, existing XCTest unit target and the real
`shafinMultitoolUITests` process target. The Xcode project uses synchronized
groups, so source/test files below must be created under the indicated folders
without editing `project.pbxproj` unless compilation proves otherwise.

## Baseline / authority refs

- Product promise and permission timing: `docs/app-store-product-plan.md:285-290`,
  `:376-381`, `:601-611`.
- Approved state semantics: `docs/implementation/ux/camera-coach-state-spec.md`
  S00–S04 (`:173-216`) and the anti-vibe rules (`:560-590`).
- Existing permission boundary: `shafinMultitool/Services/Permissions/PermissionContracts.swift`
  and `SystemPermissionClient.swift`.
- Existing Camera Coach composition and lifecycle: `ContentView.swift`,
  `OverlayView.swift`, `CameraViewModel.swift`,
  `CommercialShellRouteComposition.swift`.
- Persistent visual policy: `docs/aegis/plans/2026-08-17-camera-coach-fullscreen-navigation.md`.

### BaselineUsageDraft

- Required baseline refs: the six refs above.
- Acknowledged before plan: all six; current source was inspected at `store`
  HEAD after `f138107`.
- Cited in plan: all six.
- Missing refs: physical-device permission behaviour and App Store legal/privacy
  declarations; these are verification/release gates, not an excuse to fake UI.
- Decision: continue.

### Requirement Ready Check

- Requirement source refs: product plan and S00–S04 state spec.
- Goals / user scenario: first launch → useful local explanation → intentional
  camera request; returning permitted user → live coach; denied/restricted or
  unavailable user → truthful recovery.
- Acceptance / verification refs: state spec S00–S04, Gate B and Gate E of
  `docs/implementation/PRODUCTION_ACCEPTANCE.md`.
- Open blocker questions: exact physical-device screenshots and final localized
  Info.plist wording remain later release evidence; neither changes this
  interaction contract.
- Decision: ready.

### TDD Route

- Mode: off
- Decision: skipped
- Strict authority: not applicable
- Test posture: post-change focused regression plus true-process launch states
- Reason: no explicit strict-TDD decision exists.
- Verification: focused unit tests, true UI-test state assertions, generic
  iOS Simulator build-for-testing, source/diff and visual review.

## Compatibility boundary

- An existing user who has already seen the intro and grants camera access must
  retain the current direct transition into `OverlayView` / `CameraViewModel`.
- No persistent scene, camera setting, video, Photos, microphone or Speech
  policy is created or migrated.
- Only `AppPermission.camera` is read/requested. Microphone, Speech and Photos
  are explicitly deferred until their user-triggered recording/dialogue/save
  slices.
- Denied/restricted/unavailable states must never construct `OverlayView` or
  call `CameraViewModel.startAndWait`; no fake camera preview or live indicator
  may be shown.
- Settings is offered only for `.denied`; `.restricted`, unknown and unavailable
  have a truthful explanation and a recheck action only where it can change.
- The old automatic `OverlayView.onAppear` start is retained only as the live
  surface lifecycle. The new parent decides whether the live surface exists;
  it does not add a second start/stop caller.

## Change necessity / existence check

The current `ContentView` always constructs `OverlayView`, whose `onAppear`
starts capture. It cannot show the required pre-request and recovery states.
Documentation or Info.plist copy alone cannot prevent an untimely system
prompt or false camera surface. Source changes are necessary.

`PermissionClient` already provides an async, coalescing, testable system seam;
it is reused. A small `CameraCoachEntryFlowModel` is justified as a presentation
reducer because neither `CameraViewModel` (camera lifecycle) nor
`SystemPermissionClient` (platform status) may own onboarding persistence,
copy/state selection or Settings intent. It is the only new owner and has one
retirement trigger: if a future app-wide onboarding coordinator is adopted,
that coordinator must consume this model's state contract rather than duplicate
permission requests.

## Architecture integrity / complexity

Canonical owners stay separated: platform status/request (`PermissionClient`),
entry state and intro persistence (`CameraCoachEntryFlowModel`), system Settings
open (`CameraCoachEntryView` effect), and live session (`CameraViewModel`).
Putting this logic into `OverlayView`, `SceneDelegate`, or `CameraManager`
would conflate UX, navigation and capture lifecycle. The new model and view are
small dedicated files; do not grow `CameraViewModel` or `OverlayView` with
permission branches.

## Visual contract — blocking acceptance, not decoration

The entry surfaces use the existing dark neutral, restrained camera-instrument
language: clear type hierarchy, one primary text action, real empty space and
functional status. They are not a generic startup landing page.

Forbidden: hero gradients, sparkles, AI imagery, feature-card grids, fake
progress, glass/blur/pill/card treatment, oversized marketing headline,
neon/shadows, generic dashboard metrics, "icon plus label floating in empty
space", default tab/segmented/navigation chrome, bottom rail or a camera mock.
The presence of an SF Symbol is not a visual hierarchy by itself. Screens must
work with Dynamic Type and VoiceOver; iconography is always supplemental to
the text action. A successful test suite without reviewed screenshots cannot
close the visual gate.

## File map

Create:

- `shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryFlowModel.swift`
  — pure, injectable state owner and intro persistence seam.
- `shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift` —
  SwiftUI S01/S02/S03 surfaces and explicit effects.
- `shafinMultitoolTests/CameraCoachEntryFlowModelTests.swift` — deterministic
  permission/persistence/race coverage.
- `shafinMultitoolTests/CameraCoachEntryPresentationTests.swift` — copy,
  accessibility identifier and anti-fake-preview contracts.
- `shafinMultitoolUITests/CameraCoachEntryFlowUITests.swift` — real process
  launch-argument state coverage after the test hook is added.

Modify:

- `shafinMultitool/Multitool2Module/ContentView.swift` — compose one entry
  model and only instantiate the existing overlay in `.ready`.
- `shafinMultitool/Resources/SceneDelegate.swift` only if it needs a
  DEBUG-only deterministic `PermissionClient` selection for the real UI target.
- `shafinMultitoolUITests/UITests.swift` only to share existing safe UI-test
  launch setup; do not reintroduce orientation capture work.
- `docs/implementation/BACKLOG.md`, `STATUS.md`,
  `docs/aegis/work/2026-08-15-camera-coach-release/20-checkpoint.md` and
  `90-evidence.md` only after evidence exists.

Do not edit `CameraManager`, `CameraViewModel`, `OverlayView`, permission
foundation files, commercial shell routes, Scene Mode, Info.plist, product plan,
payment/backend/analytics or the Xcode project unless a compile failure proves
the synchronized group assumption false.

## Tasks

### Task 1 — entry-flow contract and deterministic owner

**Files:** create `CameraCoachEntryFlowModel.swift` and
`CameraCoachEntryFlowModelTests.swift` only.

**Why:** Makes all camera-access decisions explicit and testable before UI can
start capture.

**Implementation:**

1. Define `CameraCoachEntryPhase: Equatable, Sendable` with exactly
   `.resolving`, `.intro`, `.permissionContext`, `.requesting`,
   `.ready`, and `.blocked(CameraCoachCameraBlockReason)`. Define block reasons
   `.denied`, `.restricted`, `.unavailable`, `.unknown`; do not turn
   `.notDetermined` into a failure.
2. Add the minimal injected `CameraCoachIntroStore` protocol:
   `func hasSeenCameraCoachIntro() -> Bool` and `func markCameraCoachIntroSeen()`.
   Provide an app-local `UserDefaults` implementation with one namespaced key.
   The default value is false; no other migration or `UserDefaults` cleanup is
   touched.
3. Create an `@MainActor ObservableObject` initialized with
   `any PermissionClient` and `any CameraCoachIntroStore`. It publishes one
   phase and exposes only `resolveInitialState()`, `openCameraTapped()`,
   `continuePermissionRequest()`, and `recheckCameraAccess()`.
4. On resolve, obtain exactly one camera snapshot. If intro has not been seen,
   publish `.intro` regardless of authorization. After `openCameraTapped`, mark
   intro seen once and map the fresh snapshot: authorized+available → `.ready`;
   notDetermined+available → `.permissionContext`; every other state → the
   truthful blocked reason. `continuePermissionRequest` may call
   `PermissionClient.request(.camera)` exactly once per tap while suppressing
   concurrent duplicate requests; map its returned snapshot identically.
5. Do not request access during construction, `resolveInitialState`, or an app
   lifecycle callback. Recheck reads `snapshot`, never `request`.
6. Tests use an actor/mock `PermissionClient` plus an in-memory intro store and
   prove each mapping, no implicit request, one request after explicit continue,
   duplicate-tap coalescing, return-from-Settings recheck, and no camera request
   for microphone/Speech/Photos.

**Verification:**

```bash
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:shafinMultitoolTests/CameraCoachEntryFlowModelTests test
```

### Task 2 — restrained S01/S02/S03 presentation and ContentView gate

**Files:** create `CameraCoachEntryView.swift` and
`CameraCoachEntryPresentationTests.swift`; modify `ContentView.swift` only.

**Why:** Converts the accepted state machine into an accessible user path while
preventing a permission-blocked user from seeing an empty/fake camera.

**Implementation:**

1. `ContentView.CameraCoachDependencies` gains exactly the dependencies needed
   to construct the entry model; production composition creates one
   `SystemPermissionClient` and one default intro store alongside the existing
   CameraManager/ViewModel. Tests retain an explicit dependency initializer.
2. Hold the entry model as a `@StateObject` at `ContentView` scope. Start one
   `resolveInitialState()` task on appearance. Cancel no camera work there:
   only the live `OverlayView` owns its start/stop lifecycle after `.ready`.
3. Render existing `OverlayView` only for `.ready`; render
   `CameraCoachEntryView` otherwise. A resolving state is neutral and short;
   it contains no progress theatre or access prompt. Do not build a camera
   preview behind S01–S03.
4. S01 uses concrete Russian value copy: title `Снимайте увереннее`, body
   `Camera Coach подсказывает, что улучшить в кадре. Базовый анализ работает
   на устройстве.`, primary `Открыть камеру`. No price, login, subscription,
   feature grid, illustration dependency or Scene-first diversion.
5. S02 has title `Разрешите доступ к камере`, body
   `Камера нужна, чтобы показать кадр и проверить изменение.`, supplemental
   local-processing sentence, primary `Продолжить`. The button calls only
   `continuePermissionRequest`; app UI must never imitate the system alert.
6. S03 distinguishes all blockers in text. Denied: `Доступ к камере выключен`,
   primary `Открыть Настройки`, implemented with `openURL` of
   `UIApplication.openSettingsURLString`; if `openURL` cannot be handled, show
   a short manual Settings instruction without a dead end. Restricted:
   `Доступ к камере ограничен системой`; unavailable: `Камера недоступна на
   этом устройстве`; unknown: `Не удалось определить доступ к камере`.
   Those variants offer `Проверить снова`, not a fake Settings success.
7. Give each phase/root/action a stable accessibility identifier and VoiceOver
   label. All tappable controls are at least 44pt. Build visual layout from
   typography, spacing, safe areas and existing neutral colours only—none of
   the forbidden visual patterns above.
8. Presentation tests assert strings/identifiers, one primary action per state,
   no record/pause/Deep Review controls in S01–S03, no camera-preview type in
   the entry view, and the visual-policy source markers. They do not pretend to
   assess appearance through a snapshot string.

**Verification:**

```bash
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:shafinMultitoolTests/CameraCoachEntryFlowModelTests \
  -only-testing:shafinMultitoolTests/CameraCoachEntryPresentationTests \
  -only-testing:shafinMultitoolTests/CameraViewModelLifecycleTests test
```

### Task 3 — real UI-test hook, evidence and bounded acceptance

**Files:** modify only the DEBUG UI-test composition seam if required, create
`CameraCoachEntryFlowUITests.swift`, then tracker/evidence files named above.

**Why:** Launch arguments must prove the product's process-level state—not a
unit-hosted simulation—without changing Release behavior.

**Implementation:**

1. Reuse the existing `SHAFIN_UI_TESTING=1` DEBUG-only composition. Add only
   explicit launch arguments for deterministic camera snapshots
   (`notDetermined`, `authorized`, `denied`, `restricted`, unavailable) and
   intro seen/not seen. The fake client exists only in DEBUG/UI testing and
   cannot compile into or alter Release composition.
2. Test: new-user S01 has one visible `Открыть камеру`; tap it with
   notDetermined reaches S02 before an app-controlled request; an authorized
   returning user reaches the existing Camera Coach root; denied/restricted
   renders the distinct S03 text and no record/pause control. Do not automate
   Settings app, system permission alert or real hardware permission.
3. Capture portrait screenshots for S01, S02, denied and live ready; capture
   landscape only if the host yields physically upright readable content. If
   the existing iOS 26.5 capture defect reproduces, record it as host evidence;
   do not claim visual completion from rotated/split attachments.
4. Inspect every real PNG manually against the visual contract. Reject any
   generic onboarding template, cards/pills/glass/blur, empty decorative symbol,
   excessive chrome, default tab/navigation or interrupted camera-first rhythm.
5. Run focused UI class and generic no-sign `build-for-testing`; update the
   tracker from evidence only. Commit one coherent, tested slice, leaving
   record/microphone/Photos/Speech and physical-device validation open.

**Verification:**

```bash
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:shafinMultitoolUITests/CameraCoachEntryFlowUITests test
xcodebuild -workspace shafinMultitool.xcworkspace -scheme shafinMultitool \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO \
  build-for-testing
git diff --check
```

## Risks / retirement / non-goals

- System alerts and Settings outcomes are OS-owned; only app state before and
  after them is claimed/tested.
- The iOS 26.5 screenshot-orientation defect is not fixed here. It blocks only
  unverified landscape visual acceptance, never authorizes fake evidence.
- CameraManager's own start errors stay under S19/recovery work; this slice
  does not mislabel a failed capture setup as a permission denial.
- Recording/microphone, Photos save, Speech, Deep Review consent, backend,
  analytics emission, Scene Mode redesign, StoreKit, physical-device QA and
  final privacy/legal policy are separate release gates.
- If the flow is rolled back, remove only the new entry-flow composition and
  files; the existing live camera owners remain untouched. Do not preserve a
  parallel automatic permission path as a fallback.

## Execution readiness view

- Intent Lock: first camera access is requested only after a user understands
  the immediate local Camera Coach value and taps a specific action.
- Scope Fence: S01–S04 camera only; no other permission or monetisation path.
- Baseline Lock: approved product plan/state spec, existing permission client,
  current Camera Coach composition and anti-slop visual policy.
- Approved Behavior: intro → request context → system request → live or
  truthful blocked recovery; returning allowed user skips intro and enters live.
- Owner / Contract Constraints: one PermissionClient and one camera/session
  owner; no direct AVFoundation request outside the existing client.
- Compatibility Boundary: existing permitted users and saved scenes remain
  compatible; only a new namespaced intro flag is persisted.
- Retirement Boundary: no automatic OverlayView start path outside `.ready`.
- Task Batches: contract; presentation/composition; process UI evidence.
- Test Obligations: focused unit, real UI target, generic build, source/diff,
  screenshots and manual visual inspection.
- Review Gates: exact diff/file ownership, no Release test hook, anti-slop
  review; blocked host capture remains blocked.
- Drift / Rewind Rules: if implementation needs CameraManager/route/permission
  foundation changes or invokes a second permission, revert to the packet and
  re-plan before proceeding.
- Evidence Required Before Completion: test counts/XCResults, build result,
  source inspection, physical screenshot facts and tracker update.
- Advisory Boundary: implementation guidance only; not a completion or legal
  approval.

## Execution route

- Decision: visible Luna / Max thread.
- Evidence: three bounded tasks with explicit single-owner files and no hidden
  delegation; user requires a separate visible `gpt-5.6-luna`, `thinking=max`
  executor.
- Fallback: fail closed rather than create a hidden, Sol, Terra or inherited
  worker.
- User confirmation required: no.
