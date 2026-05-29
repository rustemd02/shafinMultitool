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
- `confidence`: number in `[0, 1]`.
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
- hidden/no-tip state -> `shown = false`, empty action lists.

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
