# M3 — Camera silver action pairs

## Status

Implemented in the current working tree; no commit made by this worker. This
is the Stage-2 silver-supervision boundary only. The package derives
research-only pixel corruptions from a verified external inventory and the
Apple Vision geometry JSONL. It does not create human gold, release evidence,
physical before/after episodes, or production predictions.

## Owned artifacts

- `tools/dataset/generate_camera_corruptions.py`
  - Stdlib-first offline generator using the repository's pinned Pillow
    `12.2.0` runtime. It reads verified JSONL plus media below an external
    source root and atomically publishes sorted `pairs.jsonl`, `images/*.png`,
    and `receipt.json` below a new or empty external output root.
  - It fail-closes on unknown rows/schemas, hash or linkage mismatch, source
    mutation, invalid media, symlinks, path escape, repository-boundary roots,
    non-empty outputs, and stale matching staging directories. The receipt
    binds the raw inventory/geometry hashes, the required sibling Apple Vision
    geometry receipt (including its hash, environment, request revisions, and
    extractor source hash), geometry-schema hash, generator, contract and
    pair-schema hashes, frozen semantics, seed, counts, manifest hash, and
    media aggregate hash. Derivatives are written as generated; only small
    pair metadata is staged before sorted JSONL streaming.
- `datasets/camera-coach/v1/silver-action-pair-schema.json`
  - Draft 2020-12 schema for each paired-corruption row. Ordered issue/action/
    continuous catalogs are checked against the live
    `set_composition_net_v1.json` contract before generation.
- `docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m3/M3-silver-action-pairs.md`
  - This evidence and boundary note.

## Frozen derivation contract

Raw source pixels are EXIF-transposed exactly once with
`ImageOps.exif_transpose`, converted to RGB/sRGB exactly once when an ICC
profile is present, and rebuilt without metadata before any transform. Vision's
oriented bottom-left `xywh` box is converted once to the oriented top-left
model space with `x'=x`, `y'=1-y-height`. A derivative never runs a detector;
its ROI is transformed analytically.

The frozen target semantics digest is
`fcca9e96e79e4cc2631ab9041736c81653c59143a6a05017002ad906f40b48f5`.
Coordinates are normalized full-frame top-left (`+x` right, `+y` down),
subject displacement is source-center minus derivative-center, scale is
`log2(target source linear scale / derivative linear scale)`, and horizon
correction is required degrees divided by 180. Every five-element continuous
vector follows the live contract order and has a sparse mask. Issue/action
masks mark only the recipe-positive target and exact forbidden opposite/keep
actions; all other entries are unknown (`mask=0`), not false negatives.

The generator emits only `split=research_fit`, with
`is_independent=false`, `counts_toward_quota=false`,
`research_only=true`, `human_gold=false`, and `release_admissible=false`.
Source, derivative, and derivation-family identifiers bind every derivative to
the same source family.

The geometry input is accepted only with the extractor's sibling `receipt.json`.
Its `input_inventory` and `output_geometry` hashes/counts, research boundary,
Apple Vision environment/request revisions, and extractor source digest are
verified before generation and rechecked before publication. The output
receipt carries that sibling receipt hash and environment binding.

## Safe recipes

1. `rotate_horizon`: requires silver horizon confidence at least `0.65` and
   baseline absolute angle at most `2°`; applies deterministic signed
   `6–12°` observed tilt with a border-free inscribed overscan crop. Pillow is
   called with the inverse signed rotation specified by the geometry contract,
   so the target derivative tilt is explicit. The target is
   `horizon_distracts → level_horizon`, `keep_current_setup` forbidden, and
   `horizon_delta=-theta/180`. The configured derivative tilt is checked to be
   at least `6°` in magnitude.
2. `crop_translate`: requires a selected face/person proposal with confidence
   at least `0.70` and a chosen source edge gap at least `0.12`; uses a single
   analytically specified equal-normalized-span crop (there is no anisotropic
   stretch) so the selected edge gap is at most `0.03` while the subject
   remains visible. Infeasible square crops are counted as skips. Directional
   frame-shift actions and their exact opposite/keep forbiddances follow the
   oriented top-left axes; the signed `delta_x` or `delta_y` is the desired
   subject displacement.
