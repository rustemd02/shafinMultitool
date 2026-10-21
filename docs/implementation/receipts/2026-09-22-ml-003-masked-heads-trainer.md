# ML-003 — Production-heads trainer extension with masked losses

Date: 2026-09-22 · Task: tracker §11 **ML-003** · Status row before: `TODO`
Candidate HEAD: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`)
Depends on: ML-002 (`camera_production_heads_v1.md`, closed 2026-09-22), DATA-001/DATA-002.

## Scope of this slice

Trainer/config extension only (Own: `ml/camera_coach/` model/loss/training code).
No training run, no fit, no benchmark generation, no Core ML export, no contract
edits, no receipt rewrites, no commit. The frozen v1/v2 model manifests and their
parity artifacts are untouched; the production-heads contract and validators were
only read.

## What changed (files/symbols)

New file `ml/camera_coach/production_heads.py` — the single owner of the
production head layout for training:

- `ProductionHeadsSpec.load()` — derives the frozen layout read-only from the
  pinned contracts (`camera_release_label_v1.schema.json` → 15 issue ids in
  schema order and the 5 magnitude axes cross-checked against the v1 manifest
  ordering; `camera_release_capability_mapping_v1.json` → exactly the 26
  `disposition=mapped` actions; `camera_production_heads_v1.md` machine-readable
  fence → validates head set `{6 tensor heads + calibration_artifact}`, issue
  coverage and proposed/excluded action sets). Widths:
  `good_frame_probability=1, issue_logits=15, action_utility_logits=26,
  continuous_target_deltas=5, risk_probability=1, abstention_probability=1`.
  `calibration_artifact` is intentionally not a tensor head (CAM-003/ML-007).
  `require_action_supported()` fails closed on the 6 unsupported actions and
  `keep_current_setup`.
- `supervision_from_release_label()` / `ProductionLabelSupervision` /
  `collate` — release-label-shaped records → per-head `(targets, masks)` where
  **the mask is label presence**: `verdict=None`/abstain → good-frame mask 0;
  issue `present`→(1, mask 1), `absent`→(0, mask 1, explicit negative),
  `not_observed`→(0, mask 0, uncertainty); corrective action supervised only on
  its own mapped column, `action=None` masks the whole utility head;
  `magnitude observed` labels one delta axis, absent axes stay masked and are
  never coerced to zero targets; `risk observed` and adjudicated
  `abstention` supervise their single-logit heads.
- `compute_production_heads_loss()` / `ProductionLossWeights` /
  `ProductionLossResult` — masked losses per contract H1–H6, reusing the
  existing `ml.camera_coach.losses` masked primitives
  (`binary_cross_entropy_with_logits` for H1/H2/H3/H5/H6, `smooth_l1_loss`
  for H4 = masked_huber). Targets without an explicit mask are rejected
  (supervision is never implicitly all-ones); a fully masked head reduces to a
  differentiable zero (existing `masked_mean` semantics).
- `ProductionHeadsScorer` — trainer-side head-layout owner (small deterministic
  trunk + one linear head per production tensor head, emitting raw logits).
  It is NOT the frozen v1/v2 export architecture and carries no admission claim.
- `load_research_baseline()` / `ResearchBaseline` / `ResearchBaselineError` —
  loads the old focused silver Stage-2 checkpoint
  (`camera-silver-actions-stage2-checkpoint-v1`, produced by
  `train_silver_actions.py` against the frozen v1 manifest) **only** with an
  explicit `research_only=True` argument; re-verifies the payload's own
  `research_only/human_gold/release_admissible` flags; verifies the old focused
  layout (issue width 8, old action width 26, 5 delta axes); reports
  `trained_heads = {issue, action, deltas}` and
  `untrained_production_heads = {good_frame, risk, abstention}` (contract
  GAP-1/2/3); `production_admitted` is hard-coded `False`.

New file `ml/camera_coach/tests/test_production_heads_trainer.py` — the
synthetic mini-batch check (14 tests, listed below).

No existing file was modified. `git status` delta for this slice is exactly the
two new files plus this receipt.

## How shape/mask/loss are verified (Check)

Command 1 — pinned ML-002 contract check (read-only, unchanged):

```
$ python3 ml/camera_coach/contracts/check_production_heads_v1.py
PASS ML-002 production-heads check
  contract: camera-production-heads-v1 v1.0.0
  heads: 7/7 minimal production entries with target/mask/loss/metric/consumer
  (a) issue coverage: 15/15 DATA-001 issue heads
  (b) consumer symbols verified in camera_release_capability_mapping_v1.json: 41
  (e) action head: 26 proposed = DATA-002 mapped; 7 explicitly excluded
  (d) temporal: deferred_to_ML_011 (separate entry, not a v1 head)
