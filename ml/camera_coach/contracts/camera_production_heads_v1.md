# Camera Coach production heads contract v1

Status: **model-architecture contract; authority `ML-002`**.
Depends on: `camera_release_label_v1.schema.json` (DATA-001) and
`camera_release_capability_mapping_v1.json` (DATA-002). It defines the
minimal production head set for the still-image scorer; it does not change
schemas, validators, trainer code, or admit any model.

The machine-readable owner is the fenced JSON block at the end of this
document. Run the bounded check with:

```bash
python3 ml/camera_coach/contracts/check_production_heads_v1.py
```

## Boundary and decision split

Owner decision 2026-09-22 (tracker §7): **the model proposes
verdict/issue/action/target/delta; the app verifies** contract validity,
freshness, target identity, action permission, calibration, risk, and
verification availability. Presence of a trained head never implies runtime
support: every head below remains non-admitted until ML-003…ML-018,
CAM-003/CAM-010…CAM-012, and SEC-007 close their gates.

- The minimal production set is exactly seven entries: six tensor heads plus
  one calibration artifact. `scene_class_logits`,
  `subjectness_roi_agreement_logits` (planned, required by no blocked
  capability) and `embedding` (`not_a_release_target`) are outside the
  production set.
- Target identity/selection is **app-owned** in v1 (DATA-002 capability
  `selection` is `app_only`, owners `CameraAnalysisV3Contract` /
  `CoachingEpisodeCoordinator`). The model receives the app-resolved ROI as
  its existing input and proposes target-scoped deltas, risk, and abstention;
  v1 adds no neural identity head. Identity mismatch still fails closed.
- `keep_current_setup` is never a neural utility output. It stays the
  deterministic app-side policy projection of good-frame/abstention gates
  (DATA-002 action disposition `app_only`).
- Actions with DATA-002 disposition `unsupported` are never supervised and
  never proposed; the app safety gate would suppress them anyway, and the
  trainer head simply does not contain them.

## Production heads

### H1. `good_frame_probability` — verdict/good

- **Target:** calibrated probability that the current frame needs no
  corrective advice (label `verdict=good` versus `needs_fix`/`mixed`).
- **Mask:** `good_frame_supervision_mask` — only human-gold frames with an
  adjudicated non-null verdict; explicit `abstain` frames are excluded (they
  belong to H6); `not_observed` is never a negative label.
- **Loss:** `masked_bce` (single logit).
- **Metric:** AUROC, ECE, Brier on the locked calibration/holdout splits;
  Gate C2 `good_frame_preservation_rate >= 0.95` and
  `confidence_band_accuracy >= 0.90` on the integrated runtime.
- **App consumer:** `CameraAdviceSafetyGate.evaluate` (positive/keep
  projection gate), `CameraOverlayUXPresentation.make`, and
  `CoachingEpisodeCoordinator` episode state.
- **Gap vs current checkpoint:** not trained at all (`planned` only in
  DATA-002 `trainer_heads`); the silver fit measures no good-frame target.

### H2. `issue_logits` — 15 release issue heads

- **Target:** per-head presence probability for **all 15** DATA-001 issue
  IDs: the 8 `IssueTypeV1` semantic heads plus the 7
  `TechnicalQualityIssueType` heads (`motion_blur`, `defocus`,
  `overexposure`, `underexposure`, `noise`, `occlusion`, `lens_smudge`).
- **Mask:** `issue_supervision_mask` extended to 15 columns, per example and
  per head; `status=absent` is an explicit negative, `status=not_observed`
  is masked out of the loss (uncertainty, not zero).
- **Loss:** `masked_bce_with_logits` per head.
- **Metric:** per-head AUROC/ECE plus per-head false-positive rate on
  adjudicated good frames (ML-006; positive-only accuracy is not admissible
  evidence), feeding Gate C2 `pass_rate >= 0.90` and
  `forbidden_action_violation_rate <= 0.02`.
- **App consumer:** `IssueTypeV1`, `TechnicalQualityIssueType`,
  `CameraAnalysisV3ContractValidator`, `TechnicalQualityAnalyzer`, and
  `CameraBoundedActionPlanner.plan`.
- **Gap vs current checkpoint:** the trained `issue_logits` row covers only
  8 of 15 heads; the 7 technical issue heads are untrained, and the
  silver-positive-only recipe never measured false positives on good frames.

### H3. `action_utility_logits` — 26 supported actions only

