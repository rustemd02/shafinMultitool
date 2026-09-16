# camera-training-record-v2 / v2.1.0

This is a training intake extension, not a new neural IO contract or a trained
model. `set_composition_net_v2.json` remains unchanged. The executable boundary
is `data/training_records.py`; the producer is
`tools/camera_annotation/review_pipeline.py export-language`.

## Explicit compatibility

| Version | Issue representation | Provenance | Scope |
|---|---|---|---|
| v2.0.0 | `{"reviewed": bool, "present": [issue IDs]}` | Existing fields unchanged | Reviewed whole catalog; reviewed=false masks all issues |
| v2.1.0 | Object containing exactly the eight frozen issue IDs, each `0`, `1` or `null` | Required `annotation_provenance` | Partial research issue supervision only |

The loader accepts both exact versions. Mixing their issue shapes or adding
v2.1 fields to a v2.0 record is rejected. Existing v2.0 exports, model manifests,
configuration versions and checkpoint receipts are not rewritten.

For v2.1, `1` is an explicitly stated present issue, `0` an explicitly stated
absent issue, and `null` an unknown issue. The first two yield mask 1; null yields
mask 0. Its internal tensor fill value is zero but receives no loss or gradient.
The eight names and their order come from the frozen neural manifest.

## Research provenance and targets

`annotation_provenance` has exactly these fields:

- `schema_id`: `camera-language-partial-intake-v1`.
- `label_origin`: `human_text_model_translation_confirmed` or
  `model_visual_human_confirmed`. These distinguish a translated human opinion
  from an accepted model assessment. Neither denotes independent human gold.
- `journal_sha256`, `queue_sha256`: SHA256 of the complete source byte snapshots.
- `event_line`: one-based physical journal line; `event_sha256`: SHA256 of the
  event serialized as UTF-8 JSON with sorted keys, no spaces, `ensure_ascii=false`.
- `media_sha256`: the reviewed original file bytes, checked before decoding.
- `projection`: the source event's entire projection, unchanged.
- `research_only=true`, `human_gold=false`, `release_admissible=false`,
  `training_ready=false`: required exact booleans, also verified in the projection.

The nullable issue array in the retained projection must match the emitted issue
object. v2.1 cannot carry supervised scene, subjectness, utility, good-frame,
abstention, risk or delta targets. ROI/scalars/ranking remain absent, and neural
intent remains unknown. Original intent/action/verdict/spatial/temporal opinions
remain available in the projection for a future separately admitted adapter.
In particular a spatial request for center is never interpreted as a measured
delta, a physical movement, a subject ROI or proof of improvement.

`matrix_class` retains the queue's sampling stratum; it is not a scene-class
label. The export's lineage file retains that basis, original queue row,
confirmation and model proposal. Source records and journals are never modified.
EXIF orientation, RGB conversion and the bounded 320-pixel thumbnail recipe are
recorded per derivative before existing runtime preprocessing is applied.

The loader and trainer reject configuration-based promotion to
`declared_admitted`. Full training admission still requires new evidence and an
explicit compatible contract; changing a config flag does not provide it.

## Selection and split limits

Only existing confirmed events with matching proposal lineage are selected.
Newer manual drafts or raw opinions withdraw old supervision. A slow visual
proposal does not supersede a manual revision made after its dispatch. Multiple
reviewers require adjudication; videos require separate episode admission.
Locked test is refused before media loading.

Existing source-group splits are preserved. The exporter checks group and media
SHA conflicts across the photo queue, plus exact decoded-pixel and dHash
candidates within reviewed photos. dHash is a duplicate candidate screen; it
does not prove scene independence. Author grouping is conservative and does not
establish shoot/scene IDs. Model-assisted validation remains diagnostic research
data, not independent human-gold or release evaluation.

`data/check_partial_labels.py` is a bounded forward/backward integrity check on
the materialized train split. It checks real input tensors and exact loss masks,
performs no optimizer update, does not train on validation, and makes no accuracy
claim. Empty supervision fails. The normal trainer excludes fully masked rows
from optimizer steps and validation loss and rejects empty effective splits.
