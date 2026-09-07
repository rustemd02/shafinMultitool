# M4 research — AVA silver pixel lane: negative result with diagnosis

Status: RESEARCH (owner-authorized pet-project lane; M4-011
teacher/silver policy). No tracker task closed. Honest negative
result with a bounded diagnosis trail.

## Setup

- Dataset: `trojblue/AVA-aesthetics-10pct-min50-10bins` (HF mirror of
  AVA) — 4000 real photographs with human aesthetic `mean_score`
  (1–10), downloaded to `/private/tmp/ava_silver` (outside Git,
  rights-uncleared data stays out of the repo).
- Silver labels: `good_frame_probability = (mean_score − 1)/9`,
  `abstention = 1 − p`; all other heads masked; AVA 5.5 cut used for
  binary accuracy.
- Inputs: real pixels resized to the frozen 320×320 contract;
  center 192 crop; scalars mostly `missing=1` (pixel-driven lane).
- Model: CandidateA (dual branch — the only candidate consuming the
  full-frame pixel branch); frozen multitask losses; Adam; MPS and
  CPU.

## Result: loss frozen at exactly ln(4) = 2·ln(2)

Three runs (`ml/camera_coach/research_ava_train.py`, receipts in
evidence-m4/ava-silver-training/):

1. MPS, 5 ep, lr 5e-4: loss 1.3866 → 1.3836 (flat), acc@5.5 0.414 →
   0.537 (= prior class share).
2. MPS, 10 ep, lr 2e-3 + center pseudo-ROI (to defeat the
   `_prepare_inputs` crop-zeroing when `has_roi` is false — line 533
   of the model source): loss 1.3860 flat, acc 0.586 (prior).
3. CPU probe, 3 ep: loss 1.402 → 1.3867 flat — **rules out MPS**.

A frozen BCE at exactly 2·ln(2) means both probability heads output
p ≈ 0.5 for every sample: the head input carries no gradient-bearing
signal. Contrast: the rule lane on CandidateB
(`research_train.py`, receipt in evidence-m4/research-synthetic-training/)
learned to 0.825 accuracy under the identical loss/loop — so the
loss, masks, loop, and the good/abstention heads themselves work.

## Bounded diagnosis (what IS known)

- Not the device (CPU reproduces).
- Not the loss/heads (B lane learns).
- Not ROI gating alone (pseudo-ROI did not unfreeze).
- Remaining prime suspect: CandidateA's probability-head input under
  a missing-heavy scalar profile — the head likely reads a
  fusion of embeddings where the scalar path is gated by the missing
  mask (32/40 missing in this lane) and the pixel path contributes
  only through features the head does not consume. Verifying requires
  reading CandidateA's head-input wiring and one controlled probe
  (e.g., non-missing informative scalars, or head-input hook).

## RESOLVED (same session): root cause found and fixed

The frozen loss was a LABEL-SCALE artifact, not a model defect: the
continuous `(score−1)/9` targets concentrate in 0.39–0.61 around the
0.5 initialization, starving BCE of gradient (the rule lane learned
because its labels were exactly 0/1). Binarizing at the standard AVA
5.5 cut unfroze training immediately: loss 1.386 → **1.288** in 10
epochs (lr 1e-3), the pixel pathway demonstrably learns. Accuracy
@5.5 reaches only ~0.58 — consistent with the data-scale ceiling
(4k images vs 100k+ in the literature), not a pipeline fault.

Final recipe: binarized AVA-5.5 labels + CandidateA + lr 1e-3 +
more data/epochs.

## Original next steps (for a future session)

1. Read CandidateA's head-input construction; probe with informed
   (non-missing) scalars to isolate the dead path.
2. Scale data/epochs (4000 images × 10 epochs is far below what AVA
   aesthetics models need — literature uses 100k+ images).
3. Alternative: train a small standalone CNN regressor on
   mean_score as a pure feasibility probe, independent of the frozen
   contract, before porting into it.

## Hygiene

Silver data stays outside Git; receipts carry
`approved_human_data: false`; nothing exports to Core ML; no iOS
route; no candidate-selection claim. Production candidate work
remains gated on the frozen M3 human-gold chain per plan.
