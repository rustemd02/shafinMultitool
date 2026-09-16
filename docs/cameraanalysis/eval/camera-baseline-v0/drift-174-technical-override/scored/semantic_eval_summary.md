# Semantic Label Eval Summary

Candidate: `m4-001-fullruntime-174-drift-r1-technical-override`

## Set Metrics

- `record_count`: 174
- `pass_rate`: 0.534483
- `expected_action_hit_rate`: 0.689655
- `future_action_hit_rate`: 0.887324
- `forbidden_action_violation_rate`: 0.137931
- `good_frame_preservation_rate`: 0.839506
- `technical_failure_gate_rate`: 0.9
- `positive_confirmation_rate`: 0.802469
- `confidence_band_accuracy`: 0.724138
- `demo_priority_pass_rate`: 0.333333

## Failure Counts

- `confidence_band_mismatch`: 48
- `forbidden_action_violation`: 24
- `good_frame_overcorrection`: 13
- `missing_expected_action`: 54
- `missing_future_action`: 8
- `missing_positive_confirmation`: 16
- `semantic_overreach_on_technical_failure`: 2

## First Failed Cases

- `ca_img_001` / `001.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_002` / `002.jpg`: confidence_band_mismatch
- `ca_img_007` / `007.jpg`: confidence_band_mismatch
- `ca_img_011` / `011.jpeg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_014` / `014.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_016` / `016.jpeg`: confidence_band_mismatch
- `ca_img_019` / `019.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_020` / `020.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_022` / `022.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_027` / `027.jpg`: confidence_band_mismatch
- `ca_img_034` / `034.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_035` / `035.jpg`: confidence_band_mismatch
- `ca_img_036` / `036.jpg`: forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_037` / `037.jpg`: confidence_band_mismatch
- `ca_img_043` / `043.jpg`: confidence_band_mismatch
- `ca_img_044` / `044.jpg`: missing_expected_action, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_045` / `045.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_050` / `050.jpg`: good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_052` / `052.jpg`: confidence_band_mismatch
- `ca_img_059` / `059.bmp`: confidence_band_mismatch
