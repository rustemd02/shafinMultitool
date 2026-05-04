# Hybrid Eval Summary

Run
- bundle: `camera_analysis_eval_v1_demo`
- anchor: `deterministic_only`
- best local variant: `hybrid_pause_local`

## Executive Summary
- `hybrid_pause_local` -> `mobile_blocked`; `safe_noop_rate=1.00`, `ambiguity_win=n/a`

## Core Non-Regression
- `hybrid_pause_local`: `issue_f1 1.00->1.00`, `primary_action_match_rate 1.00->1.00`, `good_frame_confirmation_rate 1.00->1.00`

## Hybrid Utility
- `hybrid_pause_local`: `safe_noop_rate=1.00`, `case_neural_coverage_rate=0.00`, `applied_fusion_rate=0.00`

## Explainability Agreement
- `hybrid_pause_local`: `fusion_trace_coverage_rate=1.00`, `head_policy_agreement_rate=1.00`, `status_trace_consistency_rate=1.00`

## Mobile Viability
- `hybrid_pause_local`: `pause_latency_p95_ms=n/a`, `live_latency_p95_ms=n/a`, `peak_memory_p95_mb=n/a`

## Ablation Highlights
- `hybrid_pause_local`: pause_execute_success_rate below 0.90

## Representative Cases
- `hybrid_pause_local`: no representative hybrid cases

## Release Recommendation
- `hybrid_pause_local`: verdict `mobile_blocked`
  - pause_execute_success_rate below 0.90
