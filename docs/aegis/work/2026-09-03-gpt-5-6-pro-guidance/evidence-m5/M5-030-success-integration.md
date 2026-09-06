# M5-030 — generator success integration

Status: **closed on the current store**.

## Atomic success with provenance

- The success edge is published only after the one-MainActor-block commit
  (model replacement + AR placement + `persistProjectMetadata` + handoff).
- The commit stamps `GenerationProvenance` (generator `scene-generator-v1`,
  model contract `setcompositionnet.v1`, schema `scene-annotation-v1`)
  onto the plan at every construction site: generation commit, beat-edit
  preservation, storyboard actor drags, and marked-object merges (prior
  provenance preserved, never overwritten with defaults). The planner
  service emits unstamped plans; exactly one VM stamp exists per path.
- Legacy projects decode with `provenance == nil` via custom
  `decodeIfPresent` Codable — backward compatible, no silent upgrade.
- The success state links to AR (placed entities) and Storyboard
  (`refreshStoryboardBeatItems` in the same commit) and is recoverable
  through the persisted snapshot + M5-021 reopen path.

## Verification

`GenerationSuccessProvenanceTests` 2/2 on permitted iPhone 17e
(`/private/tmp/m5-030-tests.xcresult`): success carries the exact
provenance triple; legacy JSON decodes nil and round-trips the stamp.
