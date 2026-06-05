# Semantic Labels v2 Summary

Generated: 2026-06-04.

## Files

- JSONL: `semantic_labels_v2.jsonl`
- CSV: `semantic_labels_v2.csv`
- Validation: `qa/semantic_labels_v2_validation.json`
- New cinematic preservation labels: `semantic_labels_cinematic_preservation_v1.jsonl`
- Image folder: `docs/cameraanalysis/dataset/inbox/images`

## Counts

- Total records: 207
- Image files: 207
- Quality labels: {'good': 96, 'mixed': 14, 'bad': 97}
- Source buckets: {'curated_user_inbox': 57, 'public_iqa_bad_tail': 50, 'official_promo_cinematic_preservation': 50, 'imagegen_bad_candidate': 20, 'synthetic_bad_paired_apple_tv_press': 30}
- Review statuses: {'ai_first_pass_needs_human_review': 107, 'cinematic_preservation_ai_first_pass_needs_human_review': 50, 'imagegen_synthetic_needs_human_review': 20, 'synthetic_recipe_needs_human_spot_check': 30}
- Demo-priority records: 46

## Benchmark Slices

- `001...107`: original silver still-image eval set with curated/user and public IQA tail records.
- `108...157`: cinematic preservation slice from Apple TV Press/trailer-poster candidates; intended to test that deliberate stylized frames are not overcorrected.
- `158...177`: generated bad stress cases with occlusion, clutter, crop, hotspot and backlight issues.
- `178...207`: deterministic synthetic paired bad variants derived from Apple TV Press seed frames.

## Most Frequent Expected Actions

- `keep_current_setup`: 96
- `simplify_background`: 24
- `remove_background_hotspot`: 18
- `add_front_fill_light`: 15
- `change_camera_angle`: 15
- `step_closer`: 14
- `step_back`: 12
- `remove_distracting_object`: 11
- `wait_for_background_clearance`: 10
- `shift_frame_right`: 8
- `rotate_subject_toward_light`: 6
- `level_horizon`: 5
- `shift_frame_left`: 4
- `add_background_light`: 1
- `shift_frame_up`: 1
- `move_subject_away_from_background`: 1
- `shift_frame_down`: 1
- `move_subject_left`: 1

## Most Frequent Future/Technical Actions

- `stabilize_camera`: 34
- `reduce_exposure`: 26
- `increase_exposure`: 18
- `refocus_subject`: 14
- `avoid_occlusion`: 12
- `reduce_iso_noise`: 10
- `clean_lens`: 1

## Boundary

This is a benchmark-ready silver/first-pass label bundle, not a gold benchmark.
The original 107 records remain unchanged. The new cinematic and synthetic slices are schema-valid and image-complete, but their `review_status` fields explicitly require human review or spot-check before dissertation claims describe them as gold labels.
