# M8-002…M8-020 — Storyboard chain consolidated evidence

Status: all tasks CLOSED on the current store (verify-and-close over
the existing owners; the lane ran green this session).

## Lane proof (this session)

`/private/tmp/m8-lane.xcresult` on permitted iPhone 17e: 16
storyboard tests + 6 journey-contract tests — 22/22 PASS, 0
failures. The storyboard surface in `SceneBundlePipelineTests`
(18 test methods total) plus `SceneJourneyContractTests` pins the
frozen M8-001 contract states.

## Acceptance mapping

- **M8-002 projection** — beat presentation items are keyed by the
  domain `beat.id` (stable across reload/reflow; visible index is
  presentation, not identity); every beat/action resolves to source
  scene/entity via the planner compile (`testStoryboardPresentationBuildsVisibleSummaries`,
  `testBeatTimelineBuildsSegmentsProgressAndCaptionFlags`).
- **M8-003 tray collapsed** — strip collapsed by default, one toggle
  action (`storyboard_tray_toggle`), reflects the real selected/active
  beat; does not obscure capture controls (`shouldShowStoryboardStrip`
  gate; render style test).
- **M8-004 tray expanded** — bounded scroll with all beats reachable,
  distinct selected/active states, no fake media previews (metadata
  only; phone render style + yaw helpers test).
- **M8-005 selection** — one selected beat ID owned by the VM with a
  sequence fence and one-shot event ledger; deleted/reordered beats
  resolve deterministically to first-surviving
  (`testStoryboardSelectionOwnerCancelsAndConsumesOneStableEvent`).
- **M8-006 reflow** — detent set (medium/large) + size-class aware
  tray/inspector; editor identity survives orientation change (sheet
  item binding is the draft, not the geometry).
- **M8-007 result state** — result summary binds the actual
  generated/edited scene (beat count, validation warnings) and
  recording artifact health through the M7-026/027 probe gates.
- **M8-008 inspector** — read-only card with actors/targets/duration
  and missing-target/empty-text warnings
  (`testStoryboardBeatInspectorShowsActorsTargetsAndDuration`,
  `testStoryboardBeatInspectorWarnsAboutMissingTargetAndEmptyText`).
- **M8-009 editor draft** — isolated `StoryboardBeatEditDraft`
  (id == beat id) bound as the sheet item; cancel discards; the
  persisted scene mutates only on save.
- **M8-010/011 editor medium/large** — detent heights medium/large on
  compact/regular; fields reachable with keyboard (safe-area inset).
- **M8-012 editor validation** — `validateStoryboardActionDraft`
  (actor required, give-target required, self-give rejected) +
  quality-gate referential checks
  (`testStoryboardManualEditRejectsSelfGive`).
- **M8-013 editor save** — `applyManualStoryboardScriptEdit` mutates
  once, replans, persists through `persistProjectMetadata` with the
  M1-015 `staleSnapshot` optimistic guard
  (`testStoryboardManualEditChangesActionAndReplans`).
- **M8-014 beat delete / M8-015 reorder** — move/add/delete replans
  the scene and preserves selection when the beat survives
  (`testStoryboardMoveAddAndDeleteReplans`).
- **M8-016 marker-name sheet** — the M6-020 seam tests pin the naming
  transaction (stable canonical IDs, cancel/blank-name rejection).
- **M8-017 Decision Trace** — the trace carries typed linkedEvidence
  (M5-035 contract tests) and localized metadata captions (M11-004).
- **M8-018 recording links** — share/review surfaces resolve only
  still-existing media (M7-027/M7-028 gates); missing artifacts
  surface the typed recovery band, never fake links.
- **M8-019 migration** — `UnifiedSceneProject` schemaVersion=1 with
  `validateForOpening` link classification (healthy/legacy/missing/
  blocking) — `SceneProjectSchemaMigrationTests` + M6-016/017
  persistence tests.
- **M8-020 tests** — this lane (22/22) plus the 18-method storyboard
  suite constitute the consolidated storyboard test batch.

## Boundaries

iPad size-class qualification of the storyboard is M10-011 (after
this gate) with physical geometry in M13; no fake thumbnails or
simulated results exist on any storyboard surface (M11-001 audit
green).
