# Camera Coach: fullscreen navigation correction

## Owner decision

The owner rejected the permanent three-section bottom rail because it consumes too much of Camera Coach's live frame. This supersedes the `2026-08-17-camera-coach-snapkit-shell.md` rail geometry and invalidates its visual acceptance. The accepted route-safety mechanics remain valid; only its presentation/navigation chrome is rejected.

## Product contract

- Camera Coach is fullscreen and camera-first. It has no persistent tab bar, bottom rail or three-way section switcher.
- The Camera route exposes exactly one compact, 44×44 minimum, top-centre `Сцены` mode control (`square.stack.3d.up`) in the existing restrained SnapKit/UIKit instrument language. It is an affordance, not a floating capsule, card, glass surface or miniature dashboard.
- When Scene Mode is active, that same control becomes `Камера` (`camera.fill`) and returns to the Camera route after the existing awaited teardown. No second global navigation control is added.
- `История` is not shown in permanent camera navigation while it has no persistent results. The retained internal route may remain for a future result-summary entry, but no discoverability, fake content, paywall teaser or empty third tab is allowed now.
- The compact control occupies only its own 44×44 hit target in the top safe area; it does not reserve a bottom content region or reduce the Camera child viewport. It must not overlap existing `OverlayView` controls on portrait or landscape.
- The shell remains the canonical owner of selected route, async teardown, blocked rollback, coalescing and orientation forwarding. The new visual control emits intent only; it never constructs routes or optimistically changes selected state.
- Design remains anti-VibeCode: no system `UITabBar`, full-width rail, floating pill, card grid, decorative blur/glass, gradients, heavy shadows, neon, fake AI decoration, oversized marketing text or delayed ornamental animation.

## Evidence correction

The rail's 6/6 UI-smoke and four attachment evidence are historical functional evidence only. They are not valid visual acceptance: the two claimed landscape PNGs were 1206×2622 portrait images with content/rail rotated sideways. The DEBUG UI test root used a plain `UIHostingController`, unlike the production `CommercialCameraCoachHostingController` orientation policy. This must be corrected in the new implementation task and in the tracker without erasing historical records.

## Implementation packet

1. Remove `CommercialShellSectionSwitcher`, every bottom-child constraint and every permanent Camera/Scenes/History selector from production and tests. Do not reintroduce `UITabBar`.
2. Add one small isolated SnapKit/UIKit `CommercialShellModeControl` (or equally narrow existing-owner extension). It owns visual/accessibility state and an intent callback only. Its identifiers are `commercial-shell-open-scenes` and `commercial-shell-return-camera` according to rendered route.
3. In `CommercialShellViewController`, anchor every active child to all shell edges; overlay the mode control at the top safe-area centre, above the child. Render Camera → open-scenes; Scene → return-camera; no displayed permanent History entry. Lock the control while an existing transition/teardown is in progress; retain visual route truth after a blocked release.
4. Reuse the production Camera hosting-controller orientation policy in the DEBUG UI-test root. Strengthen UI tests to prove usable landscape geometry and attach correct portrait/landscape artifacts. A landscape artifact must have width greater than height and visually show readable upright Camera/Scene chrome.
5. Add unit/UI tests for the compact control, preservation of existing route invariants, no lost child viewport and no persistent History affordance. Update tracker wording to mark the rail invalidated and fullscreen compact-mode implementation as the active visual slice.

## Acceptance

- Camera screenshot shows the full bottom live frame: no shell-owned bottom chrome or child bottom inset.
- Top compact mode control is readable, 44×44, accessible and does not overlap existing Camera Coach controls in portrait or landscape.
- Scene entry/return preserves the route state-machine behavior; blocked teardown does not change its displayed visual state.
- Camera portrait and Camera/Scene landscape XCTest attachments are physically landscape where claimed (`width > height`) and visually upright. Inspect them before marking the slice accepted.
- Focused routing/control tests, real UI smoke and generic build-for-testing pass; unrelated full-suite and physical-device/release/legal gates remain outside this slice.

## Execution ownership

One separate user-visible project-local `gpt-5.6-luna`, `thinking=max` chat implements this packet with no hidden agents. The main chat performs only tracker work and one bounded acceptance review.
