# ipad-platform-contract-v1 — M10-001 locked iPad contract

Status: **locked contract (v1).**

## Minimum platform

- Minimum iPadOS: 17.0 (shared `IPHONEOS_DEPLOYMENT_TARGET` across all
  targets, verified in M0-006).
- Device family `1,2` (iPhone + iPad, universal binary — no iPad
  compatibility mode; the app is native on both idioms).

## Full-screen and resizable behavior

- All four interface orientations declared
  (`UIInterfaceOrientationPortrait/PortraitUpsideDown/LandscapeLeft/LandscapeRight`);
  no iPad-specific orientation restriction exists.
- `UIRequiresFullScreen = YES`: the app does not claim multitasking
  windowing support it has not earned; Split View / Slide Over are out of
  scope for 1.0 and must not be assumed by layout code.

## Feature parity

Camera Coach, Scene Library, Generator, AR workspace, Storyboard, and
recording/playback/share follow the same owners on both idioms. Idiom
branches are allowed only for layout metrics (spacing, rail sizes), never
for behavior forks.

## Minimum camera/AR window

Camera and AR surfaces require a minimum 320pt window dimension to operate;
below that the route presents the honest unavailable state instead of a
degraded capture. (Enforced where the surface is hosted; simulator
evidence only — device windows are M13.)

## Supported orientations

All four orientations on both idioms. Orientation-specific behavior
(transforms, overlays, recording track metadata) goes through the
canonical orientation owners (M2-003, M7-007), never per-screen hacks.
