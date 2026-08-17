# Camera Coach: SnapKit section switcher

## Goal

Replace the generic system `UITabBar` in the production Camera Coach shell with a deliberately restrained, SnapKit/UIKit section switcher that feels like a cinematography instrument rather than a template app. Preserve the accepted Camera-first, single-active-route and awaited-teardown mechanics exactly.

The owner has explicitly accepted this visual direction: reuse and refine the existing SnapKit/UIKit design language; create a structured, high-quality “wow” through hierarchy, live-frame composition, typography, alignment and meaningful feedback; do not use VibeCode patterns.

## Product and visual contract

### Required outcome

- Camera remains the default and only eagerly constructed route.
- `Камера`, `Сцены`, `История` remain the only three sections. `Сцены` remains secondary and landscape-only through its existing route policy. `История` remains accessible even when empty and must not invent stored results, a paywall, a progress graph or a promise of persistence.
- Replace the visible system tab bar completely. There must be no hidden or compatibility `UITabBar` left in the shell.
- New chrome is an opaque, full-width, bottom safe-area rail. It belongs to the shell, never floats above the live frame as a capsule and never overlaps Camera Coach controls.
- It uses three equal-width control cells: SF Symbols `camera.fill`, `square.stack.3d.up`, `clock`; Russian labels `Камера`, `Сцены`, `История`.
- Selected state: `systemYellow` symbol and label, semibold type, and a thin 2 pt yellow top indicator. Unselected state: restrained secondary white/gray, regular type. State is never conveyed only by color: selected controls expose `.selected` accessibility trait.
- The rail is a quiet opaque near-black surface with a restrained top separator. It has no gradients, glass/material backdrop, blur as navigation chrome, floating pill/card shape, deep shadow, neon glow, emoji, decorative badge, fake AI treatment or gamified progress.
- The app’s “wow” comes from clean negative space around the live frame, exact icon/text alignment, contrast and a direct state transition; it must not consume camera space with decoration.
- Each control has an effective hit target of at least 44 by 44 points; content uses Dynamic Type and must not clip in either orientation. The rail may grow vertically for accessibility text instead of using a hard height that clips labels.
- During an actual route transition or permanent teardown, all section controls are non-interactive and the currently active section remains visibly selected. A blocked teardown keeps the old route and visual selection. A rapid tap is still coalesced by the shell to the final requested section.
- Section selection has one restrained, functional feedback action (selection haptic only when a real selection request is accepted); it must be no-op if user has Reduce Motion/Haptics disabled by the system. Do not add a timer, delayed “satisfying” animation or automatic movement. For real selected-state changes use a 180–260 ms system-eased crossfade; Reduce Motion is an immediate state update or crossfade without spatial motion.

### Explicit anti-VibeCode checklist

The implementation is rejected if it introduces any of the following in the shell or History empty state: generic default `UITabBar`; arbitrary floating capsule; card grid; excessive rounded rectangles; decorative blur or stacked glass; gradient-everything; large marketing headline; generic dashboard; arbitrary all-caps; multiple competing primary actions; hard shadow; neon/AI glow; emoji/novelty icon; fake data, fake precision, fake history or paywall teaser; decorative delayed animation; a newly invented parallel visual system.

## Architecture and compatibility boundary

### Existing owners to preserve

- `CommercialShellViewController` is the only owner of `CommercialSection`, route construction, active child containment, lifecycle teardown, pending-selection coalescing, selected-route truth and orientation forwarding.
- `CommercialRoute` implementations and `CommercialShellComposition` retain all route behavior. Do not edit `SceneDelegate`, `ContentView`, Camera Coach analysis/session code, Scene Mode routers, recorder or persistence.
- Existing visual references are `SceneModules/CameraScreenModule/View/CameraScreenViewController.swift` (dark, compact functional controls), `ScenesOverviewModule/SOViewController.swift` (calm dark composition and white type), and current repository `SnapKit` usage. Reuse their functional language; do not copy their old fixed-frame, hard-shadow, 16:9-only or Scene-first constraints.
- `OverlayView` owns Camera Coach’s bottom controls and may ignore safe-area internally. Therefore the new shell rail must own a separate bottom layout region and child routes must be constrained above that region.

