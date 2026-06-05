# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_v2_minus15_appletv_good`

## Set Metrics

- `record_count`: 192
- `pass_rate`: 0.666667
- `expected_action_hit_rate`: 0.729167
- `future_action_hit_rate`: 0.911392
- `forbidden_action_violation_rate`: 0.203125
- `good_frame_preservation_rate`: 0.740741
- `technical_failure_gate_rate`: 0.962963
- `positive_confirmation_rate`: 0.666667
- `confidence_band_accuracy`: 0.864583
- `demo_priority_pass_rate`: 0.5

## Failure Counts

- `confidence_band_mismatch`: 26
- `forbidden_action_violation`: 39
- `good_frame_overcorrection`: 21
- `missing_expected_action`: 52
- `missing_future_action`: 7
- `missing_positive_confirmation`: 27
- `semantic_overreach_on_technical_failure`: 1

## First Failed Cases

- `ca_img_003` / `003.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_015` / `015.jpeg`: missing_expected_action, missing_positive_confirmation
- `ca_img_035` / `035.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_042` / `042.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_045` / `045.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_049` / `049.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_054` / `054.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_067` / `067.jpg`: missing_expected_action
- `ca_img_109` / `109.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_112` / `112.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_116` / `116.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_119` / `119.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_123` / `123.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_125` / `125.jpg`: missing_expected_action, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_127` / `127.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_128` / `128.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_130` / `130.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_131` / `131.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_132` / `132.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_133` / `133.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
