# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_after_r12a`

## Set Metrics

- `record_count`: 107
- `pass_rate`: 0.514019
- `expected_action_hit_rate`: 0.785047
- `future_action_hit_rate`: 0.875
- `forbidden_action_violation_rate`: 0.140187
- `good_frame_preservation_rate`: 0.934783
- `technical_failure_gate_rate`: 1.0
- `positive_confirmation_rate`: 0.891304
- `confidence_band_accuracy`: 0.691589
- `demo_priority_pass_rate`: 0.857143

## Failure Counts

- `confidence_band_mismatch`: 33
- `forbidden_action_violation`: 15
- `good_frame_overcorrection`: 3
- `missing_expected_action`: 23
- `missing_future_action`: 6
- `missing_positive_confirmation`: 5

## First Failed Cases

- `ca_img_002` / `002.jpg`: confidence_band_mismatch
- `ca_img_007` / `007.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_009` / `009.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_010` / `010.jpg`: confidence_band_mismatch
- `ca_img_013` / `013.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_014` / `014.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_020` / `020.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_022` / `022.jpg`: confidence_band_mismatch
- `ca_img_023` / `023.jpg`: confidence_band_mismatch
- `ca_img_024` / `024.jpg`: confidence_band_mismatch
- `ca_img_025` / `025.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_027` / `027.jpg`: confidence_band_mismatch
- `ca_img_028` / `028.jpg`: confidence_band_mismatch
- `ca_img_029` / `029.jpg`: confidence_band_mismatch
- `ca_img_032` / `032.jpg`: confidence_band_mismatch
- `ca_img_034` / `034.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_035` / `035.jpg`: confidence_band_mismatch
- `ca_img_036` / `036.jpg`: confidence_band_mismatch
- `ca_img_037` / `037.jpg`: confidence_band_mismatch
- `ca_img_038` / `038.jpg`: confidence_band_mismatch