### New narrow component

Add `shafinMultitool/CommercialShell/CommercialShellSectionSwitcher.swift`.

`CommercialShellSectionSwitcher` is a `@MainActor final class` UIKit view. It may own only visual controls, accessibility and a selection-intent callback. It must not know about `CommercialRoute`, construct a controller, retain route/session state, decide a selection outcome, or perform teardown.

Public/internal surface needed by the shell and focused tests:

```swift
@MainActor
final class CommercialShellSectionSwitcher: UIView {
    var onSelectionRequested: ((CommercialSection) -> Void)?
    private(set) var selectedSection: CommercialSection
    func render(selectedSection: CommercialSection, isInteractionLocked: Bool)
}
```

The exact access control can remain module-internal; do not make visual implementation details public only to satisfy tests. Give every button a stable accessibility identifier:

- `commercial-shell-section-camera`
- `commercial-shell-section-scenes`
- `commercial-shell-section-history`

Set the rail’s identifier to `commercial-shell-section-switcher`. The button accessibility label is its Russian visible label. Its `accessibilityValue` is `Выбрано` for selection and `Не выбрано` otherwise. `accessibilityTraits` includes `.button` and, when selected, `.selected`; no disabled trait except while interaction is genuinely locked.

Use SnapKit in this component for the rail, equal-width stack and touch layout. A `UIStackView` with three actual `UIButton`s is suitable. Do not add a separate token library, theming engine or a custom navigation abstraction for this one shell.

## TDD route

**Skipped as strict TDD.** The repository has an accepted async route state machine and a real UI test target; the safely bounded path is to first add focused rendering/event tests for the isolated switcher, then adapt existing contract tests while integrating it. The implementation is not accepted until all specified focused tests and the existing launch smoke pass.

## Implementation tasks

### Task 1 — Build the isolated visual control and its contract tests

**Files owned:**

- Add `shafinMultitool/CommercialShell/CommercialShellSectionSwitcher.swift`.
- Add `shafinMultitoolTests/CommercialShellSectionSwitcherTests.swift`.
- Update the Xcode project only if the existing project uses explicit file membership and the new source/test files otherwise fail to compile. Do not alter dependency versions or build settings.

**Implementation details:**

1. Build an opaque near-black root rail; pin internal content to safe layout margins using SnapKit. The rail extends to the shell’s bottom edge; its controls live above the home-indicator inset.
2. Add a 1 physical-pixel / visually thin top separator in a low-contrast white alpha. Do not use a shadow, blur, gradient or rounded outer container.
3. Build three equal-width controls. Each control has vertically aligned symbol and text with enough vertical/horizontal inset to yield ≥44 pt interactive area. Configure type via Dynamic Type (`UIFont.preferredFont(forTextStyle:)`) and enable `adjustsFontForContentSizeCategory`.
4. Keep all visual data (section, Russian title, SF Symbol, accessibility ID) in one private deterministic mapping. Do not leave English labels in production UI.
5. `render` must be idempotent. It updates selected/unselected color, font/weight, indicator visibility, traits/value, and `isUserInteractionEnabled`; it must not send callbacks, create routes or mutate a shell.
6. A button tap calls `onSelectionRequested` with exactly its own section once, and does not optimistically change visual selection. The parent shell confirms the selection after its existing transition logic succeeds.
7. When the interface is configured for Reduce Motion, avoid spatial animation. Otherwise only animate a confirmed selected-state change using a 180–260 ms system crossfade. Never delay selection or use infinite/repeating animation.

**Focused test cases:**

1. Default render exposes exactly three controls in Camera/Scenes/History order, with the exact Russian labels, SF Symbol identities and stable IDs.
2. Camera render reports Camera selected (including accessibility trait/value), while Scenes and History report not selected.
3. Rendering Scenes after Camera changes only display state; it sends no callback.
4. A Scenes control tap emits `.scenes` exactly once and does not itself change the selected section.
5. `isInteractionLocked: true` disables all three controls without clearing the current selected state; a later unlocked render restores interaction.
6. Every control remains at least 44×44 after `layoutIfNeeded()` in a portrait-sized host and a compact-landscape-sized host. The test must use constraints/layout, not a screenshot assumption.
7. The view contains no `UITabBar`, `UIVisualEffectView`, `CAGradientLayer`, shadowed outer card or rounded outer rail. Test only direct structural conditions that are stable and meaningful; do not hard-code private UIKit hierarchy.

