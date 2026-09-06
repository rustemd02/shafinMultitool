# M5-021 — background recovery (local half)

Status: **local half closed; backend poll/resume half inherits the M5-025
external block**.

## Closed locally

- **Background checkpoints request ID + draft.** Teardown publishes
  `.cancelling` under the live request UUID+epoch and persists the snapshot
  (`buildCurrentProject` carries `sceneDescription` draft + all workspace
  state) through the delegated persistence owner.
- **Foreground restores recoverable state, creates no job.** Opening the
  persisted project restores the draft into the editable `.input` phase
  with `requestID == nil` — proven by
  `testBackgroundTeardownCheckpointsDraftAndForegroundRestoresEditableInput`.
- **No automatic new job** is structurally expressible: `generateScene`
  requires an explicit submit through the single-shot state machine.

## Explicitly remaining (external)

Foreground resume of backend polling (`create/poll/clarify/cancel` job
lifecycle) requires the M5-025 production generation client, which is
EXTERNAL-BLOCKED on a live backend provider. The local contract above is
the complete client-side half.
