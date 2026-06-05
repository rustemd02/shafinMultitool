# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_v2_207_sim`

## Set Metrics

- `record_count`: 207
- `pass_rate`: 0.63285
- `expected_action_hit_rate`: 0.714976
- `future_action_hit_rate`: 0.810127
- `forbidden_action_violation_rate`: 0.169082
- `good_frame_preservation_rate`: 0.90625
- `technical_failure_gate_rate`: 0.962963
- `positive_confirmation_rate`: 0.770833
- `confidence_band_accuracy`: 0.845411
- `demo_priority_pass_rate`: 0.5

## Failure Counts

- `confidence_band_mismatch`: 32
- `forbidden_action_violation`: 35
- `good_frame_overcorrection`: 9
- `missing_expected_action`: 59
- `missing_future_action`: 15
- `missing_positive_confirmation`: 22
- `semantic_overreach_on_technical_failure`: 1

## First Failed Cases

- `ca_img_110` / `110.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_112` / `112.jpg`: missing_expected_action, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_113` / `113.jpg`: confidence_band_mismatch
- `ca_img_114` / `114.jpg`: confidence_band_mismatch
- `ca_img_115` / `115.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_116` / `116.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_118` / `118.jpg`: confidence_band_mismatch
- `ca_img_120` / `120.jpg`: confidence_band_mismatch
- `ca_img_123` / `123.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_124` / `124.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_125` / `125.jpg`: missing_expected_action, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_126` / `126.jpg`: confidence_band_mismatch
- `ca_img_127` / `127.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_128` / `128.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_129` / `129.jpg`: missing_expected_action, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_130` / `130.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_132` / `132.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_133` / `133.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_139` / `139.jpg`: confidence_band_mismatch
- `ca_img_140` / `140.jpg`: missing_expected_action, missing_positive_confirmation
