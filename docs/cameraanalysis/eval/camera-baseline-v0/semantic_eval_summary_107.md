# Semantic Label Eval Summary

Candidate: `m4-001-fullruntime-107-r1`

## Set Metrics

- `record_count`: 107
- `pass_rate`: 0.46729
- `expected_action_hit_rate`: 0.588785
- `future_action_hit_rate`: 0.895833
- `forbidden_action_violation_rate`: 0.084112
- `good_frame_preservation_rate`: 0.478261
- `technical_failure_gate_rate`: 0.9
- `positive_confirmation_rate`: 0.434783
- `confidence_band_accuracy`: 0.672897
- `demo_priority_pass_rate`: 0.5

## Failure Counts

- `confidence_band_mismatch`: 35
- `forbidden_action_violation`: 9
- `good_frame_overcorrection`: 24
- `missing_expected_action`: 44
- `missing_future_action`: 5
- `missing_positive_confirmation`: 26
- `semantic_overreach_on_technical_failure`: 2

## First Failed Cases

- `ca_img_001` / `001.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_002` / `002.jpg`: confidence_band_mismatch
- `ca_img_003` / `003.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_006` / `006.jpg`: missing_expected_action
- `ca_img_007` / `007.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_008` / `008.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_009` / `009.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_011` / `011.jpeg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_012` / `012.jpeg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_014` / `014.jpeg`: missing_expected_action
- `ca_img_016` / `016.jpeg`: confidence_band_mismatch
- `ca_img_017` / `017.jpeg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_019` / `019.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_020` / `020.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_021` / `021.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_022` / `022.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_024` / `024.jpg`: confidence_band_mismatch
- `ca_img_027` / `027.jpg`: confidence_band_mismatch
- `ca_img_028` / `028.jpg`: missing_expected_action, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
- `ca_img_030` / `030.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation, confidence_band_mismatch
