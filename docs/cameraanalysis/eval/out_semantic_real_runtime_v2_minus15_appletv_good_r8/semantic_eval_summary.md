# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_v2_minus15_appletv_good_r8`

## Set Metrics

- `record_count`: 192
- `pass_rate`: 0.697917
- `expected_action_hit_rate`: 0.78125
- `future_action_hit_rate`: 0.911392
- `forbidden_action_violation_rate`: 0.161458
- `good_frame_preservation_rate`: 0.864198
- `technical_failure_gate_rate`: 0.962963
- `positive_confirmation_rate`: 0.82716
- `confidence_band_accuracy`: 0.869792
- `demo_priority_pass_rate`: 0.571429

## Failure Counts

- `confidence_band_mismatch`: 25
- `forbidden_action_violation`: 31
- `good_frame_overcorrection`: 11
- `missing_expected_action`: 42
- `missing_future_action`: 7
- `missing_positive_confirmation`: 14
- `semantic_overreach_on_technical_failure`: 1

## First Failed Cases

- `ca_img_016` / `016.jpeg`: confidence_band_mismatch
- `ca_img_024` / `024.jpg`: confidence_band_mismatch
- `ca_img_035` / `035.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_045` / `045.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_054` / `054.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_067` / `067.jpg`: missing_expected_action
- `ca_img_101` / `101.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_112` / `112.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_116` / `116.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_125` / `125.jpg`: confidence_band_mismatch
- `ca_img_128` / `128.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_130` / `130.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_132` / `132.jpg`: confidence_band_mismatch
- `ca_img_133` / `133.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_137` / `137.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_143` / `143.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_145` / `145.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_147` / `147.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_150` / `150.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_154` / `154.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
