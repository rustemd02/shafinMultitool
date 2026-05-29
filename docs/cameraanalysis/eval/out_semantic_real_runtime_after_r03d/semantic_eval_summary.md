# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_after_r03d`

## Set Metrics

- `record_count`: 107
- `pass_rate`: 0.261682
- `expected_action_hit_rate`: 0.514019
- `future_action_hit_rate`: 0.875
- `forbidden_action_violation_rate`: 0.17757
- `good_frame_preservation_rate`: 0.76087
- `technical_failure_gate_rate`: 1.0
- `positive_confirmation_rate`: 0.630435
- `confidence_band_accuracy`: 0.616822
- `demo_priority_pass_rate`: 0.428571

## Failure Counts

- `confidence_band_mismatch`: 41
- `forbidden_action_violation`: 19
- `good_frame_overcorrection`: 11
- `missing_expected_action`: 52
- `missing_future_action`: 6
- `missing_positive_confirmation`: 17

## First Failed Cases

- `ca_img_001` / `001.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_002` / `002.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_003` / `003.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_004` / `004.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_006` / `006.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_007` / `007.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_009` / `009.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_010` / `010.jpg`: confidence_band_mismatch
- `ca_img_011` / `011.jpeg`: confidence_band_mismatch
- `ca_img_013` / `013.jpeg`: missing_expected_action
- `ca_img_014` / `014.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_015` / `015.jpeg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_017` / `017.jpeg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_018` / `018.jpeg`: missing_expected_action, missing_positive_confirmation
- `ca_img_020` / `020.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_022` / `022.jpg`: confidence_band_mismatch
- `ca_img_023` / `023.jpg`: confidence_band_mismatch
- `ca_img_024` / `024.jpg`: confidence_band_mismatch
- `ca_img_027` / `027.jpg`: confidence_band_mismatch
- `ca_img_028` / `028.jpg`: confidence_band_mismatch
