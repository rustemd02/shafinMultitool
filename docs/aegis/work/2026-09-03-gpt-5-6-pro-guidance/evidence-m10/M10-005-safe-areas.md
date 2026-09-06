# M10-005 — safe areas and display geometry

Status: **closed on the current store**.

Layouts derive from safe area, size class, window size, and container
geometry: `SETLayoutProfile.resolve(container:accessibilityType:)` branches
on the live container (narrow/standard/wide), `SETSafeInsets` flows into
placement solvers, the shell forwards route-aware orientation masks, and
the overlay reads canvas size from its geometry proxy.

One violation found and fixed: `ARLiveAnalysisStatusChip` sized itself
from `UIScreen.main.bounds.width` (deprecated, blind to windowing and
size class). It now fills its caller-provided container width
(`liveHintPanel(size:)` already constrains to 34% of the live size).
Grep-verified: no `UIScreen.main.bounds` dimension read remains on
production paths (the single `UIScreen.main.scale` left in the legacy
CameraScreenModule is a pixel-density factor, not a layout dimension, and
that module is outside the SET OS production surface).

Verification: build clean; overlay presentation lane stays green
(`CameraOverlayUXPresentationTests`, rerun in M11-001 lane context).
