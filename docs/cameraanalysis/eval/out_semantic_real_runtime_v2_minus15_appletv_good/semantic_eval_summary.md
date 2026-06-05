# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_v2_minus15_appletv_good`

## Set Metrics

- `record_count`: 192
- `pass_rate`: 0.723958
- `expected_action_hit_rate`: 0.760417
- `future_action_hit_rate`: 0.848101
- `forbidden_action_violation_rate`: 0.203125
- `good_frame_preservation_rate`: 0.851852
- `technical_failure_gate_rate`: 0.962963
- `positive_confirmation_rate`: 0.851852
- `confidence_band_accuracy`: 0.911458
- `demo_priority_pass_rate`: 0.547619

## Failure Counts

- `confidence_band_mismatch`: 17
- `forbidden_action_violation`: 39
- `good_frame_overcorrection`: 12
- `missing_expected_action`: 46
- `missing_future_action`: 12
- `missing_positive_confirmation`: 12
- `semantic_overreach_on_technical_failure`: 1

## First Failed Cases

- `ca_img_109` / `109.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_116` / `116.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_123` / `123.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_128` / `128.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_130` / `130.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_131` / `131.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_137` / `137.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_145` / `145.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_147` / `147.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_150` / `150.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_154` / `154.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_156` / `156.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_158` / `158.jpg`: confidence_band_mismatch
- `ca_img_160` / `160.jpg`: missing_expected_action
- `ca_img_161` / `161.jpg`: missing_expected_action, forbidden_action_violation, confidence_band_mismatch
- `ca_img_162` / `162.jpg`: missing_expected_action, forbidden_action_violation
- `ca_img_163` / `163.jpg`: missing_expected_action, missing_future_action, forbidden_action_violation
- `ca_img_164` / `164.jpg`: missing_expected_action, missing_future_action, forbidden_action_violation, confidence_band_mismatch
- `ca_img_165` / `165.jpg`: missing_expected_action, forbidden_action_violation
- `ca_img_167` / `167.jpg`: missing_expected_action, forbidden_action_violation
