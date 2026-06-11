# Semantic Label Eval Summary

Candidate: `candidate_outputs_raw`

## Set Metrics

- `record_count`: 174
- `pass_rate`: 0.850575
- `expected_action_hit_rate`: 0.908046
- `future_action_hit_rate`: 0.943662
- `forbidden_action_violation_rate`: 0.028736
- `good_frame_preservation_rate`: 0.987654
- `technical_failure_gate_rate`: 1.0
- `positive_confirmation_rate`: 0.987654
- `confidence_band_accuracy`: 0.925287
- `demo_priority_pass_rate`: 0.685185

## Failure Counts

- `confidence_band_mismatch`: 13
- `forbidden_action_violation`: 5
- `good_frame_overcorrection`: 1
- `missing_expected_action`: 16
- `missing_future_action`: 4
- `missing_positive_confirmation`: 1

## First Failed Cases

- `ca_img_013` / `013.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_016` / `016.jpeg`: confidence_band_mismatch
- `ca_img_024` / `024.jpg`: confidence_band_mismatch
- `ca_img_035` / `035.jpg`: missing_expected_action, confidence_band_mismatch
- `ca_img_067` / `067.jpg`: missing_expected_action
- `ca_img_101` / `101.jpg`: missing_expected_action
- `ca_img_125` / `125.jpg`: confidence_band_mismatch
- `ca_img_132` / `132.jpg`: confidence_band_mismatch
- `ca_img_150` / `150.jpg`: missing_expected_action, forbidden_action_violation, good_frame_overcorrection, missing_positive_confirmation
- `ca_img_154` / `154.jpg`: confidence_band_mismatch
- `ca_img_211` / `211.jpg`: missing_expected_action
- `ca_img_213` / `213.jpg`: missing_expected_action
- `ca_img_214` / `214.jpg`: confidence_band_mismatch
- `ca_img_216` / `216.jpg`: missing_expected_action, forbidden_action_violation, confidence_band_mismatch
- `ca_img_217` / `217.jpg`: missing_expected_action, missing_future_action
- `ca_img_222` / `222.jpg`: forbidden_action_violation, confidence_band_mismatch
- `ca_img_223` / `223.jpg`: missing_future_action
- `ca_img_225` / `225.jpg`: missing_expected_action, missing_future_action
- `ca_img_228` / `228.jpg`: confidence_band_mismatch
- `ca_img_229` / `229.jpg`: missing_expected_action, confidence_band_mismatch
