# windowing-policy-v1 — M10-004 locked windowing policy

Status: **locked policy (v1).**

## Single workspace scene

The app vends exactly one `UISceneSession` role (no multi-window scene
manifest, no `requestSceneSessionActivation` call anywhere — grep-verified):
no second concurrent workspace scene can be created. Background/foreground
lifecycle converges on the single M1-004 owner.

## Resizable windows

Library/Generator/Storyboard are SwiftUI layouts that reflow with their
container; no fixed-size assumptions exist in their view code.

## Minimum active size (Camera/AR/recording)

Camera and AR capture require a minimum 320pt window dimension
(M10-001 contract). Below that the route presents the honest unavailable
state instead of degraded capture:

- the Camera Coach surface reports its presentation as fallback when the
  canvas cannot host the frame (`presentation.isFallback`);
- recording start requires an actual video buffer with positive dimensions
  (M7-005/M7-008 preflight rejects zero-size configurations before any
  writer exists);
- AR readiness requires a real frame with detected planes (M6-005).

A dedicated localized "expand window / go full-screen" recovery string is
not shipped: with `UIRequiresFullScreen = YES` the app cannot be shrunk
below fullscreen on iPad, so the state is unreachable in 1.0. If
multitasking is ever claimed, the recovery string becomes mandatory.