exit=0
```

Command 2 — synthetic mini-batch test (`python3 -m pytest
ml/camera_coach/tests/test_production_heads_trainer.py -q -W error`):

```
14 passed in 1.03s
```

Test inventory and what each proves:

1. `test_spec_matches_pinned_production_contracts` — widths {1,15,26,5,1,1};
   5 mapped technical actions present (`stabilize_camera`, `refocus_subject`,
   `reduce_exposure`, `increase_exposure`, `avoid_occlusion`); the 4 unsupported
   semantic actions + `clean_lens`, `reduce_iso_noise`, `keep_current_setup`
   excluded.
2. `test_scorer_emits_exact_production_head_shapes` — outputs are exactly the 6
   tensor heads in frozen order, `[B, W]` per spec, finite;
   `calibration_artifact` absent.
3. `test_absent_label_is_masked_and_not_a_zero_target` — an absent label yields
   mask 0 with a zero placeholder target, never a zero-class label.
4. `test_issue_status_semantics_present_absent_not_observed` — present=(1,1),
   absent=(0,1) explicit negative, not_observed=(0,0) uncertainty.
5. `test_missing_label_and_explicit_zero_target_are_not_the_same_supervision` —
   the explicit anti-confusion proof: mask 0 gives loss exactly 0 and gradient
   exactly 0; mask 1 with target 0 gives loss > 0 and gradient
   `sigmoid(0.75) ≠ 0`; under mask 0 the target value (0 vs 1) changes neither
   loss nor gradient. Masking is via the mask, not via zero-target substitution.
6. `test_unsupported_and_app_only_actions_fail_closed` — unsupported/app-only/
   unknown action ids raise instead of being silently masked.
7. `test_delta_absent_axis_is_masked_never_coerced_to_zero_target` — the
   observed axis is supervised with its value; the other 4 axes stay masked.
8. `test_synthetic_minibatch_loss_is_finite_and_backward_reaches_only_masked_positions`
   — 4-record batch with mixed partial labels: total and per-head losses finite;
   backward-only-on-mask (abstaining row and never-labelled action columns have
   exactly zero gradient; good-frame gradient absent exactly on the abstain row;
   risk gradient only on its adjudicated row).
9. `test_synthetic_minibatch_train_step_reduces_masked_loss` — 40 SGD steps on
   the batch: loss finite and strictly decreasing; the never-labelled
   `delta_y` head row received exactly zero gradient while the supervised
   `delta_x` row received non-zero gradient.
10. `test_fully_masked_head_keeps_total_differentiable` — all masks zero →
    differentiable zero total, backward produces non-None zero gradients.
11. `test_research_baseline_requires_explicit_research_only_flag` — default and
    `research_only=False` raise with `research_only=True` guidance; the explicit
    call returns flags `research_only=True / human_gold=False /
    release_admissible=False / production_admitted=False`, the 3 trained heads,
    the 3 untrained production heads, old layout widths 8/26/5, sha256.
12. `test_research_baseline_rejects_payload_with_production_claim` — a payload
    with any of `research_only=False`, `human_gold=True`,
    `release_admissible=True` is rejected even with the explicit flag.
13. `test_research_baseline_rejects_non_focused_layout` — an issue width of 15
    is not the focused research layout and is rejected (no silent partial load).
14. `test_baseline_state_cannot_load_into_the_production_head_layout` —
    `load_state_dict(strict=True)` of the baseline state into
    `ProductionHeadsScorer` raises `RuntimeError`: the compatibility boundary
    is structural, not conventional.

Regression (no interference with the existing trainer/loss/model tests):

```
$ python3 -m pytest ml/camera_coach/tests/ -q
74 passed, 7 warnings in 44.16s
```

(60 pre-existing tests + the 14 new ones; afterwards the new file was warning-
cleaned and re-run with `-W error`: 14 passed.)

Environment: macOS arm64, `python3` 3.11.9 (framework build),
`torch 2.10.0` (CPU), `pytest 9.0.2`.

## Research baseline compatibility

The old focused checkpoint stays loadable **only** as a research baseline:
`load_research_baseline(path, research_only=True)` validates the
`camera-silver-actions-stage2-checkpoint-v1` schema, the payload's own
research-only flags, and the frozen v1 layout, and returns metadata that cannot
be presented as a production claim (`production_admitted=False` is structural).
Loading it into the production 15-issue / 26-mapped-action layout fails with an
explicit width error (tests 13–14). The real silver-fit checkpoint itself lives
outside the repo (`setos-backend/local-data/SETOS/`, current canonical tree does
not contain `silver-fit-20260918-stage2-q8m2v4/` at the documented path); the
tests synthesize a payload with the exact old schema/layout to verify the
loader without touching local data.

## Limitations (explicit)

- No training run happened; nothing here measures quality. Final fit requires
  DATA-016 and human-gold data (DATA-010/011) per tracker §7.
- `ProductionHeadsScorer` is a trainer-side head-layout owner, not the export
  architecture; backbone/final architecture selection and Core ML
  export/parity/admission remain ML-004/005 and ML-012/013/014.
- `calibration_artifact` is out of scope here (CAM-003 loading, ML-007 fit).
- Temporal heads are deferred to the ML-011 decision, as pinned by the contract.
- The intent-admissibility mask (frozen v2 `merge_intent_supervision_mask`)
  is not reimplemented; the caller can compose it on top of the label-presence
  masks.
- `supervision_from_release_label` validates the supervised sections it owns
  (verdict/issues/action/risk/abstention); full `camera_release_label_v1`
  schema validation stays with the DATA-001 validator.
- Status update of tracker row ML-003 is left to the orchestrator; this receipt
  is the evidence.
