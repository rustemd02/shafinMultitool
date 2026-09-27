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
- ~~`UIRequiresFullScreen = YES`~~ → **исправлено 2026-09-27 (owner-delegated
  сверка, §19 п.13):** владелец перевёл продукт на native resizable windows
  2026-09-16 (commit `d4815f3`); в `project.pbxproj` во всех четырёх конфигурациях
  стоит `INFOPLIST_KEY_UIRequiresFullScreen = NO`, и контрактный тест
  `iPadPlatformContractTests.testWindowingDoesNotUseScaledFullScreenCompatibilityMode`
  требует `UIRequiresFullScreen == false` («master plan §3.8 requires resizable
  iPad layouts with native control sizes»). Split View / Slide Over больше не
  исключены самим фактом конфигурации; мультитаскинг-поведение проверяется
  только физически (DEV-011) и не заявляется здесь.

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