**Task-1 acceptance:** focused test class passes and generic project build-for-testing compiles the new source. No route test is weakened or skipped.

### Task 2 — Replace only shell chrome while preserving route semantics

**Files owned:**

- Modify `shafinMultitool/CommercialShell/CommercialShellViewController.swift`.
- Modify `shafinMultitoolTests/CommercialShellRoutingTests.swift`.
- Modify `shafinMultitoolTests/CommercialShellLaunchCompositionTests.swift` only for affected public UI assumptions; retain launch/route assertions.
- Modify `shafinMultitoolUITests/UITests.swift`.
- Modify `shafinMultitool/CommercialShell/CommercialShellRouteComposition.swift` only to correct the honest History empty-state copy and visual base as specified below.

**Shell integration details:**

1. Remove `UITabBar`, its delegate conformance, `item(for:)`, English title/image helpers and every system-tab selection write. Do not preserve it off-screen or as an accessibility shim.
2. Replace the `tabBar` property with a `sectionSwitcher` property exposed only as far as existing focused tests need. Construct/configure it in `viewDidLoad`, set its callback to `requestSelection(_:)`, add it above child views, and anchor it leading/trailing/bottom to the shell view. Use the new switcher’s top anchor as the active child’s bottom constraint.
3. Set shell root background to the same quiet near-black visual base used by the rail, not `.systemBackground`, so route changes never reveal a white generic flash. Do not impose this background on child routes that own their own visual context.
4. At every existing place that previously set `tabBar.selectedItem` or `tabBar.isUserInteractionEnabled`, call one narrow helper such as `renderSectionChrome()`. That helper is the only shell-to-switcher presentation boundary and passes `selectedSection` plus `isTearingDown || isTransitioning`. Do not duplicate display-state calculations across transition branches.
5. Preserve route truth exactly: no selection visual change before `installRoute(for:)` completes; blocked deactivation returns to the retained section; `finishTransition()` unlocks only when appropriate; permanent release locks controls; selection before load still works. Keep the accepted coalescing behavior unchanged.
6. Preserve one active child and exact awaited teardown ordering. Do not refactor `performTransition`, `performRelease`, task ownership, route factory or orientation behavior beyond replacing visual synchronization statements.
7. Keep the rail visible in portrait and landscape. In landscape it may be visually compact only if all controls still meet the 44 pt hit target and Dynamic Type constraints; do not hide it simply for visual minimalism.

**History details:**

1. Rename the title to `История` and set message to `Завершённые разборы этой сессии появятся здесь.`
2. Do not add storage, save affordance, fake analysis items, empty-state illustration, premium upsell or button.
3. Keep `isEmptyState == true`, `persistenceAction == nil` and route accessibility identifier behavior.
4. Use the same quiet dark base and white/secondary-white typography without a card container; retain Dynamic Type and centered readable layout.

**Test changes and additions:**

1. Replace current tests’ direct `tabBar` item assertions with assertions on `sectionSwitcher.selectedSection`, interaction state and the exact stable control identifiers. Do not reduce assertions for laziness, containment, teardown ordering, blocked rollback, coalescing, repeat selection or permanent release.
2. Add a routing test that a blocked transition leaves both shell `selectedSection` and switcher visible selection on Camera and restores interaction.
3. Add a routing test that a transition is visibly locked while the old route waits, then unlocks with the actual selected route after release.
4. Add/retain an honest-History composition test for `История`, exact message, `isEmptyState`, and no persistence action.
5. Update UI smoke tests to find buttons by the three new accessibility IDs, not `app.tabBars`, and assert Camera’s selected state on launch. The existing Scene-library → Camera return journey must keep passing with the new IDs.
6. Add UI test coverage that History is reachable and presents the honest empty state, then Camera remains reachable again. This must run through the production shell, not a mocked visual view.
7. Keep portrait and landscape smoke checks. Add assertions that each camera/scene/history section control exists and is hittable in the tested orientation where the route is available; do not claim physical-device camera behavior.

