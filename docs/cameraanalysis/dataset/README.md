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
      001...207
    images_manifest.csv
    images_manifest.jsonl
    apple_tv_press_trailer_sources_108_157.jsonl
    imagegen_bad_sources_158_177.jsonl
    semantic_labels_v1.jsonl
    semantic_labels_v1.csv
    semantic_labels_v1_summary.md
    semantic_labels_imagegen_bad_v1.jsonl
    semantic_labels_imagegen_bad_v1.csv
    semantic_labels_imagegen_bad_v1_summary.md
    semantic_labels_synthetic_bad_v1.jsonl
    semantic_labels_synthetic_bad_v1.csv
    semantic_labels_synthetic_bad_v1_summary.md
    qa/
      contact_sheet_001_036.jpg
      contact_sheet_037_072.jpg
      contact_sheet_073_107.jpg
      contact_sheet_108_157.jpg
      contact_sheet_158_177_imagegen_bad.jpg
      contact_sheet_178_207_synthetic_bad.jpg
      semantic_labels_v1_validation.json
  curated/
    bad_live_challenge_50_manifest.*
    bad_live_challenge_50_contact_sheet.jpg
```

## Source Policy

- `001...057` are user-curated cinematic / camera-analysis examples.
- `058...107` are selected low-quality public IQA examples from LIVE In the Wild ChallengeDB.
- `108...157` are unlabeled official Apple TV Press trailer-poster/still candidates for the next benchmark expansion.
- `158...177` are AI-generated synthetic bad anti-examples derived from `108...127`, with extra deterministic framing damage for demo stress testing.
- `178...207` are deterministic synthetic bad variants derived from `128...157`; every degradation is reproducible from a named Python recipe.
- `ChallengeDB_release/` is raw public dataset input and is intentionally ignored by git.
- The tracked source of truth for this repo is the renamed image subset plus manifests and labels, not the raw dataset dump.
- `apple_tv_press_trailer_sources_108_157.jsonl` stores the source page URL, source image URL, dimensions and SHA-256 for each Apple TV Press candidate.
- `imagegen_bad_sources_158_177.jsonl` stores parent-frame provenance, imagegen source paths, expected issue tags and deterministic postprocess metadata for the synthetic bad set.

## Label Policy

`semantic_labels_v1.jsonl` is a first-pass AI label set, not human-gold data.
It currently covers only `001...107`; `108...157` are intentionally marked as unlabeled candidates until a separate review pass creates labels for them.
Every record currently has `review_status = ai_first_pass_needs_human_review`.

`semantic_labels_imagegen_bad_v1.jsonl` is a separate synthetic stress set for `158...177`.
It is not merged into `semantic_labels_v1` because these records are deliberately exaggerated anti-examples, not organic camera captures.
Every record has `review_status = imagegen_synthetic_needs_human_review`.

`semantic_labels_synthetic_bad_v1.jsonl` is a separate deterministic recipe stress set for `178...207`.
It is useful for auditable eval/debugging because each record has a parent image, recipe name and exact expected action set.
Every record has `review_status = synthetic_recipe_needs_human_spot_check`.

The labels separate:

- `expected_semantic_actions`: actions the current semantic camera-coach catalog can express.
- `future_needed_actions`: technical/IQA actions that need future app support, such as `stabilize_camera`, `refocus_subject`, `reduce_exposure`, or `reduce_iso_noise`.
- `forbidden_actions`: actions the app must avoid for that frame.

This separation matters: many bad ChallengeDB frames are technical failures, not composition failures. The app should not pretend that blur, defocus or blown exposure can be fixed by "move camera right".

The synthetic bad set intentionally combines multiple visible problems in each frame: bad crop, edge pressure, foreground obstruction, clutter, empty space, hotspot or backlight.
Its purpose is to make the semantic coach explain why it recommends actions such as `step_back`, `shift_frame_right`, `simplify_background` or `wait_for_background_clearance`.

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
