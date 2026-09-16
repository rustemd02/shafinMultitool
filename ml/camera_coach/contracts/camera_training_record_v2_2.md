# camera-training-record-v2 / v2.2.0

This explicit research intake extension leaves the v2 neural inputs and outputs
unchanged. v2.0 closed-catalog and v2.1 partial-language records retain their prior
meaning. The new producer is `tools/dataset/build_camera_edge_controls.py`; the
consumer remains `data/training_records.py`.

v2.2 uses the same eight nullable issue fields as v2.1, with a separately typed
`camera-edge-measurement-intake-v1` provenance. It admits only
`subject_too_close_to_edge` conditional on the supplied selected ROI. This is an
operational geometric proxy, not independent human assessment of a photograph.

The thresholds come from existing live `AnalysisPipeline` geometry:
`edgePressureScore = clamp(1 - minimum_edge_distance / 0.10)`. The strong label is
1 at gap <= 0.02 (pressure >= 0.80), 0 at gap >= 0.10 (pressure 0), and unknown in
between. A geometric no-op indicates sufficient edge margin for this one ROI;
it never labels the full frame as good or all advice as unnecessary.

The original ROI is Apple Vision silver, selected by the existing geometry
extractor. Confidence >= 0.8 is a fixed candidate filter, not calibrated
probability or human gold. The producer retains the entire source geometry row,
its source image hash, geometry-manifest hash, source rights and their hashes.
Only the crop and resulting ROI transform are analytically known. Images follow
the existing EXIF/ICC recipe, isotropic crop, a bounded max160 Lanczos thumbnail,
then the unchanged v2 runtime preprocessing.

The loader verifies retained geometry/rights/pixel hashes, original and derived
ROI binding, normalized top-left coordinates, aspect-preserving crop bounds,
measurement consistency, allowed recipe and research flags. It rejects known
intent, nonempty scalars or ranking, all other issue labels and any supervised
scene, subjectness, utility, good-frame, risk, abstention or delta targets. The
five absent deltas remain null and all corresponding neural masks are zero.
Changing configuration to `declared_admitted` is rejected.

`annotation_provenance` contains: schema_id, label_origin, source_record_id,
source_group_id, source_media_sha256, geometry_sha256, geometry,
rights_sha256, rights, geometry_manifest_sha256, rights_manifest_sha256,
crop_window_xyxy, coordinate_space, pixel_sha256, recipe, research_only,
human_gold, release_admissible and training_ready. The fixed provenance origin
is `silver_apple_vision_analytic_crop`; coordinate_space is
`oriented_full_frame_top_left_normalized`. JSON hashes use UTF-8, sorted keys,
no separators whitespace, ensure_ascii=false and no nonfinite values.

All outputs remain research_only=true, human_gold=false,
release_admissible=false and training_ready=false. Source license eligibility
does not promote the derived labels or a trained model. Source/crop/author groups
and conservative dHash near-duplicate components are assigned together before
training. Independent shoots are not established merely by author grouping;
validation is diagnostic. No locked-test content or labels are used. The
LASIESTA I_SI_01 sequence is reserved for the separate runtime diagnostics and
does not enter this Commons intake.

This data supports a finite learning/preprocessing/resume experiment against
majority and exact ROI geometry baselines. The exact formula already has all
required inputs and is preferable for this relation. A neural fit on these
controls alone cannot justify replacing that formula, admitting another output
component, or promoting a model into the production path.
