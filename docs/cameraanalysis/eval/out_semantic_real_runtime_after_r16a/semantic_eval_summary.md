# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_after_r16a`

## Set Metrics

- `record_count`: 107
- `pass_rate`: 0.728972
- `expected_action_hit_rate`: 0.925234
- `future_action_hit_rate`: 0.916667
- `forbidden_action_violation_rate`: 0.018692
- `good_frame_preservation_rate`: 1.0
- `technical_failure_gate_rate`: 1.0
- `positive_confirmation_rate`: 0.956522
- `confidence_band_accuracy`: 0.803738
- `demo_priority_pass_rate`: 0.857143

## Failure Counts

- `confidence_band_mismatch`: 21
- `forbidden_action_violation`: 2
- `missing_expected_action`: 8
- `missing_future_action`: 4
- `missing_positive_confirmation`: 2

## First Failed Cases

- `ca_img_002` / `002.jpg`: confidence_band_mismatch
- `ca_img_009` / `009.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_010` / `010.jpg`: confidence_band_mismatch
- `ca_img_013` / `013.jpeg`: missing_expected_action, confidence_band_mismatch
- `ca_img_020` / `020.jpg`: missing_expected_action, missing_positive_confirmation
- `ca_img_022` / `022.jpg`: confidence_band_mismatch
- `ca_img_024` / `024.jpg`: confidence_band_mismatch
- `ca_img_027` / `027.jpg`: confidence_band_mismatch
- `ca_img_029` / `029.jpg`: confidence_band_mismatch
- `ca_img_035` / `035.jpg`: confidence_band_mismatch
- `ca_img_037` / `037.jpg`: confidence_band_mismatch
- `ca_img_043` / `043.jpg`: confidence_band_mismatch
- `ca_img_044` / `044.jpg`: confidence_band_mismatch
- `ca_img_050` / `050.jpg`: confidence_band_mismatch
- `ca_img_052` / `052.jpg`: confidence_band_mismatch
- `ca_img_053` / `053.jpg`: confidence_band_mismatch
- `ca_img_072` / `072.jpg`: missing_future_action
- `ca_img_074` / `074.bmp`: missing_expected_action
- `ca_img_077` / `077.jpg`: confidence_band_mismatch
- `ca_img_078` / `078.bmp`: confidence_band_mismatch
