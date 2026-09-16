# M3 — Camera silver geometry extractor

## Status

Implemented in the current working tree; no commit made by this worker. This
package is an offline research proposal stage only. It turns a previously
verified Camera research inventory into Apple Vision subject, saliency, and
horizon geometry for later synthetic-corruption work. It does not create
Camera Coach action labels, human gold, release admissibility, or a production
runtime claim.

## Owned artifacts

- `tools/dataset/extract_camera_geometry.swift`
  - Native macOS `swiftc` CLI using `VNDetectHumanRectanglesRequest`,
    `VNDetectFaceRectanglesRequest`,
    `VNGenerateAttentionBasedSaliencyImageRequest`, and
    `VNDetectHorizonRequest`.
  - Reads only an already verified JSONL inventory and media below the
    caller-selected external source root. No network, simulator, device, media
    copy, or third-party dependency is used.
  - Rejects unknown inventory fields, non-research rows, malformed or mutable
    files, hash/size/dimension/format mismatches, unsafe relative paths,
    symlinked paths (including lexical intermediate components before any
    resolution), and pre-existing output roots. It rechecks source and tool
    hashes before publishing. The receipt captures the macOS build, Vision
    framework identity, and each request's active revision.
  - Publishes sorted `geometry.jsonl` and `receipt.json` by atomically renaming
    one fully synced staged directory into a new output path. The receipt binds input inventory
    records/hash, output JSONL records/hash, tool source hash, OS/Vision
    request environment, and selection/saliency/horizon availability counts.
  - `--self-test` uses temporary valid image bytes and exercises inventory
    parsing, source hash mismatch, path escape, final/intermediate symlink
    rejection, pre-existing output protection, atomic publication, and
    geometry-to-receipt binding.

- `datasets/camera-coach/v1/silver-geometry-schema.json`
  - Draft 2020-12 schema for each JSONL geometry record.
  - Defines the immutable `research_only=true`, `human_gold=false`,
    `release_admissible=false`, `geometry_authority=silver_apple_vision`
    boundary and the optional saliency/horizon shapes.

## Record contract

Every row preserves the exact source `source_id`, `source_record_id`,
inventory-relative `relative_path`, and verified SHA-256. It records raw
decoded dimensions, EXIF orientation tag/name, oriented dimensions, and
whether the orientation came from `kCGImagePropertyOrientation` or the
default-up behavior when EXIF is absent.

ImageIO decodes the source bytes without rotating them. The exact EXIF tag is
passed once to `VNImageRequestHandler`; no physical rotation is applied by the
tool. Vision geometry is therefore normalized to the oriented image with
bottom-left origin, x-right, y-up, and `xywh` boxes. A later Pillow consumer
working from raw source pixels must first call `ImageOps.exif_transpose` exactly
once, then apply only `x' = x`, `y' = 1 - y - height`, `width' = width`, and
`height' = height` to move a box into top-left image space. It must not apply a
second EXIF transform.

The optional horizon object is explicitly an observed tilt, not an uprighting
correction. Apple documents that the `VNHorizonObservation.transform` inverse
uprights the image ([API reference](https://developer.apple.com/documentation/vision/vnhorizonobservation/transform)); this record makes that
operation explicit for Pillow. `observed_angle_degrees` is the raw `VNHorizonObservation.angle`
converted from radians. Positive means the horizon falls toward +x in the
oriented display (clockwise in x-right/y-down), equivalently a negative line
angle in the record's x-right/y-up coordinates. `pillow_uprighting_rotation_degrees`
is the same numeric value: after the one required
`ImageOps.exif_transpose`, pass it to `PIL.Image.rotate(angle=...)`; Pillow's
positive angles rotate counter-clockwise visually, which levels that observed
tilt. This is optional evidence, not a levelness truth claim.

The record retains every raw face/person candidate. The compact local
proposal-only selector merges one uniquely containing person/face pair, or
selects a candidate only when its confidence is at least `0.5` and either:

1. it is the sole merged/candidate proposal;
2. it is endorsed by exactly one saliency center with saliency confidence at
   least `0.5`; or
3. it wins by a confidence margin greater than `0.15`.

All other cases are `selection_status=ambiguous` with a null
`selected_subject`; no group or action label is invented. A frame with no
candidate is `selection_status=none`. The selector is deliberately not runtime
parity and is not a human annotation oracle.

The optional `upstream_metadata` inventory field is accepted because the
current AVA-derived inventory emits it; it is validated as scalar/array/object
metadata and policy-bearing keys are rejected. It is not copied into geometry
records or used for subject selection.

## Verification evidence

Commands run from the repository root:

```text
$ swiftc -warnings-as-errors tools/dataset/extract_camera_geometry.swift \
    -o /private/tmp/set-os-geometry
PASS (no compiler output)

$ /private/tmp/set-os-geometry --self-test
PASS extract_camera_geometry self-test inventory_schema hash_path_symlink_guards atomic_outputs receipt_binding research_only_boundary

$ python3 -m json.tool datasets/camera-coach/v1/silver-geometry-schema.json >/dev/null
PASS
```

A bounded local pilot used three existing Wikimedia Commons images in the
external corpus, with output under a temporary external directory and
`--max-records 3`:

```text
$ /private/tmp/set-os-geometry \
    --inventory "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/commons/v1-scale-1000/inventory.jsonl" \
    --source-root "/Users/unterlantas/Library/Application Support/SETOS/Datasets/camera-coach/research/commons/v1-scale-1000" \
    --output-root <temporary>/output --max-records 3
PASS extract_camera_geometry records=3 geometry_sha256=bc1748890f5a893802bc1328cca653191408cd43cc9436827d84ea905e401e0f
```

The pilot receipt recorded three complete Vision analyses, three saliency
regions, zero horizon observations, two `none` selections, and one selected
face. The temporary pilot output and compiled binary were removed after
inspection. No claim is made for Commons-scale coverage or detector quality.

Final scope checks for this slice:

```text
$ git diff --check -- tools/dataset/extract_camera_geometry.swift \
    datasets/camera-coach/v1/silver-geometry-schema.json \
    docs/aegis/work/2026-09-03-gpt-5-6-pro-guidance/evidence-m3/M3-silver-geometry-extractor.md
PASS (no output)
```

## Limits

Apple Vision results and byte identity are conditional on the captured macOS
and Vision runtime; the receipt records that environment rather than claiming
cross-OS determinism. Detection absence is valid missing evidence. The output
is a silver geometry proposal for research and synthetic corruption generation,
not a label-schema action target, `KEEP`, risk/abstention decision, locked
holdout, or release artifact. The parent task owns any larger Commons pilot and
must keep raw media outside Git.
