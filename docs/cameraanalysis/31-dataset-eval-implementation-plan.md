# 31. Dataset Eval Implementation Plan

Status: implementation-ready plan.
Date: 2026-05-21.

Этот документ отвечает на вопрос: что конкретно нужно сделать после появления:

- canonical source-of-truth: [30-semantic-camera-source-of-truth.md](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/cameraanalysis/30-semantic-camera-source-of-truth.md);
- image set: `docs/cameraanalysis/dataset/inbox/images/001...107`;
- first-pass labels: `docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl`.

Главная мысль: дальше нельзя улучшать Camera Analysis «на глаз». Сначала нужно сделать eval, который измеряет, когда система:

- правильно хвалит хороший кадр;
- не переисправляет художественный low-key / cinematic кадр;
- отличает технический дефект от композиционной проблемы;
- выдает полезный live-tip;
- не выдает forbidden tips;
- показывает pause-разбор с confidence.

## 1. Current Inputs

### Required Dataset Inputs

```text
docs/cameraanalysis/dataset/inbox/images/
  001...107
  images_manifest.csv
  images_manifest.jsonl
  semantic_labels_v1.jsonl
  semantic_labels_v1.csv
  semantic_labels_v1_summary.md
  qa/
    contact_sheet_001_036.jpg
    contact_sheet_037_072.jpg
    contact_sheet_073_107.jpg
    semantic_labels_v1_validation.json
```

### Current Label Stats

Current first-pass label set:

- total records: 107;
- `good`: 46;
- `mixed`: 14;
- `bad`: 47;
- source buckets:
  - `curated_user_inbox`: 57;
  - `public_iqa_bad_tail`: 50;
- demo-priority records: 14.

Important boundary:

- `semantic_labels_v1` is AI first pass, not final human-gold;
- every record currently has `review_status = ai_first_pass_needs_human_review`;
- labels are still useful as bootstrap eval and calibration data.

## 2. Immediate Decisions

### Decision 1. What To Commit

Do not commit the raw `ChallengeDB_release` folder unless the user explicitly accepts repository bloat and licensing implications.

Recommended git policy:

- commit source docs;
- commit labels/manifests/contact sheets if repository size remains acceptable;
- do not commit raw `ChallengeDB_release`;
- either ignore raw dataset or move it outside tracked repo later.

Concrete check before commit:

```bash
du -sh docs/cameraanalysis/dataset
du -sh docs/cameraanalysis/dataset/inbox/images/ChallengeDB_release
git status --short docs/cameraanalysis/dataset
```

### Decision 2. What Is Gold

For now:

- `semantic_labels_v1.jsonl` is `silver`;
- user-reviewed subset becomes `gold_demo_v1`;
- future VLM-reviewed/human-edited subset becomes `gold_eval_v1`.

Do not call the whole set `gold` until the user reviews at least:

- all 14 demo-priority frames;
- at least 10 bad LIVE ChallengeDB frames;
- at least 5 mixed/ambiguous frames.

### Decision 3. Eval Scope

Initial eval should not try to replay full camera inference from pixels.

Initial eval should measure:

- candidate output projections vs labels;
- labels schema quality;
- forbidden-tip behavior;
- good-frame preservation;
- technical-quality gate behavior.

End-to-end pixel replay can come later.

## 3. PR Pipeline

### PR-E01. Dataset Freeze And Hygiene

Goal:

Make the dataset safe, stable and reusable.

Write scope:

- `docs/cameraanalysis/dataset/**`
- `.gitignore` or local dataset ignore policy if needed
- `docs/cameraanalysis/README.md`
- this document if corrections are discovered

Tasks:

1. Decide whether raw `ChallengeDB_release` stays in repo folder or is moved outside tracked data.
2. Add a dataset README:
   - what `001...107` are;
   - why `058...107` are bad LIVE ChallengeDB tail frames;
   - what `semantic_labels_v1` contains;
   - which files are source-of-truth.
3. Add or update ignore rules for heavyweight raw data if needed.
4. Verify every label points to an existing image.
5. Verify every image has exactly one label.
6. Preserve contact sheets for visual audit.

Acceptance criteria:

- `semantic_labels_v1_validation.json` exists and says `status = passed`;
- image count equals label count;
- no accidental deletion of user-curated images;
- raw public dataset handling is explicit;
- README explains that labels are first-pass/silver, not final gold.

Verification:

```bash
python3 - <<'PY'
from pathlib import Path
import json
images = [p for p in Path("docs/cameraanalysis/dataset/inbox/images").iterdir()
          if p.is_file() and p.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp", ".heic"}]
labels = [json.loads(x) for x in Path("docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl").read_text(encoding="utf-8").splitlines()]
assert len(images) == 107
assert len(labels) == 107
assert sorted(p.name for p in images) == [r["filename"] for r in labels]
print("dataset freeze ok")
PY
```

### PR-E02. Semantic Label Eval Adapter

Goal:

Convert `semantic_labels_v1.jsonl` into an eval bundle that the existing Python eval harness can score.

Write scope:

- `docs/cameraanalysis/eval/semantic_label_adapter.py`
- `docs/cameraanalysis/eval/run_semantic_label_eval.py`
- `docs/cameraanalysis/eval/tests/test_semantic_label_eval.py`
- optional generated example report under `docs/cameraanalysis/eval/out_semantic_labels_example/`

Tasks:

1. Define `SemanticLabelRecord` loader.
2. Validate required fields:
   - `record_id`;
   - `filename`;
   - `quality_label`;
   - `expected_live_tip`;
   - `expected_pause_summary`;
   - `expected_semantic_actions`;
   - `future_needed_actions`;
   - `forbidden_actions`;
   - `confidence_target`;
   - `demo_priority`;
   - `eval_tags`.
3. Build normalized eval case projection:
   - `case_id`;
   - `image_ref`;
   - `quality_label`;
   - `expected_actions`;
   - `future_actions`;
   - `forbidden_actions`;
   - `expected_live_text_class`;
   - `expected_pause_summary`;
   - `tags`;
   - `source_bucket`.
4. Add CLI:

```bash
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_labels
```

5. Initial mode may score labels against themselves as `oracle_projection`.
6. Output:
   - `case_results.jsonl`;
   - `set_metrics.json`;
   - `bucket_metrics.json`;
   - `semantic_eval_summary.md`.

Acceptance criteria:

- CLI runs from repo root;
- output report has 107 cases;
- schema validation catches missing files, missing labels and invalid action ids;
- tests cover happy path and at least 3 malformed cases.

Verification:

```bash
python3 -m pytest docs/cameraanalysis/eval/tests -q
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_labels
```

### PR-E03. Candidate Output Projection Contract

Goal:

Define the shape that app/runtime/candidate pipelines must output so eval can compare real behavior with labels.

Write scope:

- `docs/cameraanalysis/32-semantic-eval-output-contract.md`
- `docs/cameraanalysis/eval/semantic_output_schema.py`
- tests

Candidate output shape:

```json
{
  "record_id": "ca_img_001",
  "filename": "001.jpg",
  "mode": "live",
  "shown": true,
  "live_tip": "Кадр читается хорошо: герой выделен светом и цветом.",
  "pause_summary": null,
  "semantic_actions": ["keep_current_setup"],
  "confidence": 0.82,
  "source": "deterministic_current",
  "trace_ids": []
}
```

Tasks:

1. Define output schema for live and pause.
2. Define how to score:
   - expected action hit;
   - forbidden action violation;
   - good-frame preservation;
   - technical failure suppression;
   - confidence band match.
3. Add schema validator.
4. Add fixture candidate outputs:
   - perfect oracle;
   - deliberately bad candidate;
   - deterministic-baseline placeholder.

Acceptance criteria:

- scorer can compare labels vs candidate outputs;
- forbidden tips are counted as severe failures;
- good-frame overcorrection is separately reported;
- technical-failure misclassification is separately reported.

### PR-E04. Good Frame Preservation Gate

Goal:

Make eval explicitly protect good cinematic frames from mechanical overcorrection.

Why:

This is central to the dissertation story. A naive camera coach says "too dark" or "move closer"; our system must recognize when darkness, negative space or backlight is intentional.

Tasks:

1. Add bucket `good_frame_preservation`.
2. Add sub-buckets:
   - `avoid_overcorrection`;
   - `low_key_style`;
   - `wide_negative_space`;
   - `backlight_style`;
   - `object_still_life_good`;
   - `group_subject_good`.
3. Score failures:
   - candidate suggests exposure correction on protected low-key frame;
   - candidate suggests `step_closer` on protected wide/negative-space frame;
   - candidate suggests background simplification on intentional cinematic background;
   - candidate does not provide any positive explanation on good frame.

Acceptance criteria:

- all `quality_label = good` cases are scored for overcorrection;
- demo-priority good cases are highlighted separately;
- report includes top failing good frames.

### PR-E05. Technical Quality Gate

Goal:

Prevent the semantic planner from pretending that motion blur, defocus and exposure failure are ordinary composition problems.

Why:

The LIVE ChallengeDB bad tail mostly contains technical failures. They are valuable because they teach the system when not to give fake semantic camera advice.

Tasks:

1. Add `technical_quality_defects` scoring:
   - `motion_blur`;
   - `defocus`;
   - `overexposure`;
   - `underexposure`;
   - `noise`;
   - `occlusion`;
   - `low_contrast`.
2. Add allowed technical future actions:
   - `stabilize_camera`;
   - `refocus_subject`;
   - `reduce_exposure`;
   - `increase_exposure`;
   - `avoid_occlusion`;
   - `clean_lens`;
   - `reduce_iso_noise`.
3. Add failure type `semantic_overreach_on_technical_failure`.
4. Add rule:
   - if technical defect is dominant and candidate outputs only `shift_frame_*`, score as weak or wrong unless labels also expected reframing.

Acceptance criteria:

- technical failures are not counted as normal semantic-action failures;
- report separates "needs better IQA gate" from "needs better composition planner";
- this creates a clear next implementation target for the app.

### PR-E06. Object-Aware Tip Readiness

Goal:

Prepare the eval path for object-aware tips such as "цветок мешает лицу" without pretending the current 107-image set fully covers them.

Tasks:

1. Add optional fields to label schema:
   - `target_entities`;
   - `distracting_entities`;
   - `object_relation`;
   - `grounding_required`;
   - `object_display_label_policy`.
2. Backfill only cases where object relation is obvious.
3. Add TODO bucket `needs_object_distraction_cases`.
4. Define minimum future object-aware mini-set:
   - 10 images where object clearly distracts;
   - 5 where object is good foreground/prop and must not be removed;
   - 5 where object label is uncertain and system should degrade to generic text.

Acceptance criteria:

- eval schema can represent object-aware cases;
- current labels do not overclaim object grounding;
- next dataset collection request is explicit.

### PR-E07. Demo Gold Review Pass

Goal:

Turn 14 demo-priority frames from silver labels into user-reviewed gold labels.

Tasks:

1. Create a review sheet for demo-priority images:
   - filename;
   - preview ref;
   - current label;
   - expected live;
   - expected pause;
   - forbidden actions.
2. Ask user to approve/edit each.
3. Save reviewed output:

```text
docs/cameraanalysis/dataset/gold/gold_demo_v1.jsonl
docs/cameraanalysis/dataset/gold/gold_demo_v1_review.md
```

Acceptance criteria:

- all 14 demo-priority frames have `review_status = human_reviewed`;
- at least 5 defense scenarios are selected;
- each selected defense scenario has:
  - what app should show live;
  - what app should show in pause;
  - what debug/evidence line should prove.

### PR-E08. Current App Baseline Export

Goal:

Generate candidate outputs from the current deterministic app/pipeline or a faithful approximation, so eval can report current failures.

Possible implementation paths:

1. Swift unit/integration adapter if pipeline can accept still images.
2. Python proxy adapter using labels and known current limitations.
3. Manual baseline candidate for first report.

Recommended path:

- start with manual/proxy baseline to unblock eval report;
- later replace with real app still-image replay.

Tasks:

1. Create `candidate_outputs_current_baseline.jsonl`.
2. Mark source as `manual_proxy_current_limitations` if not real runtime.
3. Run scorer against labels.
4. Produce report:
   - good-frame false positives;
   - technical-failure semantic overreach;
   - missing object-aware tips;
   - missing positive confirmation.

Acceptance criteria:

- report honestly says whether baseline is real runtime or proxy;
- no proxy report is used as a final performance claim;
- report is still useful for prioritizing next implementation PRs.

### PR-E09. Calibration Backlog From Eval Failures

Goal:

Convert eval findings into implementation PRs.

Tasks:

1. Read eval failures.
2. Create ranked issue list:
   - high impact;
   - demo impact;
   - thesis impact;
   - implementation complexity.
3. Generate next implementation PRs:
   - `GoodFramePreservationEngine`;
   - `TechnicalQualityGate`;
   - `ObjectAwareDistractionDetector`;
   - `PauseExplanationAlignment`;
   - `ConfidenceCalibration`.
4. Update `12-agent-prompts.md` with prompts for those PRs.

Acceptance criteria:

- no implementation PR is justified only by intuition;
- each PR links to eval failure buckets;
- DoD includes before/after eval metrics.

## 4. Required Metrics

Initial semantic label eval must produce these metrics:

