# M4 research lane — synthetic rule-label training evidence

Status: RESEARCH (owner-authorized 2026-09-07). NOT a production
candidate; no M4 tracker task is closed by this — M4-012/014 remain
gated on frozen human gold (M3-022) exactly as the plan requires.

## What ran

`ml/camera_coach/research_train.py` against the frozen
SETCompositionNet-v1 contract and the frozen loss weights:

- **Generated inputs**: 800 deterministic samples (seed 20260907)
  conforming to the manifest input contract (full frame, subject
  crop, in-frame ROI, ROI mask, in-range scalar features, missing
  mask). Labels are a KNOWN composition rule over ROI features
  (subject present; center inside rule-of-thirds bounds; area in
  [0.05, 0.35]) → `good_frame_probability`, with
  `abstention_probability = 1 − good`; all other heads masked out.
- **Trained**: candidate_b_roi_conditioned_ablation, Adam 1e-3,
  batch 32, 12 epochs on CPU, frozen multitask loss
  (`compute_multitask_loss`).
- **Evaluated** on a held-out 160-sample synthetic split.

## Results (receipt.json)

| metric | before | after 12 epochs |
|---|---|---|
| rule-label accuracy | 0.175 | **0.825** |
| mean absolute error | 0.514 | **0.175** |

The model recovered the injected rule from raw contract features —
the training environment (data → train → eval) works end-to-end.
Accuracy plateaus at the 7/8 ROI-present prior; MAE ≈ 1/8 tracks the
no-ROI share, i.e., the residual is the ambiguous no-subject slice
where the rule is least expressible from the ROI alone.

## Why this does not close M4 tasks

`approved_human_data: false` is stamped in the receipt. The plan's
M4-012/014 acceptance requires the frozen M3 human-gold split,
two-annotator calibration, and adjudication — synthetic rule labels
validate mechanics, not coach semantics. The human-gold chain drops
into this exact harness unchanged (replace the sample builder).

Runtime: 645 s CPU; torch 2.10.0.