- **Target:** utility probability for each of the **26 actions with DATA-002
  disposition `mapped`** (21 semantic + 5 technical: `stabilize_camera`,
  `refocus_subject`, `reduce_exposure`, `increase_exposure`,
  `avoid_occlusion`). Excluded: the 6 `unsupported` actions
  (`rotate_subject_toward_light`, `reposition_prop_for_balance`,
  `remove_background_hotspot`, `simplify_background`, `clean_lens`,
  `reduce_iso_noise`) and `keep_current_setup` (`app_only`).
- **Mask:** `action_utility_supervision_mask` over the 26 columns; an action
  is supervised only where the human label records a corrective action;
  keep-frames and `not_observed` magnitudes contribute no positive target.
- **Loss:** `masked_bce_with_logits` (multi-label utility).
- **Metric:** masked top-1 hit rate per action family, wrong-direction and
  wrong-magnitude errors reported separately (ML-006); Gate C2
  `expected_action_hit_rate >= 0.90`, `forbidden_action_violation_rate <=
  0.02`, zero critical violations in the reviewed safety set.
- **App consumer:** `SemanticActionType`, `CameraBoundedActionPlanner.plan`,
  `CameraAdviceSafetyGate.evaluateAdmissibility`,
  `SETCameraCopy.actionKey(forCanonicalActionID`, `ActionVerifier.verify`;
  exposure execution via `ExposureFeatureSignals.applyProControl` /
  `proControlsSnapshotAndWait()` stays app-owned.
- **Gap vs current checkpoint:** the trained row names a **different** 26:
  it includes 4 actions that DATA-002 marks `unsupported`
  (`rotate_subject_toward_light`, `reposition_prop_for_balance`,
  `remove_background_hotspot`, `simplify_background`) and excludes the 5
  mapped technical actions including `avoid_occlusion`. The production head
  is the DATA-002 `mapped` set, not the current trainer ordering.

### H4. `continuous_target_deltas` — target-scoped magnitudes

- **Target:** normalized magnitude for the commanded action on the label
  `magnitude` axes (`delta_x`, `delta_y`, `scale_delta`, `light_delta`,
  `horizon_delta`), scoped to the app-resolved target ROI.
- **Mask:** `continuous_target_deltas_mask`; only frames with an observed
  magnitude label contribute; an absent delta is masked, never coerced to
  zero.
- **Loss:** `masked_huber`.
- **Metric:** MAE, RMSE, within-tolerance rate versus the verifier deadband;
  wrong-direction success must be 0 (§4 release evidence, Gate C2/C3).
- **App consumer:** `CameraBoundedActionPlanner.plan` (copy magnitude),
  `ActionVerifier.verify` (deadband/goal predicate),
  `CameraOverlayUXPresentation.make` (region/arrow presentation).
- **Gap vs current checkpoint:** the row exists (`research_only_current`)
  but is silver-supervised only; human-gold magnitudes are 0 (DATA-004) and
  the tolerance/deadband gate is unmeasured.

### H5. `risk_probability` — safety risk of the proposed advice

- **Target:** probability that emitting the current proposal is unsafe or
  permission-violating (people/consent-sensitive movement, movable/permission
  uncertainty, hazardous instruction), independent of issue presence.
- **Mask:** `risk_supervision_mask`; only frames whose label carries
  `risk.status=observed` with an adjudicated probability band.
- **Loss:** `masked_bce`.
- **Metric:** AUROC, ECE, Brier; safety reporting is separate from average
  accuracy (ML-006/ML-008); Gate C2 `forbidden_action_violation_rate <=
  0.02` and zero critical violations in the reviewed safety set.
- **App consumer:** `CameraAdviceSafetyGate.evaluateAdmissibility` and
  `CoachingEpisodeCoordinator` suppression decisions.
- **Gap vs current checkpoint:** not trained (`planned` only).

### H6. `abstention_probability` — honest abstention

- **Target:** probability that the model should abstain (no confident
  verdict/action) for the frame. Abstention *reason codes*
  (`ambiguous_subject`, `unsupported_case`, `protected_intent`, …) stay
  deterministic app-side in v1; the head emits the probability only.
- **Mask:** `abstention_supervision_mask`; frames with adjudicated
  `abstention.status` (`abstain` or `none`); `not_observed` is masked.
- **Loss:** `masked_bce`.
- **Metric:** AUROC, ECE, selective-risk/risk-coverage curve (ML-007);
  Gate C2 `good_frame_preservation_rate` and honest-abstention behavior in
  Gate C3; abstention is reported separately, never folded into average
  accuracy (§5 DoD).
