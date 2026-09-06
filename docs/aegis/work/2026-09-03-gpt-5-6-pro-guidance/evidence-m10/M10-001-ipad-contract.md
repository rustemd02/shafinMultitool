# M10-001 — iPad platform contract

Status: **closed on the current store**.

Locked in `docs/implementation/ipad-platform-contract-v1.md`: minimum
iPadOS 17.0, universal binary (families 1+2, no compatibility mode), all
four orientations, fullscreen-only windowing (no Split View claim), same
owners on both idioms (layout-metrics branches only), 320pt minimum
camera/AR window with honest unavailable state below it, orientation
behavior through the canonical owners.

Verification: `iPadPlatformContractTests` 4/4 against the built product
Info.plist on permitted iPhone 17e (`/private/tmp/m10-001-tests.xcresult`).
Device windows remain M13.