- `record_count`;
- `expected_action_hit_rate`;
- `forbidden_action_violation_rate`;
- `good_frame_preservation_rate`;
- `technical_failure_gate_rate`;
- `positive_confirmation_rate`;
- `confidence_band_accuracy`;
- `demo_priority_pass_rate`;
- bucket metrics by `eval_tags`;
- bucket metrics by `quality_label`;
- bucket metrics by `source_bucket`.

Important:

- do not collapse everything into one "quality score";
- report separate failure categories;
- always show demo-priority failures explicitly.

## 5. Data Model Rules

### Required Label Fields

Each `semantic_labels_v1` record must keep:

- `record_id`;
- `filename`;
- `image_path`;
- `source_bucket`;
- `source_dataset`;
- `quality_label`;
- `scene_type`;
- `primary_subject`;
- `positive_factors`;
- `problems`;
- `technical_quality_defects`;
- `expected_live_tip`;
- `expected_pause_summary`;
- `expected_semantic_actions`;
- `future_needed_actions`;
- `forbidden_actions`;
- `confidence_target`;
- `demo_priority`;
- `eval_tags`;
- `review_status`.

### Action Semantics

Use `expected_semantic_actions` for actions already present in the closed semantic catalog:

- `keep_current_setup`;
- `simplify_background`;
- `remove_background_hotspot`;
- `add_front_fill_light`;
- `add_background_light`;
- `wait_for_background_clearance`;
- `change_camera_angle`;
- `level_horizon`;
- `step_closer`;
- `step_back`;
- `shift_frame_*`.

Use `future_needed_actions` for technical/IQA actions not yet part of the semantic catalog:

- `stabilize_camera`;
- `refocus_subject`;
- `reduce_exposure`;
- `increase_exposure`;
- `avoid_occlusion`;
- `clean_lens`;
- `reduce_iso_noise`.

Do not silently move future technical actions into semantic actions without updating the catalog and UI contract.

## 6. Verification Checklist

Before claiming any eval/dataset PR done:

```bash
python3 -m pytest docs/cameraanalysis/eval/tests -q
python3 - <<'PY'
from pathlib import Path
import json
images = [p for p in Path("docs/cameraanalysis/dataset/inbox/images").iterdir()
          if p.is_file() and p.suffix.lower() in {".jpg", ".jpeg", ".png", ".bmp", ".heic"}]
labels = [json.loads(x) for x in Path("docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl").read_text(encoding="utf-8").splitlines()]
assert len(images) == len(labels)
assert [r["filename"] for r in labels] == sorted(p.name for p in images)
assert all(r["expected_live_tip"] for r in labels)
assert all(r["expected_pause_summary"] for r in labels)
assert all(not (set(r["expected_semantic_actions"]) & set(r["forbidden_actions"])) for r in labels)
print("semantic labels ok")
PY
```

If `run_semantic_label_eval.py` exists:

```bash
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_labels
```

## 7. What I Need From The User

Before gold/demo freeze:

1. Review the 14 demo-priority frames.
2. Tell which 5-7 are best for defense.
3. Correct any labels that feel wrong.
4. Provide object-aware distraction cases:
   - flower blocking face;
   - lamp distracting from person;
   - phone/cup/prop competing with subject;
   - good prop that must not be removed.

Recommended format:

```text
Файл: 001.jpg
Статус: approve / edit
Если edit:
  live:
  pause:
  forbidden:
  comment:
```

## 8. Implementation Order

Recommended order:

1. PR-E01 Dataset Freeze And Hygiene.
2. PR-E02 Semantic Label Eval Adapter.
3. PR-E03 Candidate Output Projection Contract.
4. PR-E04 Good Frame Preservation Gate.
5. PR-E05 Technical Quality Gate.
6. PR-E07 Demo Gold Review Pass.
7. PR-E08 Current App Baseline Export.
8. PR-E09 Calibration Backlog From Eval Failures.
9. PR-E06 Object-Aware Tip Readiness can run in parallel after PR-E02.

Do not start Remote VLM implementation until PR-E02 and PR-E04/PR-E05 exist. Otherwise VLM output will look impressive but will not be measurable.

## 9. Done Definition For This Stage

This stage is done when:

- dataset has explicit hygiene policy;
- labels are loadable and validated;
- eval can score labels vs candidate outputs;
- reports separate good-frame preservation, forbidden tips and technical failures;
- demo-priority frames are reviewed;
- current app/proxy baseline has a failure report;
- next algorithmic PRs are ranked by eval failures, not intuition.

After that, it becomes safe to implement:

- better good-frame preservation;
- technical quality gate in live/pause;
- object-aware distraction tips;
- pause-only VLM provider;
- VLM-to-student distillation plan.
