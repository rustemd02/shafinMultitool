# M11-008 — iconography

Status: **closed on the current store**.

- 14 distinct SF Symbols, all functional (no decorative novelty): each
  icon sits inside a labeled button or a labeled status container.
- Decorative glyphs inside labeled controls carry `accessibilityHidden`
  (caption markers, hint icons, chevrons, trash glyphs next to text,
  arrow glyphs whose action text carries meaning). Interactive icon-only
  buttons expose labels (`generator_back_button`, `camera_coach_close`,
  `scene_cell_delete` — the last added in this task).
- RTL/mirroring: glyphs are direction-neutral except chevrons, which
  follow the existing mirrored display transform (M2-003 owner).
- Provenance: SF Symbols (system, no license burden) + two design
  textures (M12-038 manifest).

Verification: build clean; audit script above run to zero true misses
(4 remaining hits are parent-labeled, verified by hand).
