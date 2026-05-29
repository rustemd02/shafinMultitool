# Camera Analysis Dataset

Status: silver bootstrap dataset.
Created: 2026-05-21.

This dataset supports the semantic camera-coach eval described in
`docs/cameraanalysis/31-dataset-eval-implementation-plan.md`.

## Contents

```text
docs/cameraanalysis/dataset/
  inbox/
    images/
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
  curated/
    bad_live_challenge_50_manifest.*
    bad_live_challenge_50_contact_sheet.jpg
```

## Source Policy

- `001...057` are user-curated cinematic / camera-analysis examples.
- `058...107` are selected low-quality public IQA examples from LIVE In the Wild ChallengeDB.
- `ChallengeDB_release/` is raw public dataset input and is intentionally ignored by git.
- The tracked source of truth for this repo is the renamed image subset plus manifests and labels, not the raw dataset dump.

## Label Policy

`semantic_labels_v1.jsonl` is a first-pass AI label set, not human-gold data.
Every record currently has `review_status = ai_first_pass_needs_human_review`.

The labels separate:

- `expected_semantic_actions`: actions the current semantic camera-coach catalog can express.
- `future_needed_actions`: technical/IQA actions that need future app support, such as `stabilize_camera`, `refocus_subject`, `reduce_exposure`, or `reduce_iso_noise`.
- `forbidden_actions`: actions the app must avoid for that frame.

This separation matters: many bad ChallengeDB frames are technical failures, not composition failures. The app should not pretend that blur, defocus or blown exposure can be fixed by "move camera right".

## Validation

Run from repository root:

```bash
python3 -m pytest docs/cameraanalysis/eval/tests -q
python3 docs/cameraanalysis/eval/run_semantic_label_eval.py \
  --labels docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl \
  --outputs docs/cameraanalysis/eval/out_semantic_current_proxy \
  --candidate proxy_current_limitations
```

The proxy candidate is not a real app runtime measurement. It is a declared limitations baseline until still-image replay exists.
