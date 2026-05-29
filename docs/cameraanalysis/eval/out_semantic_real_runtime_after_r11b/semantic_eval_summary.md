# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_after_r11b`

## Set Metrics

- `record_count`: 107
- `pass_rate`: 0.457944
- `expected_action_hit_rate`: 0.738318
- `future_action_hit_rate`: 0.875
- `forbidden_action_violation_rate`: 0.11215
- `good_frame_preservation_rate`: 1.0
- `technical_failure_gate_rate`: 1.0
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.663551
- `demo_priority_pass_rate`: 0.714286

## Failure Counts

- `confidence_band_mismatch`: 36
- `forbidden_action_violation`: 12
- `missing_expected_action`: 28
- `missing_future_action`: 6
- `missing_positive_confirmation`: 2

## First Failed Cases

- `ca_img_002` / `002.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_003` / `003.jpg`: confidence_band_mismatch
- `ca_img_005` / `005.jpg`: confidence_band_mismatch
- `ca_img_007` / `007.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_009` / `009.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_010` / `010.jpg`: confidence_band_mismatch
- `ca_img_013` / `013.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_014` / `014.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_020` / `020.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_022` / `022.jpg`: confidence_band_mismatch
- `ca_img_023` / `023.jpg`: confidence_band_mismatch
- `ca_img_024` / `024.jpg`: confidence_band_mismatch
- `ca_img_027` / `027.jpg`: confidence_band_mismatch
- `ca_img_028` / `028.jpg`: confidence_band_mismatch
- `ca_img_029` / `029.jpg`: confidence_band_mismatch
- `ca_img_032` / `032.jpg`: confidence_band_mismatch
- `ca_img_034` / `034.jpg`: confidence_band_mismatch
- `ca_img_035` / `035.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_036` / `036.jpg`: confidence_band_mismatch
- `ca_img_037` / `037.jpg`: confidence_band_mismatch
