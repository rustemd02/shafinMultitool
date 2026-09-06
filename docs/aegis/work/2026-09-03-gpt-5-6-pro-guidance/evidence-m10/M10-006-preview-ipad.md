# M10-006 — Camera preview iPad

Status: **closed on the current store**.

Subject boxes, tap selection, target markers, and the occlusion solver
share the canonical aspect-driven transforms (M2-002/M2-003): normalized
geometry maps consistently across iPhone and iPad canvases without
device branches. `iPadOverlayGeometryTests` 3/3 pins box containment on
five representative canvases (iPhone portrait/landscape, iPad 4:3/3:4,
split-view fraction), slop scaling, and wide/compact profile resolution.
Physical iPad rendering remains M13.
