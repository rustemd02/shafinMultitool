# Semantic Label Eval Summary

Candidate: `semantic_eval_real_runtime_candidate_outputs_after_r17a`

## Set Metrics

- `record_count`: 107
- `pass_rate`: 0.803738
- `expected_action_hit_rate`: 0.981308
- `future_action_hit_rate`: 0.958333
- `forbidden_action_violation_rate`: 0.0
- `good_frame_preservation_rate`: 1.0
- `technical_failure_gate_rate`: 1.0
- `positive_confirmation_rate`: 1.0
- `confidence_band_accuracy`: 0.82243
- `demo_priority_pass_rate`: 0.928571

## Failure Counts

- `confidence_band_mismatch`: 19
- `missing_expected_action`: 2
- `missing_future_action`: 2

## First Failed Cases

- `ca_img_002` / `002.jpg`: confidence_band_mismatch
- `ca_img_010` / `010.jpg`: confidence_band_mismatch
- `ca_img_013` / `013.jpeg`: missing_expected_action, confidence_band_mismatch
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
- `ca_img_074` / `074.bmp`: missing_expected_action
- `ca_img_077` / `077.jpg`: confidence_band_mismatch
- `ca_img_078` / `078.bmp`: confidence_band_mismatch
- `ca_img_082` / `082.bmp`: confidence_band_mismatch
- `ca_img_090` / `090.jpg`: confidence_band_mismatch
- `ca_img_097` / `097.bmp`: missing_future_action