3. `crop_zoom_in`: requires a selected face/person proposal with confidence
   at least `0.70`, sensible initial area, and full visibility; applies a
   deterministic `1.15–1.50×` square crop/reframe, retaining a final edge gap
   above `0.03` and entering the configured `(0.03, 0.12]` edge-pressure band.
   If the transformed ROI cannot reach that band, the recipe is counted as a
   skip and no edge-pressure issue is emitted. The target is
   `subject_too_close_to_edge → step_back`, `step_closer` and
   `keep_current_setup` forbidden, with negative `scale_delta`.

The current silver geometry schema represents only `face` and `person`
proposals. Therefore no object-edge claim is fabricated and the optional
object projection marker is not emitted for this schema revision. No
calibration or holdout input is accepted.

## Verification evidence

Commands run from the repository root:

```text
$ python3 -m py_compile tools/dataset/generate_camera_corruptions.py
PASS

$ python3 tools/dataset/generate_camera_corruptions.py --self-test
PASS generate_camera_corruptions self-test recipes square_stream_zoom_receipt_lf hash_path_mask_determinism atomic_research_only

$ python3 - <<'PY'
import json
from pathlib import Path
for name in (
    'datasets/camera-coach/v1/silver-geometry-schema.json',
    'datasets/camera-coach/v1/silver-action-pair-schema.json',
    'ml/camera_coach/contracts/set_composition_net_v1.json',
):
    json.loads(Path(name).read_text(encoding='utf-8'))
    print('JSON PASS', name)
PY
JSON PASS datasets/camera-coach/v1/silver-geometry-schema.json
JSON PASS datasets/camera-coach/v1/silver-action-pair-schema.json
JSON PASS ml/camera_coach/contracts/set_composition_net_v1.json

$ python3 - <<'PY'
import importlib.util, json, tempfile
from pathlib import Path
from PIL import Image
from jsonschema import Draft202012Validator
spec = importlib.util.spec_from_file_location('gen', 'tools/dataset/generate_camera_corruptions.py')
gen = importlib.util.module_from_spec(spec); spec.loader.exec_module(gen)
with tempfile.TemporaryDirectory(prefix='camera-corruption-schema-', dir='/private/tmp') as td:
    base = Path(td); root = base / 'source'; (root / 'images').mkdir(parents=True)
    inventory = []; geometry = []
    for record_id in ('a', 'b', 'c'):
        image = Image.new('RGB', (320, 240), (40, 90, 120))
        relative = f'images/{record_id}.png'; image.save(root / relative, format='PNG', optimize=False, compress_level=9)
        row = gen._fixture_inventory_row('fixture', record_id, relative, image, root)
        inventory.append(row); geometry.append(gen._fixture_geometry(row))
    inventory_path = base / 'inventory.jsonl'; geometry_path = base / 'geometry.jsonl'
    inventory_bytes = b''.join(gen._json_bytes(row) for row in inventory)
    geometry_bytes = b''.join(gen._json_bytes(row) for row in geometry)
    inventory_path.write_bytes(inventory_bytes)
    geometry_path.write_bytes(geometry_bytes)
    (base / 'receipt.json').write_bytes(gen._json_bytes(
        gen._fixture_geometry_receipt(inventory_bytes, geometry_bytes, len(inventory))))
    output = base / 'output'; gen._run(inventory_path, geometry_path, root, output, 20260909, None)
    geometry_schema = json.loads(Path('datasets/camera-coach/v1/silver-geometry-schema.json').read_text())
    pair_schema = json.loads(Path('datasets/camera-coach/v1/silver-action-pair-schema.json').read_text())
    assert all(not list(Draft202012Validator(geometry_schema).iter_errors(row)) for row in geometry)
    pairs = [json.loads(line) for line in (output / 'pairs.jsonl').read_text().splitlines()]
    assert all(not list(Draft202012Validator(pair_schema).iter_errors(row)) for row in pairs)
    print(f'SCHEMA PASS geometry={len(geometry)} pairs={len(pairs)}')
PY
SCHEMA PASS geometry=3 pairs=9

$ git diff --check -- tools/dataset/generate_camera_corruptions.py \
    datasets/camera-coach/v1/silver-action-pair-schema.json \
    docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m3/M3-silver-action-pairs.md
PASS (no output)
```

