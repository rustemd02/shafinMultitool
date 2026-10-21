# DATA-002 receipt — release capability mapping

Date: 2026-09-22  
Candidate HEAD at authoring: `f8b6afd5de714c5c1c6e80c16c3c2a1bcdeb43ee`  
Scope: mapping/validator/tracker documentation only. No Swift, model weights, raw/local data, commit, reset, stash, branch, or worktree operation was performed.

## Delivered

- `ml/camera_coach/contracts/camera_release_capability_mapping_v1.json`
- `ml/camera_coach/contracts/camera_release_capability_mapping_v1.md`
- `ml/camera_coach/contracts/validate_camera_release_capability_mapping.py`
- `docs/implementation/APP_STORE_RELEASE_TRACKER.md` (`DATA-002` → `DONE`)

The validator now pins the five canonical input paths/IDs/versions and hashes
against those files instead of resolving inputs from mapping-provided paths. It
also pins a 12-source consumer-owner allowlist, validates structured
`consumer_support` records, canonical registry action subsets, source owners and
mapping relations, exact case projections/statuses, model head/output state, and
ActionVerifier honesty. Every supported consumer has a real owner symbol; the
behavior-only app validator records bind to
`CameraAnalysisV3ContractValidator`. UI action ownership is the existing
`SETCameraCopy.actionKey(forCanonicalActionID:)`; `rotate_entity` remains
deferred with no invented frozen action. `conditional` consumer status was
normalized to explicit `unsupported` with downstream blockers. A strict
33/33 `action_dispositions` ledger covers every DATA-001 action; unsupported
actions carry reasons and tracker dependencies rather than implied support.
`clear_lens_obstruction` maps only `occlusion`/`avoid_occlusion`; `lens_smudge`
and `clean_lens` remain separate unsupported paths.

## Verification

Command:

```text
python3 ml/camera_coach/contracts/validate_camera_release_capability_mapping.py
```

Result: `PASS DATA-002 mapping validator`; exact ordered source projection `68/68`; source operation/predicate/verifier fields preserved; 20 registry operations; 15 release issues; 33 release actions; capability statuses `8 blocked / 12 app_only / 6 deferred`; 12 consumer sources allowlisted; action dispositions `33/33`; negative self-checks `6/6`.

The validator also reports the source's existing count declaration (`16/33/9/10`) versus row-derived counts (`16/35/7/10`) and leaves that source file unchanged.

Command:

```text
python3 -m py_compile ml/camera_coach/contracts/validate_camera_release_capability_mapping.py
```

Result: pass.

The validator output also records the preserved stale source aggregate
`16/33/9/10` versus row-derived `16/35/7/10`; the canonical source was not
rewritten.

Command:

```text
git diff --check -- docs/implementation/APP_STORE_RELEASE_TRACKER.md
git diff --no-index --check /dev/null ml/camera_coach/contracts/camera_release_capability_mapping_v1.json
git diff --no-index --check /dev/null ml/camera_coach/contracts/camera_release_capability_mapping_v1.md
git diff --no-index --check /dev/null ml/camera_coach/contracts/validate_camera_release_capability_mapping.py
```

Result: no whitespace errors. The tracker retains its pre-existing hard-break spaces outside the edited row.

## SHA-256 (after verification and documentation update)

```text
a1a38cda009bf7347d4815ca55a379ffc90bd19540c0015a8ce07f9428a338df ml/camera_coach/contracts/camera_release_capability_mapping_v1.json
5dd24315c620cc198328bb1313c3c0f2157519b6ce8b5570fb417df564cfa8cb ml/camera_coach/contracts/camera_release_capability_mapping_v1.md
63dee774ad796c9273745a962450465fb2f8566d988987af44037897b633b0f7 ml/camera_coach/contracts/validate_camera_release_capability_mapping.py
75da1f430df0eb3cdc3c1bd09a9e07d302b8bb280f000d45d51558933c8f3e88 docs/implementation/APP_STORE_RELEASE_TRACKER.md
```

## Explicit blockers/dependencies

Blocked capabilities retain labels, trainer heads, declared Core ML keys, and app/planner/safety/UI consumers but cannot claim release support until ML-002/003 model admission and CAM-003/CAM-010 operation qualification/safety/UI gates are complete. ML-006/007/011/012/013 remain the issue/action/delta, good, risk, and abstention follow-ups. Technical app-only paths remain deterministic; `avoid_occlusion`, `clean_lens`, `reduce_iso_noise`, lens switching, and capture-moment selection remain unsupported/incomparable with explicit downstream blockers. `clear_lens_obstruction` contains only the canonical `occlusion` issue; `lens_smudge` is not conflated with obstruction. Temporal/output-crop/review capabilities are explicitly deferred with dependencies; declared v2 output names do not imply a production scorer.
