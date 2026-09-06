# M11-001 — visual authority

Status: **closed on the current store**.

## Checklist audit (`scripts/evidence/check_visual_authority.py`)

Fail-closed grep audit over the 26-file SET OS production surface
(Multitool2Module UI/Shell, SceneGenerator views, CommercialShell,
DesignSystem; legacy SceneModules/CameraScreen/EditScript, Benchmark,
Debug/Performance, Tests/Previews/fixtures excluded by tracker authority):

- palette: ink + warm white present, single `setOrange` cinematic accent —
  no system blue (word-boundary exact, no component false positives);
- typography/spacing: SETTypography/SETSpacing tokens (see existing
  `SETDesignSystemTokenTests` lane);
- marker budget, film mechanics, one-shot event ownership: per-task
  evidence (M2-027…032, M5-018);
- banned: blur/material, shadows, gradients, generic cards, fake
  thumbnails — none in scope.

## Two production violations found and fixed

1. `SETTallyBadge` ran `repeatForever` pulse — now a one-shot settle
   transition on appear (steady state under Reduce Motion).
2. `DirectionArrows` used black drop shadows — replaced with a solid
   scrim disc behind the glyph (no shadow API).

## Verification

Audit script exits 0; `CameraOverlayUXPresentationTests` 25/25 on permitted
iPhone 17e (`/private/tmp/m11-001-tests.xcresult`).