An additional temporary JPEG check with EXIF orientation tag `6` passed with
raw source dimensions `80×40` and oriented derivative dimensions `40×80`,
confirming the one-time Pillow orientation path (`EXIF ORIENTATION PASS
pairs=3`).

The bounded self-test also validates EXIF tag `6` on a `100×100` source.
Rotated tags 5–8 are compared with the expected `(height, width)` tuple rather
than requiring the two numeric dimensions to differ, so square frames remain
valid.

The self-test creates three temporary PNG sources, matching silver rows, and a
fully bound sibling geometry receipt; covers all three recipes and their
directional/action masks; verifies equal-span translation, streamed staging
cleanup, zoom pressure-band gating, receipt tamper rejection, U+2028-safe LF
parsing, source hash and path-escape negatives; runs two identical seeded
outputs; and asserts byte-identical trees and receipts. Temporary files are
removed by the task-owned temporary directory; no real corpus pilot is claimed
here.

## Published research-fit corpora

The audited generator was run with seed `20260909` against the full verified
Commons, EVA, and AADB geometry sets. All output roots are external to Git under
`~/Library/Application Support/SETOS/Datasets/camera-coach/research/paired-corruptions/v1/`.

| Source | Sources | Pairs | Translate | Zoom | Horizon | Manifest SHA-256 | Receipt SHA-256 |
|---|---:|---:|---:|---:|---:|---|---|
| Commons `v1-scale-1000` | 767 | 233 | 114 | 79 | 40 | `091697d616d168c46afb8ae41b0a3fe503b8304d7fed7e1f4c6341b5e8f2e56f` | `bab422ec74c47852866ffa37c60ae27121ede045a239683e2969a61d9e2c874a` |
| EVA `fb40a9f1` | 5,101 | 1,099 | 492 | 376 | 231 | `ea9e5609f671004a385d74bbfdee255a7f81803f3f029b22edf8c3b06979687f` | `ec40169d8d58a96c80652365c04e8eeae88ad5fa07e479c445cab47e92d34680` |
| AADB `warp256-v1` | 9,433 | 4,265 | 1,892 | 1,359 | 1,014 | `19ed1644f21f2217e4e3e2f21fd37486f842a9456a5326db1e1e07ac66d1432e` | `85ae7d6849895a721d1aceba9df0dd3db0046cc302d4edc6e0470919d7c312ce` |

All `5,597` rows passed Draft 2020-12 validation and every derivative media
hash was recomputed successfully. A real Commons CMYK image with an embedded
ICC profile was converted through `ImageCms.profileToProfile` to metadata-free
sRGB and produced two valid pairs. Pillow-exposed invalid EXIF values outside
`1...8` are normalized only to the no-op tag `1`, matching ImageIO; all valid
tags still must equal the Vision receipt. The post-run Sol audit verified 135
such real no-op cases and rejection of an injected valid-tag mismatch.

Two EVA files emitted non-fatal Pillow `Truncated File Read` metadata warnings
and produced no pairs. They remain hash-bound research sources; a future
release-candidate intake must turn this warning class into a counted skip.

## Limits and review readiness

Apple Vision geometry is silver and conditional on the captured macOS/Vision
runtime recorded by the geometry extractor. Geometry absence or unsupported
proposal quality causes a counted skip; it is not converted into a label.
Continuous values and target masks are supervision for research experiments,
not Camera Coach frozen label/episode records. The output media remains
outside Git and must not be promoted to release or human-gold data without a
separate review gate.

Fresh Sol audits returned `SHIP` for the package and for both published
research-fit corpora. This does not close the human-gold or release gate.
