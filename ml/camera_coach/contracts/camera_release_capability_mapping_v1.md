# DATA-002 release capability mapping

The machine-readable owner is [`camera_release_capability_mapping_v1.json`](camera_release_capability_mapping_v1.json). Run the bounded check with:

```bash
python3 ml/camera_coach/contracts/validate_camera_release_capability_mapping.py
```

It proves the pinned canonical source is mapped exactly 68/68 (ordered IDs, no duplicates or extras), preserves the source operation/predicate/verifier projection, and checks the DATA-001 issue/action catalog, app enums, v2 head order/shapes, Core ML key state, explicit capability gates, and the allowlisted consumer owners/symbols. The validator also runs six in-memory negative controls (canonical-path substitution, fabricated action relation, fake/deleted consumer symbol, wrong case status, wrong capability count).

## Status semantics

| Status | Meaning |
| --- | --- |
| `blocked` | Label, trainer/Core ML references, planner/safety/UI consumers, blocker, and tracker dependencies are present; qualification or model admission still blocks release. |
| `app_only` | DATA-001 labels and deterministic app/UI owner are present; the gate explains why no neural head/output is claimed. |
| `deferred` | Not a release capability yet; missing links are named with a tracker dependency and no support is claimed. |

There are 8 blocked, 12 app-only, and 6 deferred capabilities. All 20 draft registry operations are represented. The 68 source rows derive to 16 `implemented_regression`, 35 `partial`, 7 `not_implemented`, and 10 `implemented_local`. The source file declares 16/33/9/10; that stale declaration is preserved and reported by the validator rather than silently rewritten.

The current v2 contract is not a production model: only `issue_logits`, `action_utility_logits`, and `continuous_target_deltas` are marked `research_only_current`; five heads are `planned`, and `embedding` is not a release target. Core ML names/shapes are copied from the contract but `production_admitted` is false. No draft operation is treated as runtime/model support.

Technical quality actions/issues and state, selection, feedback, and temporal paths remain deterministic app-owned or explicitly deferred. `action_dispositions` covers all 33 DATA-001 actions: mapped actions reference capabilities that actually contain them, while `rotate_subject_toward_light`, `reposition_prop_for_balance`, `remove_background_hotspot`, `simplify_background`, `clean_lens`, and `reduce_iso_noise` remain explicit unsupported/app-only entries with reasons and tracker dependencies; `keep_current_setup` is an app-only policy output. `ActionVerifier` support is claimed only for its handled action set; `avoid_occlusion`, `change_lens`, and capture-moment selection remain explicit unsupported/incomparable paths with downstream blockers. `clear_lens_obstruction` is restricted to the canonical `occlusion`/`avoid_occlusion` pair; `lens_smudge` is not conflated with it. UI action copy is owned by `SETCameraCopy.actionKey(forCanonicalActionID:)`. The mapped consumers are the existing `CameraAnalysis*` validators, `CameraBoundedActionPlanner`, `CameraAdviceSafetyGate`, `CameraOverlayUXPresentation`/production view, and `ActionVerifier`/`CoachingEpisodeCoordinator`.

Primary follow-up dependencies are ML-002/003 (model architecture/training and admission), ML-006/007/011/012/013 (issue/action/delta, good, abstention, and risk heads), and CAM-003/CAM-010 (operation qualification, deterministic safety, and UI/runtime admission). This artifact changes no Swift, model weights, or local/raw data.
