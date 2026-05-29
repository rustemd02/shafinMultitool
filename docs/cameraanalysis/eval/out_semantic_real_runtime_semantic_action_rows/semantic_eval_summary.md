# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_semantic_action_rows`

## Set Metrics

- `record_count`: 107
- `pass_rate`: 0.186916
- `expected_action_hit_rate`: 0.495327
- `future_action_hit_rate`: 0.520833
- `forbidden_action_violation_rate`: 0.345794
- `good_frame_preservation_rate`: 0.543478
- `technical_failure_gate_rate`: 0.9
- `positive_confirmation_rate`: 0.543478
- `confidence_band_accuracy`: 0.439252
- `demo_priority_pass_rate`: 0.428571

## Failure Counts

- `confidence_band_mismatch`: 60
- `forbidden_action_violation`: 37
- `good_frame_overcorrection`: 21
- `missing_expected_action`: 54
- `missing_future_action`: 23
- `missing_positive_confirmation`: 21
- `semantic_overreach_on_technical_failure`: 2

## First Failed Cases

- `ca_img_001` / `001.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_002` / `002.jpg`: missing_expected_action, forbidden_action_violation
- `ca_img_003` / `003.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_004` / `004.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_005` / `005.jpg`: confidence_band_mismatch
- `ca_img_006` / `006.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_007` / `007.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_008` / `008.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_010` / `010.jpg`: confidence_band_mismatch
- `ca_img_011` / `011.jpeg`: confidence_band_mismatch
- `ca_img_013` / `013.jpeg`: missing_expected_action
- `ca_img_014` / `014.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_015` / `015.jpeg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_017` / `017.jpeg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_021` / `021.jpg`: confidence_band_mismatch
- `ca_img_022` / `022.jpg`: forbidden_action_violation
- `ca_img_023` / `023.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_024` / `024.jpg`: confidence_band_mismatch
- `ca_img_025` / `025.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_027` / `027.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
