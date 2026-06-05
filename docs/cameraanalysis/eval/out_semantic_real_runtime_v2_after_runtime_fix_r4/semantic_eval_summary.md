# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_v2_207_sim`

## Set Metrics

- `record_count`: 207
- `pass_rate`: 0.657005
- `expected_action_hit_rate`: 0.7343
- `future_action_hit_rate`: 0.848101
- `forbidden_action_violation_rate`: 0.193237
- `good_frame_preservation_rate`: 0.864583
- `technical_failure_gate_rate`: 0.962963
- `positive_confirmation_rate`: 0.802083
- `confidence_band_accuracy`: 0.850242
- `demo_priority_pass_rate`: 0.5

## Failure Counts

- `confidence_band_mismatch`: 31
- `forbidden_action_violation`: 40
- `good_frame_overcorrection`: 13
- `missing_expected_action`: 55
- `missing_future_action`: 12
- `missing_positive_confirmation`: 19
- `semantic_overreach_on_technical_failure`: 1

## First Failed Cases

- `ca_img_013` / `013.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_101` / `101.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_109` / `109.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_110` / `110.jpg`: confidence_band_mismatch
- `ca_img_113` / `113.jpg`: confidence_band_mismatch
- `ca_img_114` / `114.jpg`: confidence_band_mismatch
- `ca_img_115` / `115.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_116` / `116.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_118` / `118.jpg`: confidence_band_mismatch
- `ca_img_120` / `120.jpg`: confidence_band_mismatch
- `ca_img_123` / `123.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_124` / `124.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_126` / `126.jpg`: confidence_band_mismatch
- `ca_img_128` / `128.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_129` / `129.jpg`: missing_expected_action, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_130` / `130.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_131` / `131.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_134` / `134.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_137` / `137.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_139` / `139.jpg`: confidence_band_mismatch