- **App consumer:** `CameraAdviceSafetyGate.evaluate` (silent/ask decision),
  `CoachingEpisodeCoordinator` (episode state),
  `CameraOverlayUXPresentation.make` (no-advice presentation).
- **Gap vs current checkpoint:** not trained (`planned` only); the current
  closed-loop suite already fails closed on `calibration_unavailable`.

### H7. `calibration_artifact` — calibrated thresholds (not a tensor head)

- **Target:** per-head calibration mapping (temperature/isotonic plus
  show/silent thresholds) over H1–H6 outputs, fit on the frozen calibration
  split; artifact schema and fail-closed loading are owned by CAM-003
  (`CameraConfidenceCalibrator` path, mentioned here for routing only — the
  symbol is not part of the DATA-002 consumer allowlist).
- **Mask:** frozen calibration partition of human-gold records only;
  research-only and silver records never fit production calibration.
- **Loss:** not a gradient head — NLL/ECE minimization objective on the
  calibration split (`not_a_gradient_head`).
- **Metric:** ECE and reliability curves per head, selective risk at chosen
  thresholds; Gate C2 `confidence_band_accuracy >= 0.90`.
- **App consumer:** `CameraAdviceSafetyGate.evaluateAdmissibility` /
  `CameraAdviceSafetyGate.evaluate` consume calibrated confidence;
  `CoachingEpisodeCoordinator` owns the unavailable → fail-closed state.
- **Gap vs current checkpoint:** no calibration artifact exists;
  `CameraConfidenceCalibrator` remains unavailable.

## Temporal — explicitly deferred (ML-011 decision)

Temporal outcome modeling (before/after `fixed/improved/unchanged/worse`,
target-lost, scene/lens change) is **not** a v1 production head. Per tracker
§7 and ML-011: first evaluate the existing target-scoped `ActionVerifier`
(CAM-004/005/006 evidence) on locked temporal clips; a separate temporal
scorer is trained only for a proven gap in a supported action family.
Temporal labels/splits belong to DATA-013/DATA-014. The still-image export
(ML-012) does not wait for a temporal scorer.

## Excluded from the v1 production set

- `scene_class_logits`, `subjectness_roi_agreement_logits`: `planned`
  research heads; no blocked DATA-002 capability references them; they stay
  out of the minimal set until a named capability requires them.
- `embedding`: `not_a_release_target` internal representation.
- Neural target-identity head: replaced by the app-owned selection path
  (capability `selection`, `app_only`).

## Named gaps of the current Stage-2 checkpoint

1. **GAP-1:** trains only `issue_logits`, `action_utility_logits`,
   `continuous_target_deltas`; `good_frame_probability`, `risk_probability`,
   `abstention_probability` are untrained.
2. **GAP-2:** issue head covers 8/15 (all 7 technical issue heads missing).
3. **GAP-3:** action head names the wrong 26 (4 unsupported semantic actions
   included, 5 mapped technical actions missing).
4. **GAP-4:** no calibration artifact; `CameraConfidenceCalibrator`
   unavailable; no show/silent thresholds.
5. **GAP-5:** positive-only silver issue metric never measured false
   positives on good frames; no risk/abstention supervision exists.
6. **GAP-6:** temporal verification unmodeled — deferred by design to the
   ML-011 decision, not a trainer defect.
7. **GAP-7:** silver-only supervision with `human_gold=0` corpus (DATA-004);
   final fit requires DATA-016 and masked human-gold losses (ML-003).

## Machine-readable block

