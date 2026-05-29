# Semantic Labels v1 Summary

Generated: 2026-05-21.

## Files

- JSONL: `semantic_labels_v1.jsonl`
- CSV: `semantic_labels_v1.csv`
- Validation: `qa/semantic_labels_v1_validation.json`
- Image folder: `docs/cameraanalysis/dataset/inbox/images`

## Counts

- Total records: 107
- Quality labels: {'good': 46, 'mixed': 14, 'bad': 47}
- Confidence targets: {'high': 73, 'medium': 31, 'low': 3}
- Source buckets: {'curated_user_inbox': 57, 'public_iqa_bad_tail': 50}
- Demo-priority records: 14
- Good live texts made more specific: 15

## Most Frequent Expected Actions

- `keep_current_setup`: 46
- `simplify_background`: 13
- `remove_background_hotspot`: 10
- `add_front_fill_light`: 7
- `wait_for_background_clearance`: 6
- `change_camera_angle`: 4
- `step_closer`: 4
- `shift_frame_right`: 2
- `step_back`: 2
- `add_background_light`: 1
- `level_horizon`: 1

## Most Frequent Future/Technical Actions

- `stabilize_camera`: 30
- `reduce_exposure`: 18
- `refocus_subject`: 14
- `increase_exposure`: 8
- `reduce_iso_noise`: 7
- `avoid_occlusion`: 2
- `clean_lens`: 1

## Most Frequent Technical Defects

- `motion_blur`: 30
- `overexposure`: 18
- `defocus`: 14
- `underexposure`: 8
- `low_light`: 5
- `no_clear_focus`: 5
- `no_clear_subject`: 5
- `background_clutter`: 3
- `hotspot`: 2
- `occlusion`: 2
- `clutter`: 1
- `horizon`: 1
- `flash`: 1
- `subject_too_small`: 1
- `color_cast`: 1
- `low_contrast`: 1

## Demo-Priority Filenames

- `001.jpg`
- `003.jpg`
- `005.jpg`
- `010.jpg`
- `015.jpeg`
- `018.jpeg`
- `019.jpg`
- `020.jpg`
- `026.jpg`
- `031.jpg`
- `040.jpg`
- `041.jpg`
- `048.jpg`
- `051.jpg`

## Labeling Policy

These labels are an AI first pass from contact-sheet visual review. They are useful for eval bootstrap and planner calibration, but `review_status` remains `ai_first_pass_needs_human_review` until the user confirms or edits key cases.

The labels intentionally separate `expected_semantic_actions` from `future_needed_actions`. Many LIVE ChallengeDB bad images are primarily technical failures, so they should not force the semantic planner to pretend that motion blur, defocus, noise or blown exposure can be fixed by reframing alone.
