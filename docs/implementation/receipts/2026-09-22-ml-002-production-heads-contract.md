# ML-002 receipt — production heads contract

Date: 2026-09-22
Candidate HEAD at authoring: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee` (branch `store`)
Scope: contract documentation plus its bounded check script only. No schema, validator, trainer code, model weights, app source, or local/raw data was changed. No training was run. No git commit/push was performed; pre-existing working-tree changes from other tasks were left untouched.

## Method

1. Read the tracker (§0–2, §7, §11 ML-002), `AGENTS.md`, `camera_release_label_v1.schema.json` (15 issue IDs, 33 action IDs, verdict/risk/abstention/intent/before_after), `camera_release_capability_mapping_v1.md` + `.json` (trainer head states, 20 capabilities: 8 blocked / 12 app_only / 6 deferred; 33/33 action dispositions; 12-source consumer allowlist), `INTEGRATION.md`, `PRODUCTION_ACCEPTANCE.md` Gate C2, and the current Stage-2 trainer surface (`models/set_composition_net_v2.py`, `losses.py`).
2. Decided the minimal production head set strictly from the DATA-002 capability references: every blocked capability requires exactly `issue_logits`, `action_utility_logits`, `good_frame_probability`, `risk_probability`, `abstention_probability`, `continuous_target_deltas`; calibration is added as the CAM-003/ML-007 artifact; everything else (scene/subjectness/embedding, neural target identity, temporal) is explicitly out of the v1 set.
3. Wrote `ml/camera_coach/contracts/camera_production_heads_v1.md` with a machine-readable JSON block, then `ml/camera_coach/contracts/check_production_heads_v1.py` (stdlib-only) validating issue coverage against the label schema, consumer symbols against the capability mapping JSON, field completeness, temporal separation, and the action set against DATA-002 dispositions.
4. Ran the check, plus five negative controls on /tmp copies of the contract (dropped issue head, fabricated consumer symbol, emptied mask, temporal promoted, unsupported action proposed): every mutation failed with the expected message and exit code 1. Temporary files were removed afterwards.

## Per-head decision (summary)

| Head | Target | Loss | Metric anchor | App consumer (mapping symbols) |
|---|---|---|---|---|
| `good_frame_probability` | calibrated P(frame needs no advice), verdict=good vs needs_fix/mixed | `masked_bce` | AUROC/ECE/Brier; Gate C2 `good_frame_preservation_rate >= 0.95`, `confidence_band_accuracy >= 0.90` | `CameraAdviceSafetyGate.evaluate`, `CameraOverlayUXPresentation.make`, `CoachingEpisodeCoordinator` |
| `issue_logits` (15 heads) | per-head presence for all 8 `IssueTypeV1` + 7 `TechnicalQualityIssueType` IDs | `masked_bce_with_logits` | per-head AUROC/ECE + good-frame FP rate (ML-006); Gate C2 `pass_rate`/`forbidden_action_violation_rate` | `IssueTypeV1`, `TechnicalQualityIssueType`, `CameraAnalysisV3ContractValidator`, `TechnicalQualityAnalyzer`, `CameraBoundedActionPlanner.plan` |
| `action_utility_logits` (26 heads) | utility for exactly the 26 DATA-002 `mapped` actions (21 semantic + 5 technical incl. `avoid_occlusion`); 4 unsupported semantic + `clean_lens`/`reduce_iso_noise` + `keep_current_setup` excluded | `masked_bce_with_logits` | masked top-1 per family; wrong-direction/magnitude separate; Gate C2 `expected_action_hit_rate >= 0.90` | `SemanticActionType`, planner, safety gate, `SETCameraCopy.actionKey(forCanonicalActionID`, `ActionVerifier.verify`, `ExposureFeatureSignals.applyProControl` |
| `continuous_target_deltas` | normalized magnitude on the 5 label axes, scoped to app-resolved ROI | `masked_huber` | MAE/RMSE/within-tolerance vs verifier deadband; wrong-direction success = 0 | planner, `ActionVerifier.verify`, `CameraOverlayUXPresentation.make` |
| `risk_probability` | P(unsafe/permission-violating proposal), independent of issues | `masked_bce` | AUROC/ECE/Brier; safety reported separately; zero critical safety-set violations | `CameraAdviceSafetyGate.evaluateAdmissibility`, `CoachingEpisodeCoordinator` |
| `abstention_probability` | P(should abstain); reason codes stay deterministic app-side in v1 | `masked_bce` | AUROC/ECE + selective-risk/risk-coverage (ML-007); honest abstention Gate C3 | `CameraAdviceSafetyGate.evaluate`, `CoachingEpisodeCoordinator`, overlay |
| `calibration_artifact` | per-head calibration + show/silent thresholds over the six tensor heads (CAM-003/ML-007 artifact) | not a gradient head (NLL/ECE objective) | ECE/reliability/selective risk; Gate C2 `confidence_band_accuracy >= 0.90` | safety gate (calibrated confidence), `CoachingEpisodeCoordinator` fail-closed state |

Temporal: separate entry, `status=deferred_to_ML_011` — existing target-scoped `ActionVerifier` is evaluated first (CAM-004/005/006 evidence); a temporal scorer is trained only for a proven gap; labels/splits are DATA-013/014. The still-image export (ML-012) does not wait for it.

Excluded from the v1 production set: `scene_class_logits`, `subjectness_roi_agreement_logits` (planned; no blocked capability references them), `embedding` (`not_a_release_target`), and any neural target-identity head (target selection is app-owned per DATA-002 capability `selection`, `app_only`).

## Check command and output

```text
python3 ml/camera_coach/contracts/check_production_heads_v1.py
```

```text
PASS ML-002 production-heads check
  contract: camera-production-heads-v1 v1.0.0
  heads: 7/7 minimal production entries with target/mask/loss/metric/consumer
  (a) issue coverage: 15/15 DATA-001 issue heads
  (b) consumer symbols verified in camera_release_capability_mapping_v1.json: 41
  (e) action head: 26 proposed = DATA-002 mapped; 7 explicitly excluded
  (d) temporal: deferred_to_ML_011 (separate entry, not a v1 head)
EXIT=0
```

Negative controls (each on a mutated /tmp copy, each exits 1 with the expected message): dropped `lens_smudge` from coverage; fabricated consumer `enum FabricatedGate`; emptied `abstention_probability.mask`; `temporal.status` changed away from `deferred_to_ML_011`; unsupported `clean_lens` added to `proposed_action_ids`. `python3 -m py_compile` passes. Temporary files removed.

## SHA-256

```text
4e7a87bb974d180e2ab13c1f330aa3dffd63725d3b38cddcfee0051947e2c66b  ml/camera_coach/contracts/camera_production_heads_v1.md
2ec1e4148497c4cb75e282717c1cc6f4d0cb8d0de8bf3fc94319f3de7289d081  ml/camera_coach/contracts/check_production_heads_v1.py
```

## Limitations

- This is a contract, not a model: nothing is trained, exported, calibrated, or admitted. `CameraConfidenceCalibrator` remains unavailable; all DATA-002 `blocked` capabilities stay blocked until ML-003…ML-018 and CAM-003/CAM-010…CAM-012 close.
- The check proves document/mapping/schema consistency only (coverage, consumers, field completeness, temporal separation, action dispositions). It cannot prove metric achievability; Gate C2 thresholds remain binding on the integrated runtime (ML-006/008), not on this document.
- Metric/threshold values quoted from `PRODUCTION_ACCEPTANCE.md` Gate C2 are references for consistency, not new or changed thresholds.
- Human-gold corpus is still 0 (DATA-004); the contract's masks assume adjudicated labels that do not exist yet (DATA-010…016). The current Stage-2 checkpoint stays research-only with the seven named gaps (GAP-1…GAP-7) recorded in the contract.
- The calibration head's loading path symbol `CameraConfidenceCalibrator` is deliberately not in the machine-readable consumer lists (it is not part of the DATA-002 consumer allowlist); it is named in prose only, routed to CAM-003.