<!-- camera-production-heads-v1:machine-readable-begin -->
```json
{
  "contract_id": "camera-production-heads-v1",
  "contract_version": "1.0.0",
  "authority": "ML-002",
  "depends_on": ["DATA-001", "DATA-002"],
  "decision_split": "model proposes verdict/issue/action/delta; app verifies contract, freshness, identity, permission, calibration, risk, verification availability",
  "heads": [
    {
      "head_id": "good_frame_probability",
      "role": "verdict_good",
      "target": "calibrated probability the frame needs no corrective advice (label verdict=good vs needs_fix/mixed)",
      "mask": "good_frame_supervision_mask: human-gold frames with adjudicated non-null verdict; abstain frames excluded; not_observed never a negative label",
      "loss": "masked_bce (single logit)",
      "metric": "AUROC + ECE + Brier; Gate C2 good_frame_preservation_rate >= 0.95 and confidence_band_accuracy >= 0.90",
      "consumer": ["enum CameraAdviceSafetyGate", "static func evaluate(", "struct CameraOverlayUXPresentation", "static func make(", "struct CoachingEpisodeCoordinator"],
      "gap_refs": ["GAP-1", "GAP-4", "GAP-5"]
    },
    {
      "head_id": "issue_logits",
      "role": "issue_presence",
      "target": "per-head presence probability for all 15 DATA-001 issue ids (8 IssueTypeV1 semantic + 7 TechnicalQualityIssueType technical)",
      "mask": "issue_supervision_mask extended to 15 columns per example per head; absent=explicit negative; not_observed masked out",
      "loss": "masked_bce_with_logits per head",
      "metric": "per-head AUROC/ECE plus per-head false-positive rate on adjudicated good frames (ML-006); Gate C2 pass_rate >= 0.90, forbidden_action_violation_rate <= 0.02",
      "consumer": ["enum IssueTypeV1", "enum TechnicalQualityIssueType", "enum CameraAnalysisV3ContractValidator", "struct TechnicalQualityAnalyzer", "enum CameraBoundedActionPlanner", "static func plan("],
      "covered_issue_ids": [
        "subject_too_close_to_edge",
        "subject_not_prominent_enough",
        "background_competes_with_subject",
        "insufficient_look_space",
        "backlight_hides_subject",
        "scene_has_no_clear_focus",
        "frame_visually_overloaded",
        "horizon_distracts",
        "motion_blur",
        "defocus",
        "overexposure",
        "underexposure",
        "noise",
        "occlusion",
        "lens_smudge"
      ],
      "gap_refs": ["GAP-2", "GAP-5", "GAP-7"]
    },
    {
      "head_id": "action_utility_logits",
      "role": "action_utility",
      "target": "utility probability for each of the 26 DATA-002 disposition=mapped actions (21 semantic + 5 technical); unsupported actions never supervised or proposed; keep_current_setup stays app-only policy output",
      "mask": "action_utility_supervision_mask over 26 columns; supervised only where the human label records a corrective action; keep-frames and not_observed contribute no positive target",
      "loss": "masked_bce_with_logits (multi-label utility)",
      "metric": "masked top-1 hit rate per action family; wrong-direction and wrong-magnitude errors separate (ML-006); Gate C2 expected_action_hit_rate >= 0.90, forbidden_action_violation_rate <= 0.02, zero critical safety-set violations",
      "consumer": ["enum SemanticActionType", "enum CameraBoundedActionPlanner", "static func plan(", "enum CameraAdviceSafetyGate", "static func evaluateAdmissibility(", "enum SETCameraCopy", "static func actionKey(forCanonicalActionID", "enum ActionVerifier", "static func verify(", "enum ExposureFeatureSignals", "func applyProControl(", "func proControlsSnapshotAndWait()"],
      "proposed_action_ids": [
        "shift_frame_left",
        "shift_frame_right",
        "shift_frame_up",
        "shift_frame_down",
        "step_back",
        "step_closer",
        "lower_camera",
        "raise_camera",
        "change_camera_angle",
        "level_horizon",
        "move_subject_left",
        "move_subject_right",
        "move_subject_away_from_background",
        "move_object_left",
        "move_object_right",
        "move_object_forward",
        "move_object_back",
        "remove_distracting_object",
        "add_front_fill_light",
        "add_background_light",
        "wait_for_background_clearance",
        "stabilize_camera",
        "refocus_subject",
        "reduce_exposure",
        "increase_exposure",
        "avoid_occlusion"
      ],
      "excluded_action_ids": [
        "rotate_subject_toward_light",
        "reposition_prop_for_balance",
        "remove_background_hotspot",
        "simplify_background",
        "clean_lens",
        "reduce_iso_noise",
        "keep_current_setup"
      ],
      "gap_refs": ["GAP-3", "GAP-7"]
    },
    {
      "head_id": "continuous_target_deltas",
      "role": "target_deltas",
      "target": "normalized magnitude for the commanded action on the label magnitude axes (delta_x, delta_y, scale_delta, light_delta, horizon_delta), scoped to the app-resolved target ROI",
      "mask": "continuous_target_deltas_mask: only observed-magnitude labels contribute; absent delta masked, never coerced to zero",
      "loss": "masked_huber",
      "metric": "MAE, RMSE, within-tolerance rate vs verifier deadband; wrong-direction success must be 0 (release section 4, Gate C2/C3)",
      "consumer": ["enum CameraBoundedActionPlanner", "static func plan(", "enum ActionVerifier", "static func verify(", "struct CameraOverlayUXPresentation", "static func make("],
      "gap_refs": ["GAP-7"]
    },
    {
      "head_id": "risk_probability",
      "role": "risk",
      "target": "probability that emitting the current proposal is unsafe or permission-violating (consent-sensitive movement, movable/permission uncertainty, hazardous instruction), independent of issue presence",
      "mask": "risk_supervision_mask: only frames whose label carries risk.status=observed with an adjudicated probability",
      "loss": "masked_bce",
      "metric": "AUROC + ECE + Brier; safety failures reported separately from average accuracy (ML-006/ML-008); Gate C2 forbidden_action_violation_rate <= 0.02 and zero critical safety-set violations",
      "consumer": ["enum CameraAdviceSafetyGate", "static func evaluateAdmissibility(", "struct CoachingEpisodeCoordinator"],
      "gap_refs": ["GAP-1", "GAP-5"]
    },
    {
      "head_id": "abstention_probability",
      "role": "abstention",
      "target": "probability that the model should abstain (no confident verdict/action); abstention reason codes stay deterministic app-side in v1",
      "mask": "abstention_supervision_mask: frames with adjudicated abstention.status (abstain or none); not_observed masked",
      "loss": "masked_bce",
      "metric": "AUROC + ECE + selective-risk/risk-coverage curve (ML-007); abstention reported separately (DoD); Gate C2 good_frame_preservation_rate and Gate C3 honest-abstention behavior",
      "consumer": ["enum CameraAdviceSafetyGate", "static func evaluate(", "struct CoachingEpisodeCoordinator", "struct CameraOverlayUXPresentation", "static func make("],
      "gap_refs": ["GAP-1", "GAP-4", "GAP-5"]
    },
    {
      "head_id": "calibration_artifact",
      "role": "calibration",
      "target": "per-head calibration mapping (temperature/isotonic + show/silent thresholds) over the six tensor heads, fit on the frozen calibration split; artifact schema and fail-closed loading owned by CAM-003",
      "mask": "frozen calibration partition of human-gold records only; research-only and silver records never fit production calibration",
      "loss": "not_a_gradient_head: NLL/ECE minimization objective on the calibration split",
      "metric": "ECE and reliability curves per head; selective risk at chosen thresholds; Gate C2 confidence_band_accuracy >= 0.90",
      "consumer": ["enum CameraAdviceSafetyGate", "static func evaluateAdmissibility(", "static func evaluate(", "struct CoachingEpisodeCoordinator"],
      "gap_refs": ["GAP-4"]
    }
  ],
  "temporal": {
    "head_id": "temporal_outcome_verification",
    "status": "deferred_to_ML_011",
    "reason": "no v1 temporal head: first evaluate the existing target-scoped ActionVerifier on locked temporal clips; a separate temporal scorer is trained only for a proven gap in a supported action family; temporal labels/splits belong to DATA-013/DATA-014",
    "tracker_dependencies": ["ML-011", "DATA-013", "DATA-014"]
  },
  "excluded_from_production": [
    {"head_id": "scene_class_logits", "reason": "planned research head; no blocked DATA-002 capability references it"},
    {"head_id": "subjectness_roi_agreement_logits", "reason": "planned research head; target identity/selection is app-owned (capability selection, app_only)"},
    {"head_id": "embedding", "reason": "not_a_release_target internal representation"}
  ],
  "named_gaps_of_current_checkpoint": [
    "GAP-1: trains only issue_logits/action_utility_logits/continuous_target_deltas; good/risk/abstention untrained",
    "GAP-2: issue head covers 8/15; all 7 technical issue heads missing",
    "GAP-3: action head names the wrong 26 (4 unsupported included, 5 mapped technical missing)",
    "GAP-4: no calibration artifact; CameraConfidenceCalibrator unavailable",
    "GAP-5: positive-only silver issue metric; no good-frame false-positive or risk/abstention supervision",
    "GAP-6: temporal verification unmodeled (deferred to ML-011 by design)",
    "GAP-7: silver-only supervision; human_gold=0 (DATA-004); final fit requires DATA-016"
  ]
}
```
<!-- camera-production-heads-v1:machine-readable-end -->
