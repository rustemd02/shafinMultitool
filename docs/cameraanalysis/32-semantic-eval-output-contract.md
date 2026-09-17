# 32. Semantic Eval Output Contract

Status: implementation contract.
Date: 2026-05-22.

This document defines the JSONL shape used to compare Camera Analysis behavior
with `semantic_labels_v1.jsonl`.

## Candidate Output Row

Each output row represents what a candidate system would show for one labeled image:

```json
{
  "record_id": "ca_img_001",
  "filename": "001.jpg",
  "mode": "live",
  "shown": true,
  "live_tip": "Кадр читается хорошо: герой выделен светом и цветом.",
  "pause_summary": "Герой выделен цветом и теплым светом; темнота является стилем.",
  "semantic_actions": ["keep_current_setup"],
  "future_actions": [],
  "confidence": 0.86,
  "source": "oracle_projection",
  "runtime_claim": "label_oracle",
  "trace_ids": []
}
```

## Required Fields

- `record_id`: must match a label record.
- `filename`: must match the label filename.
- `mode`: `live`, `pause`, or `both`.
- `shown`: whether a user-facing tip would be shown.
- `semantic_actions`: closed catalog actions currently expressible by the app.
- `future_actions`: technical/IQA actions that are tracked by eval but not yet part of the current live semantic UI.
- `confidence`: number in `[0, 1]`. For Swift rows this is the normalized
  numeric score attached to the supplied presentation, not an independently
  adjusted evaluation score, established probability or proof of a visible
  percentage on the current product screen.
- `source`: candidate id, for example `proxy_current_limitations`.
- `runtime_claim`: whether this is a real runtime result or proxy/oracle data.

## Multi-Mode Rows

A real app replay may emit two rows for one image:

- one `live` row from `LiveHintPresentation`;
- one `pause` row from `PauseCritiquePresentation`.

The scorer treats this pair as one case result by merging actions, confidence and trace ids for the same `record_id`.

Rules:

- at most one row per `(record_id, mode)`;
- `mode = both` cannot be combined with separate `live` / `pause` rows;
- all rows for one `record_id` must use the same `runtime_claim`;
- the merged row uses `mode = both` internally for scoring.

## Runtime Claim Values

- `label_oracle`: generated from labels for scorer sanity checks only.
- `test_fixture`: deliberately bad generated candidate for tests.
- `not_real_runtime`: proxy baseline. Useful for prioritization, not a performance claim.
- `real_runtime_still_replay`: output was produced by the actual Swift/CoreML camera-analysis path from a still image.

## Swift Producer Contract

The app side now has a typed producer row:

```text
shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift
  SemanticEvalCandidateOutput
  SemanticEvalRuntimeClaim
```

Current mapping:

- `LiveHintPresentation` -> one `live` candidate row.
- `PauseCritiquePresentation` -> one `pause` candidate row.
- `LiveHintPresentation.actionType` -> closed `SemanticActionType` raw values.
- `PauseActionRow.semanticActionType` -> closed `SemanticActionType` raw values.
- `PauseActionRow.actionType` remains the coarse transport/UI action and must not be used as the only source for semantic eval scoring.
- hidden/no-tip state -> `shown = false`, empty `semantic_actions`; separately tracked `future_actions` may remain and do not imply a visible instruction.

### Confidence observations

For Swift presentation rows, canonical `confidence` uses the existing
`ConfidencePresentation.make(...).value` conversion shared with numeric
confidence consumers such as Decision Trace:

- live: `LiveHintPresentation.confidence`;
- pause: `PauseCritiquePresentation.verdictConfidence`;
- no presentation: zero by the existing hidden-row convention. Zero in this
  case does not mean that an observed advice confidence was zero.

The exporter must not add a technical floor, apply scene-specific caps or
promote a score into a target band. Any policy already applied by the
presentation builder remains part of the presentation; exporting it does not
validate that policy or establish probability calibration.

New Swift rows include optional `confidence_evidence`:

| Field | Meaning |
| --- | --- |
| `source` | Exact presentation property above, or `no_presentation`. |
| `context` | `supplied_presentation` or `still_replay_candidate`. |
| `presentation_frame_id` | Frame belonging to the supplied presentation, when present. |
| `critique_verdict_confidence` | Finite post-fusion `CritiqueReport.verdictConfidence`, only when supplied by the producer. |
| `presentation_confidence` | Finite presentation score before the UI's bounded conversion; absent for hidden rows or non-finite input. |

