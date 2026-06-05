# Synthetic Bad Labels v1

Status: deterministic synthetic benchmark expansion.
Created: 2026-06-04.

This label set covers `178...207`, generated from Apple TV Press seed frames.
It is intentionally separate from `semantic_labels_v1.jsonl` so the original 107-record silver set remains stable.

## Recipe Counts

- `background_clutter`: 4
- `crooked_horizon`: 4
- `edge_cutoff`: 3
- `low_contrast_noise`: 3
- `motion_blur`: 4
- `overexposed_hotspot`: 4
- `too_much_empty_space`: 4
- `underexposed_subject`: 4

## Boundary

- These are paired stress cases, not organic camera captures.
- The expected actions are derived from known synthetic recipes and must be spot-checked before calling them gold.
- Technical-only cases intentionally use `future_needed_actions` without composition actions.
