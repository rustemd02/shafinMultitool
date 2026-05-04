# Camera Analysis Eval Summary

Run:
- bundle: `camera_analysis_eval_v1_demo`
- baseline: `deterministic_only`
- candidate: `hybrid_pause_local`

## Strengths
- `issue_f1`: `1.00` -> `1.00`
- `primary_action_match_rate`: `1.00` -> `1.00`
- `good_frame_confirmation_rate`: `1.00` -> `1.00`

## Issues
- `unsupported_claim_rate`: `0.00` -> `0.00`
- `hint_visibility_policy_accuracy`: `1.00` -> `1.00`
- `hint_jitter_rate`: n/a

## Actions
- `fallback_policy_accuracy`: `1.00` -> `1.00`
- `summary_consistency_rate`: `0.67` -> `0.67`

## Explanation Faithfulness
- `explanation_faithfulness_score`: `0.95` -> `0.95`

## Release / Merge Recommendation

Status: `fail`

Why:
- not enough critical bucket improvements
- no critical regression on issue_f1
- no critical regression on primary_action_match_rate
- good frame confirmation did not regress
- unsupported claims did not increase
