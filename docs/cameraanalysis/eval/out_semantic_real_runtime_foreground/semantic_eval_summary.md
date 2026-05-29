# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_foreground`

## Set Metrics

- `record_count`: 107
- `pass_rate`: 0.018692
- `expected_action_hit_rate`: 0.429907
- `future_action_hit_rate`: 0.1875
- `forbidden_action_violation_rate`: 0.271028
- `good_frame_preservation_rate`: 0.456522
- `technical_failure_gate_rate`: 0.8
- `positive_confirmation_rate`: 0.456522
- `confidence_band_accuracy`: 0.074766
- `demo_priority_pass_rate`: 0.0

## Failure Counts

- `confidence_band_mismatch`: 99
- `forbidden_action_violation`: 29
- `good_frame_overcorrection`: 25
- `missing_expected_action`: 61
- `missing_future_action`: 39
- `missing_positive_confirmation`: 25
- `semantic_overreach_on_technical_failure`: 4

## First Failed Cases

- `ca_img_001` / `001.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_002` / `002.jpg`: missing_expected_action
- `ca_img_003` / `003.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_004` / `004.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_005` / `005.jpg`: confidence_band_mismatch
- `ca_img_006` / `006.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_007` / `007.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_008` / `008.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_009` / `009.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_010` / `010.jpg`: confidence_band_mismatch
- `ca_img_011` / `011.jpeg`: confidence_band_mismatch
- `ca_img_012` / `012.jpeg`: confidence_band_mismatch
- `ca_img_013` / `013.jpeg`: missing_expected_action
- `ca_img_014` / `014.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_015` / `015.jpeg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_017` / `017.jpeg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_018` / `018.jpeg`: confidence_band_mismatch
- `ca_img_019` / `019.jpg`: confidence_band_mismatch
- `ca_img_020` / `020.jpg`: confidence_band_mismatch
- `ca_img_021` / `021.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
