# M12-033 — machine-readable component disposition

Status: implemented in the isolated `codex/set-os-m12-033` worktree; legal
approval and replacement verification remain intentionally open.

## Contract

`docs/implementation/provenance/release-component-status.json` is the single
status input for every material model, framework, media, font, asset, and
dependency family derived from M0-007. It replaces the five provenance rows
that used to be hard-coded in `scripts/validate_release_bundle.sh`. The validator is
`scripts/validate_release_component_status.py` and is offline/read-only.

Every component record has:

- a stable ID and kind;
- exactly one of `KEEP`, `RETRAIN`, `REPLACE`, or
  `REMOVE_AFTER_VERIFIED_REPLACEMENT`;
- a non-empty `CAMERA_ONLY`/`SCENE_ONLY` scope set;
- owner, reason, expected source/bundle path, legal state, replacement
  dependency, source presence state, and Debug/Release membership;
- strict unknown-field and missing-field rejection.

`PENDING` legal state is schema-valid, but blocks a Release component. A
replacement disposition also blocks until its dependency reports `VERIFIED`.
No record claims legal approval, source-to-export rights, or verified
replacement. The validator emits one stable row per blocking component and one
`KNOWN_BLOCKER_COUNT=<n>` line. A malformed record fails before it can be used
as release evidence.

The canonical current record contains 19 material component records and reports
16 Release blockers:

| ID | component | scope | disposition | current blocker | owner |
|---|---|---|---|---|---|
| `circle-usdz` | `Circle.usdz` | `SCENE_ONLY` | `KEEP` | legal state pending | M12-038 |
| `detr-segmentation-model` | `DETRResnet50SemanticSegmentationF16P8.mlmodelc` | `CAMERA_ONLY` | `REMOVE_AFTER_VERIFIED_REPLACEMENT` | legal state pending | M12-034 |
| `font-bebasneue-regular` | `BebasNeue-Regular.ttf` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-036 |
| `font-caveat-variable` | `Caveat-Variable.ttf` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-036 |
| `font-jetbrainsmono-variable` | `JetBrainsMono-Variable.ttf` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-036 |
| `font-oswald-variable` | `Oswald-Variable.ttf` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-036 |
| `font-ptm55ft` | `PTM55FT.ttf` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-036 |
| `info-plist-localization` | `InfoPlist.xcstrings` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-041 |
| `llama-framework` | `Frameworks/llama.framework` | `SCENE_ONLY` | `REMOVE_AFTER_VERIFIED_REPLACEMENT` | legal state pending | M12-034 |
| `nima-aesthetic-model` | `aesthetic_nima_mobilenet_fp16.mlmodelc` | `CAMERA_ONLY` | `REMOVE_AFTER_VERIFIED_REPLACEMENT` | legal state pending | M12-034 |
| `person-usdz` | `Person.usdz` | `SCENE_ONLY` | `KEEP` | legal state pending | M12-038 |
| `localized-resources` | `Localizable.xcstrings` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-041 |
| `module-assets-catalog` | `Multitool2Module/Assets.xcassets` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-037 |
| `privacy-manifest` | `PrivacyInfo.xcprivacy` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-027 |
| `resource-assets-catalog` | `Resources/Assets.xcassets` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-037 |
| `snapkit-dependency` | `Pods/SnapKit` | `CAMERA_ONLY,SCENE_ONLY` | `KEEP` | legal state pending | M12-039 |

The 16-row count is derived from the validator output, not from a shell
constant. The three excluded material records are explicit and absent from
Release. No current record uses `deferred`; if a future record does, the
validator treats that unresolved membership as a Release blocker.
`validate_release_bundle.sh` still owns all existing privacy, bundle structure,
payload, acknowledgement, manifest, size, and material-contributor checks.
`run_release_gates.sh` still runs the existing offline llama and Circle
technical validators before build and now preflights the new record/validator.

## M0-007 coverage reconciliation

The record is anchored to the SHA-256 of the M0 source inventory:

`docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m0/source-bundle-inventory.jsonl`
→ `93015bf41c1e4cd38a29e64a0483dc867d781de1337bf66b96c3b2c23e7910a5`.

Each current model/framework/media/font/asset/dependency family is represented
once by a full component record. The two explicit exclusions below are only
benchmark and fixture resources, which are not public material components.
`Release=deferred` is a typed unresolved membership state that blocks Release;
it is not a legal approval claim.

| M0 material family | M12-033 representation | release treatment |
|---|---|---|
| `Frameworks/llama.xcframework` | `llama-framework` | full record; current bundle path is blocking |
| DETR Core ML package | `detr-segmentation-model` | full record; current bundle path is blocking |
| NIMA Core ML package | `nima-aesthetic-model` | full record; current bundle path is blocking |
| M0 GGUF (`Resources/Models/dataset_v9_event_sft_q4_k_m.gguf`) | `scene-gguf-model` | full record; source absent and Debug/Release excluded |
| `Resources/Circle.usdz` | `circle-usdz` | full record; rights pending |
| `Resources/Person.usdz` | `person-usdz` | full record; rights pending |
| `Resources/Circle.rcproject` | `circle-rcproject` | full record; source project excluded from app bundle |
| five bundled `.ttf` font files | `font-*` records (5) | full records; Release bundled, pending M12-036 |
| `Resources/Assets.xcassets` | `resource-assets-catalog` | full record; Release bundled, pending M12-037 |
| `Multitool2Module/Assets.xcassets` | `module-assets-catalog` | full record; Release bundled, pending M12-037 |
| `Resources/Textures/SETGrain.png` | `set-grain-texture` | full record; excluded from app target per M0 |
| `Resources/Localizable.xcstrings` | `localized-resources` | full record; Release bundled, pending M12-041 |
| `Resources/InfoPlist.xcstrings` | `info-plist-localization` | full record; Release bundled, pending M12-041 |
| `PrivacyInfo.xcprivacy` | `privacy-manifest` | full record; Release bundled, pending M12-027 |
| `Pods/SnapKit` | `snapkit-dependency` | full record; linked/bundled, pending M12-039 |
| `Resources/DeviceBenchmark` | `device-benchmark-resources` exclusion | Release excluded; Debug/evaluation only |
| `Resources/Fixtures` | `fixture-resources` exclusion | Release excluded; test-only |

The generated `Assets.car` and app executable are derived release outputs, not
new source component identities; their existing bundle/size validators remain
the source of truth for those checks. Future M12 provenance tasks may promote
an exclusion to a dedicated record, but this task does not pre-approve it.

## Verification

Commands run in the isolated worktree:

```text
python3 scripts/tests/test_validate_release_component_status.py
→ exit 0; 17 tests passed

python3 scripts/validate_release_component_status.py \
  --repo-root "$PWD" \
  --record docs/implementation/provenance/release-component-status.json
→ exit 1 (expected: 16 pending legal/replacement blockers)
→ 16 KNOWN_BLOCKER rows; exactly one KNOWN_BLOCKER_COUNT=16

bash -n scripts/validate_release_bundle.sh
bash -n scripts/run_release_gates.sh
bash -n scripts/tests/test_release_bundle_gate.sh
bash -n scripts/tests/test_release_provenance_gate.sh
→ exit 0 for each

scripts/tests/test_release_provenance_gate.sh
→ exit 0; all five offline orchestration fixtures passed

git diff --check
→ exit 0
```

The full copied-app bundle fixture was not claimed here because the available
historical Release app lacked the required root privacy manifest before the new
component validator was reached. It must be rerun by the integrating release
lane against a fresh Release app; no simulator/device/signing/archive claim is
made by M12-033.