**Task-2 acceptance:** no production `UITabBar` remains in CommercialShell; no English section labels remain in user-visible CommercialShell/History UI; all existing safety invariants have explicit focused assertions; UI tests use only the new identifiers.

### Task 3 — Visual evidence and tracker reconciliation

**Files owned:**

- Modify `docs/implementation/ux/camera-coach-state-spec.md`.
- Modify `docs/implementation/BACKLOG.md`.
- Modify `docs/implementation/STATUS.md`.
- Modify `docs/aegis/work/2026-08-15-camera-coach-release/20-checkpoint.md`.
- Modify `docs/aegis/work/2026-08-15-camera-coach-release/90-evidence.md`.

**Required documentation changes:**

1. Replace the stale “exact geometry remains pending” wording for CC-007B with the accepted full-width opaque SnapKit/UIKit rail contract in this plan. Do not rewrite the historical note that the old system tab bar was rejected.
2. Record CC-007B as implemented only after Task 2’s tests actually pass. Record exact commit, simulator/device runtime, commands, XCResult path/counts, `git diff --check`, and the non-release-ready boundary.
3. State explicitly that the visual direction does not alter legal/provenance, physical-device, App Store, monetisation or paid-backend gates.
4. Include a concise anti-VibeCode visual evidence checklist rather than declaring “wow” without evidence.

**Visual evidence required:**

1. Capture XCTest attachments/screenshots or equivalent retained simulator artifacts for Camera (portrait and landscape), Scene library (landscape), and History empty state. The screenshots must show the opaque rail, one task hierarchy, readable targets and no collision with camera controls.
2. Inspect the artifacts before marking documentation accepted. A technical UI test pass alone is insufficient for the visual acceptance claim.
3. If reliable screenshot attachment cannot be produced in the current simulator, record that visual evidence is still pending rather than claiming it passed; leave code/test changes intact only if their functional checks pass.

## Required verification sequence

The visible Luna / Max executor runs the narrowest checks first, fixes only failures caused by this slice, then runs the integration checks. It must not conceal pre-existing failures or broaden the change into permissions, Camera Coach SwiftUI redesign, Scene Mode redesign, Core ML or release-gate work.

```bash
set -o pipefail
xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /private/tmp/shafin-cc007b-switcher \
  test \
  -only-testing:shafinMultitoolTests/CommercialShellSectionSwitcherTests \
  -only-testing:shafinMultitoolTests/CommercialShellRoutingTests \
  -only-testing:shafinMultitoolTests/CommercialShellLaunchCompositionTests

xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /private/tmp/shafin-cc007b-ui \
  test \
  -only-testing:shafinMultitoolUITests/CameraCoachLaunchUITests

xcodebuild -workspace shafinMultitool.xcworkspace \
  -scheme shafinMultitool \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /private/tmp/shafin-cc007b-build \
  build-for-testing

git diff --check
git status --short
```

If simulator OS/name differs on this host, query `xcrun simctl list devices available` and use an equivalent current iPhone simulator; document the substitution. Do not turn the unrelated historical full-suite failures into this task’s failure or describe them as fixed.

## Stop conditions and non-goals

- Stop and report rather than inventing a workaround if preserving the 44 pt touch target conflicts with an actual supported landscape size; the product owner must choose between a different rail geometry and a route-specific presentation rule.
- Stop and report if the existing `OverlayView` cannot coexist above the child bottom constraint without losing a primary camera control; do not cover it with an overlay or silently hide shell navigation.
- This plan does not authorize a new onboarding, permission UI, Camera Coach SwiftUI rewrite, Scene Mode redesign, persistence/history implementation, backend, monetisation/paywall, new imagery, model/provenance changes, signing, submission, push or App Store action.

## Execution ownership

Execution must be performed by one separate user-visible Codex project-local chat using `gpt-5.6-luna` with `thinking=max`. It may not create hidden subagents. The main chat’s role is limited to this contract, tracker coordination and one bounded final acceptance review of the reported diff/evidence.
