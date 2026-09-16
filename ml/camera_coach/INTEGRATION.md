# SETCompositionNet — Core ML integration

Current status (2026-09-16): **research export and host parity verified; no
SETCompositionNet candidate is admitted to the production coaching path.**
`SETCompositionNet-Stage2-Local.mlpackage` exists in the source tree, but the
app target explicitly excludes it in `shafinMultitool.xcodeproj/project.pbxproj`.
`SETCompositionNetScorer` can load that named bundle resource when available;
its missing-resource/invalid-input checks are not a model-quality admission gate.
A current search finds no production caller constructing the scorer. Historical
simulator bundle-load tests do not establish current Release inclusion.

## Contracts and ownership

| Boundary | Source | Meaning |
|---|---|---|
| Legacy Stage-2 model | `contracts/set_composition_net_v1.json`, `convert_coreml.py` | Six inputs / nine outputs. Historical direct supervision is declared for issue, action and delta heads only; this does not prove every component or scalar head was trained. |
| Intent-aware research candidates | `contracts/set_composition_net_v2.json`, `models/set_composition_net_v2.py`, `export_v2.py` | Frozen v2 model IO; intent is a separate input. Export supports seeded tooling weights and an explicit records checkpoint. |
| Training evidence | [component supervision v1](contracts/component_supervision_v1.md), `component_supervision.py` | Checkpoint v2 / receipt v3 carry canonical component names, counts and hashes of effective training supervision. Model IO and training-record versions are unchanged. |
| Input provenance | App `SETCompositionNetRuntimeSchema.swift`, `SETCompositionNetV2InputSchema.swift` | Frame/generation/orientation/ROI and tensor contract checks. These checks do not establish model accuracy or release permission. |
| Current release barrier | App target membership exception and absence of scorer wiring | Research packages remain outside the production path. Component export metadata is not yet a runtime admission consumer. |

`trained_head_mask` means that at least one component has observed direct
supervision. Use ordered component counts to assess coverage. An unknown issue is
not a negative label; an absent delta is not zero. Counts commit only after a
successful optimizer step using the effective augmented masks. Validation and
failed steps add no counts. Ranking supervision does not establish an absolute
good-frame target. Best and latest checkpoint states retain separate evidence.

Legacy checkpoints have unknown component evidence. They may be exported for
research or resumed with an unknown prefix; an old aggregate flag cannot establish
coverage for unrecorded components. Existing checkpoints and receipts are never
rewritten to claim stronger provenance.

## Export a real records checkpoint

Run from the repository root in the pinned macOS Python/torch/coremltools
environment. The checkpoint and matching training config are both required;
choose a new output outside the app and Git media trees. For example, with paths
set to the desired immutable run and a fresh research output:

```bash
python3 -B -m ml.camera_coach.export_v2 \
  --checkpoint "$SETOS_RESEARCH_CHECKPOINT" \
  --training-config "$SETOS_TRAINING_CONFIG" \
  --output "$SETOS_RESEARCH_EXPORT"
```

The exporter validates checkpoint version, config/resume semantics, seed, model
candidate, frozen manifest, selected epoch, state keys/shapes/dtypes, finite
tensors and selected-state component bindings. It exports the checkpoint's saved
best state when present and records both selected and current epochs. Seeded
tooling mode remains available without checkpoint/config and records untrained
weights explicitly.

To require actual direct supervision for a named component, add, for example,
`--require-component issue_logits:subject_too_close_to_edge`. Missing or unknown
coverage rejects the export before any output mutation or conversion. A legacy
checkpoint is therefore exportable for research but fails this requirement.
Passing this check is not release admission: packages and sidecars retain
`research_only=true`, `human_gold=false`, `release_admissible=false`, and no
quality/calibration claim. No export option promotes a model into the app.

The Python records loader exposes logical BHWC image/mask tensors; the model's
existing `_as_bchw` adapter converts image, crop and ROI mask into Core ML BCHW
transport. Do not send logical BHWC arrays directly to Core ML. The frozen shapes
are `[1,3,320,320]`, `[1,3,192,192]`, and `[1,1,320,320]` respectively. Preserve
pixel preprocessing, normalized ROI, scalar masks and intent ordering together.

Every export validates exact IO and nonempty, finite, shape-correct PyTorch ↔
Core ML outputs at fixed `atol=0.005`, `rtol=0.01`; a failure prevents publishing
the package. Package tree SHA, tensor-state SHA, checkpoint/config/contract SHA,
component evidence and parity are retained in adjacent provenance/parity JSON.
Host numerical parity proves transfer, not useful advice or device performance.

## Verified real checkpoint path

Local evidence root:
`../setos-backend/local-data/SETOS/verification/component-provenance-20260916-c8ih0apa/`.
The original four-epoch edge-controls experiment remains a negative quality
result: balanced accuracy 0.5, versus 1.0 for the analytic ROI-gap baseline.
It is used here only to verify real checkpoint export and preprocessing.

- `pytest-final.json` / `.log`: 64 focused checks passed, including partial
  components, zero masks, failed steps, resume/best-state evidence, legacy
  unknowns and both seeded tooling exports.
- `verification-receipt.json`: immutable input hashes, connected required-component
  rejection, actual export and canonical three-case parity; max absolute error
  `0.00026866793632507324`.
- `actual-record-parity.json`: four actual validation records, max absolute error
  `0.00028318166732788086`. Logical-loader and BCHW transport PyTorch outputs are
  bitwise equal; no private pixels or labels were uploaded.
- `lineage-final.json`: exported selected epoch 2 tensors match the original fit
  state hash `5abe229ef5c6c89007169d50b78aaed5a3adbde855fe9e24f7df840592ccf259`.
  The source checkpoint at epoch 4 remains SHA
  `1c0464a2d3d8390c82a77be85976edf913e2b29ddb7226db67c1848ee6e0e844`.
- `negative-fit-export-layout-verified/SETCompositionNet-v2-negative-fit-research.mlpackage`:
  tree SHA `702df0db7279219b0e3a8e93e6c4109b6ddcda5aa440d4b9dd153edbbba0aa78`.
  All legacy component coverage remains unknown. The first failed BHWC measurement
  driver and its log are preserved separately; only the external driver was fixed.

## Required before production use

Keep the research exclusion until source/data/weights rights, per-component
supervision, independent scenario evaluation, false-advice and temporal metrics,
calibration, preprocessing/coordinate parity and actual-device latency/energy
are admitted in the model registry. Human evaluation and physical-device tests
remain distinct gates. Runtime mapping must bind the accepted catalog and frame,
scene, ROI and intent provenance to the existing planner and verifier. The
current successful export does not satisfy those gates.
