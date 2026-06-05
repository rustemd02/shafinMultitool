# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_v2_207_sim`

## Set Metrics

- `record_count`: 207
- `pass_rate`: 0.57971
- `expected_action_hit_rate`: 0.676329
- `future_action_hit_rate`: 0.848101
- `forbidden_action_violation_rate`: 0.207729
- `good_frame_preservation_rate`: 0.8125
- `technical_failure_gate_rate`: 0.925926
- `positive_confirmation_rate`: 0.75
- `confidence_band_accuracy`: 0.811594
- `demo_priority_pass_rate`: 0.478261

## Failure Counts

- `confidence_band_mismatch`: 39
- `forbidden_action_violation`: 43
- `good_frame_overcorrection`: 18
- `missing_expected_action`: 67
- `missing_future_action`: 12
- `missing_positive_confirmation`: 24
- `semantic_overreach_on_technical_failure`: 2

## First Failed Cases

- `ca_img_012` / `012.jpeg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_013` / `013.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_017` / `017.jpeg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_035` / `035.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_040` / `040.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_052` / `052.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_055` / `055.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_062` / `062.jpg`: semantic_overreach_on_technical_failure, confidence_band_mismatch
- `ca_img_064` / `064.jpg`: missing_expected_action, forbidden_action_violation, confidence_band_mismatch
- `ca_img_069` / `069.jpg`: missing_expected_action
- `ca_img_075` / `075.bmp`: missing_expected_action
- `ca_img_080` / `080.jpg`: confidence_band_mismatch
- `ca_img_084` / `084.jpg`: missing_expected_action
- `ca_img_086` / `086.jpg`: forbidden_action_violation
- `ca_img_087` / `087.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_092` / `092.bmp`: missing_expected_action
- `ca_img_101` / `101.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_102` / `102.jpg`: missing_expected_action
- `ca_img_109` / `109.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_110` / `110.jpg`: confidence_band_mismatch