Absent evidence in a historical row is unknown. An absent optional score is
unknown or invalid, never an observed zero. Non-finite observations are omitted
while source/context are retained; finite out-of-range raw scores remain
observable. Canonical confidence still uses the original presentation score
through the existing UI conversion. Non-finite entries in the diagnostic
numeric-feature map are omitted so one invalid debug score cannot break JSON
encoding for the whole row. These fields never infer
critique confidence from an arbitrary debug-feature map. The existing
`debug_numeric_features.verdict_confidence` remains a legacy diagnostic of
the critique stage; it is not the UI score.

`still_replay_candidate` explicitly identifies a presentation produced by
the still-image builders. Live replay bypasses production frame admission,
temporal confirmation, publication and retention; the row is not proof that
the same hint was accepted or displayed during live capture. A caller testing
pipeline retention must export the retained `currentLiveHint`, not a pending
replacement. A caller testing the user's presentation must observe the
selected UI route after its own publication and readiness gates:

- The primary Camera Coach route is `CameraViewModel` →
  `SETCameraCoachProductionView`. Live hints pass through the view model's
  `applyLiveHint`, which can suppress them for analysis/performance state.
  Pause UI requires `isPauseProjectionReady` and an accepted snapshot. Its
  selected critique prefers the value in `pausePresentationState.success`,
  then falls back to `CameraViewModel.pauseCritique`; that selected value feeds
  `CameraReviewPresentation.make`. The review projection does not expose a
  confidence percentage.
- The additional Scene Generator route reads
  `SceneGeneratorViewModel.liveHint` / `hintPauseCritique` through
  `makeHintDecisionTrace()`. Its pause critique is applied only when the
  accepted snapshot has a display image; Decision Trace uses the numeric
  confidence converter above.

A pipeline publication or exported numeric score alone establishes neither
UI acceptance nor that a percentage was rendered on the primary camera screen.

The scorer's multi-mode merge selects the maximum confidence from shown rows
with semantic actions, otherwise shown rows, otherwise all rows. That is an
evaluation aggregation across modes, not one observed UI confidence. Its
existing high/medium/low thresholds and labels remain separate from the UI's
display tones and are unchanged by this producer correction. Historical
exports that used exporter-only floors/caps cannot be interpreted as recorded
UI confidence without the corresponding presentation evidence.

DEBUG replay API:

```text
AnalysisPipeline.testingReplayStillImageForSemanticEval(...)
SemanticEvalStillImageReplayOptions.fullRuntime
SemanticEvalStillImageReplayOptions.lightweightTest
SemanticEvalStillImageReplayResult.rows
```

`fullRuntime` is the only option allowed to claim `runtime_claim = real_runtime_still_replay`.
`lightweightTest` deliberately emits `runtime_claim = test_fixture`, because it skips heavy DETR/aesthetic/neural/visual evidence paths and exists only for fast contract tests.

Important boundary:

- this proves that runtime presentations and still-image replay can be exported into eval JSON;
- as of 2026-05-22, `SemanticEvalStillImageBatchReplayTests.testExportSemanticEvalCandidateOutputsFromStillImages` can batch replay all `001...107` images and write real-runtime rows;
- final measured reports must use rows produced by `fullRuntime`, not proxy rows and not `lightweightTest`.

## Scored Failure Types

- `missing_expected_action`: candidate missed an expected semantic action.
- `missing_future_action`: frame needs a technical/IQA action not emitted by the candidate.
- `forbidden_action_violation`: candidate emitted an action explicitly forbidden by the label.
- `good_frame_overcorrection`: candidate tried to fix a protected good/cinematic frame.
- `missing_positive_confirmation`: candidate did not affirm a good frame.
- `semantic_overreach_on_technical_failure`: candidate gave ordinary composition advice for a dominant technical defect.
- `confidence_band_mismatch`: candidate confidence does not match the expected band.

## Key Metrics

- `expected_action_hit_rate`
- `future_action_hit_rate`
- `forbidden_action_violation_rate`
- `good_frame_preservation_rate`
- `technical_failure_gate_rate`
- `positive_confirmation_rate`
- `confidence_band_accuracy`
- `demo_priority_pass_rate`

These metrics must stay separated. A single average quality score would hide exactly the mistakes this feature is supposed to expose.
