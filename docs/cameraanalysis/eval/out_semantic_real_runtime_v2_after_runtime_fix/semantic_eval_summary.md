# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_v2_207_sim`

## Set Metrics

- `record_count`: 207
- `pass_rate`: 0.492754
- `expected_action_hit_rate`: 0.608696
- `future_action_hit_rate`: 0.848101
- `forbidden_action_violation_rate`: 0.26087
- `good_frame_preservation_rate`: 0.625
- `technical_failure_gate_rate`: 0.925926
- `positive_confirmation_rate`: 0.572917
- `confidence_band_accuracy`: 0.768116
- `demo_priority_pass_rate`: 0.369565

## Failure Counts

- `confidence_band_mismatch`: 48
- `forbidden_action_violation`: 54
- `good_frame_overcorrection`: 36
- `missing_expected_action`: 81
- `missing_future_action`: 12
- `missing_positive_confirmation`: 41
- `semantic_overreach_on_technical_failure`: 2

## First Failed Cases

- `ca_img_001` / `001.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_002` / `002.jpg`: confidence_band_mismatch
- `ca_img_004` / `004.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_009` / `009.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_012` / `012.jpeg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_013` / `013.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_017` / `017.jpeg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_019` / `019.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_021` / `021.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_028` / `028.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_029` / `029.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_030` / `030.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_031` / `031.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_034` / `034.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_035` / `035.jpg`: confidence_band_mismatch
- `ca_img_036` / `036.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_040` / `040.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_043` / `043.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_050` / `050.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_052` / `052.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
