# M12-033 — machine-readable component disposition

Status: implemented in the isolated `codex/set-os-m12-033` worktree; legal
approval and replacement verification remain intentionally open.

## Contract

`docs/implementation/provenance/release-component-status.json` is the single
status input for the five provenance rows that used to be hard-coded in
`scripts/validate_release_bundle.sh`. The validator is
`scripts/validate_release_component_status.py` and is offline/read-only.

Every component record has:

- a stable ID and kind;
- exactly one of `KEEP`, `RETRAIN`, `REPLACE`, or
  `REMOVE_AFTER_VERIFIED_REPLACEMENT`;
- a non-empty `CAMERA_ONLY`/`SCENE_ONLY` scope set;
- owner, reason, expected source/bundle path, legal state, replacement
  dependency, and Debug/Release membership;
- strict unknown-field and missing-field rejection.

`PENDING` legal state is schema-valid, but blocks a Release component. A
replacement disposition also blocks until its dependency reports `VERIFIED`.
No record claims legal approval, source-to-export rights, or verified
replacement. The validator emits one stable row per blocking component and one
`KNOWN_BLOCKER_COUNT=<n>` line. A malformed record fails before it can be used
as release evidence.

The canonical current record reports five blockers:

| ID | component | scope | disposition | current blocker | owner |
|---|---|---|---|---|---|
| `circle-usdz` | `Circle.usdz` | `SCENE_ONLY` | `KEEP` | legal state pending | M12-038 |
| `detr-segmentation-model` | `DETRResnet50SemanticSegmentationF16P8.mlmodelc` | `CAMERA_ONLY` | `REMOVE_AFTER_VERIFIED_REPLACEMENT` | legal state pending | M12-034 |
| `llama-framework` | `Frameworks/llama.framework` | `SCENE_ONLY` | `REMOVE_AFTER_VERIFIED_REPLACEMENT` | legal state pending | M12-034 |
| `nima-aesthetic-model` | `aesthetic_nima_mobilenet_fp16.mlmodelc` | `CAMERA_ONLY` | `REMOVE_AFTER_VERIFIED_REPLACEMENT` | legal state pending | M12-034 |
| `person-usdz` | `Person.usdz` | `SCENE_ONLY` | `KEEP` | legal state pending | M12-038 |

The count is derived from the validator output, not from a shell constant.
`validate_release_bundle.sh` still owns all existing privacy, bundle structure,
payload, acknowledgement, manifest, size, and material-contributor checks.
`run_release_gates.sh` still runs the existing offline llama and Circle
technical validators before build and now preflights the new record/validator.

## M0-007 coverage reconciliation

The record is anchored to the SHA-256 of the M0 source inventory:

`docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m0/source-bundle-inventory.jsonl`
→ `93015bf41c1e4cd38a29e64a0483dc867d781de1337bf66b96c3b2c23e7910a5`.

Each current material family is represented once below, either by a blocking
component record or an explicit exclusion/deferred owner. The exclusions do
not assert legal approval; they prevent this five-blocker gate from silently
claiming ownership of later M12 work.

| M0 material family | M12-033 representation | release treatment |
|---|---|---|
| `Frameworks/llama.xcframework` | `llama-framework` | component record; current bundle path is blocking |
| DETR Core ML package | `detr-segmentation-model` | component record; current bundle path is blocking |
| NIMA Core ML package | `nima-aesthetic-model` | component record; current bundle path is blocking |
| `Resources/Circle.usdz` | `circle-usdz` | component record; rights pending |
| `Resources/Person.usdz` | `person-usdz` | component record; rights pending |
| `Resources/DeviceBenchmark` | `device-benchmark-resources` exclusion | Release excluded; Debug/evaluation only |
| `Resources/Fixtures` | `fixture-resources` exclusion | Release excluded; test-only |
| `Resources/Textures` | `camera-textures` exclusion | deferred to M12-037 asset review |
| `Resources/Fonts` | `bundled-fonts` exclusion | deferred to M12-036 font/provenance review |
| `Resources/Assets.xcassets` | `resource-assets-catalog` exclusion | deferred to M12-037 asset/branding review |
| `Multitool2Module/Assets.xcassets` | `module-assets-catalog` exclusion | deferred to M12-037 AppIcon/branding review |
| `Resources/Localizable.xcstrings` | `localized-resources` exclusion | deferred to M12-041 localization/release review |
| `Resources/InfoPlist.xcstrings` | `info-plist-localization` exclusion | deferred to M12-041 localization/release review |
| `PrivacyInfo.xcprivacy` | `privacy-manifest` exclusion | owned by M12-027 privacy gate |
| `Pods/SnapKit` | `snapkit-dependency-source` exclusion | deferred to M12-039 notice/license gate |
| M0-recorded GGUF under excluded `Resources/Models` | explicit M0 exclusion (absent from current checkout) | never Release; no path is invented here; M12-034 owns final model disposition |

The generated `Assets.car` and app executable are derived release outputs, not
new source component identities; their existing bundle/size validators remain
the source of truth for those checks. Future M12 provenance tasks may promote
an exclusion to a dedicated record, but this task does not pre-approve it.

## Verification

Commands run in the isolated worktree:

```text
python3 scripts/tests/test_validate_release_component_status.py
→ exit 0; 7 tests passed

python3 scripts/validate_release_component_status.py \
  --repo-root "$PWD" \
  --record docs/implementation/provenance/release-component-status.json
→ exit 1 (expected: five pending legal/replacement blockers)
→ 5 KNOWN_BLOCKER rows; exactly one KNOWN_BLOCKER_COUNT=5

bash -n scripts/validate_release_bundle.sh
bash -n scripts/run_release_gates.sh
bash -n scripts/tests/test_release_bundle_gate.sh
bash -n scripts/tests/test_release_provenance_gate.sh
→ exit 0 for each

scripts/tests/test_release_provenance_gate.sh
→ exit 0; all three offline orchestration fixtures passed

git diff --check
→ exit 0
```

The full copied-app bundle fixture was not claimed here because the available
historical Release app lacked the required root privacy manifest before the new
component validator was reached. It must be rerun by the integrating release
lane against a fresh Release app; no simulator/device/signing/archive claim is
made by M12-033.
