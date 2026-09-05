# Camera Coach capture protocol v1

Status: operational draft; `schema_version=v1.0.0`.

This protocol defines how future Camera Coach source shoots are recorded. It
does not claim that any source has been collected, licensed, consented, or
calibrated. Raw media and rights-uncleared material stay outside Git. Only
versioned metadata and hashes may be admitted to a release manifest.

## Unit of capture and stable families

The atomic capture unit is a deliberate source decision, not a file count.
Every entry receives stable IDs for:

- `source_shoot_id`: one controlled session with one source owner;
- `scene_family_id`: the same physical scene and layout;
- `take_family_id`: one continuous take or still decision window;
- `time_family_id`: a bounded lighting/people/time condition;
- `location_family_id` and `person_family_ids`: privacy-safe grouping keys;
- `device_family_id`, orientation, lens, and lighting condition;
- `derivation_family_id`: the source plus all crops, color variants, burst
  neighbours, sequence frames, and episode views derived from it.

The family IDs are split-protection keys. A family must occur in exactly one of
`train`, `calibration`, or `holdout`; this includes `device_family_id` as well
as source, scene, take, time, location, person, and derivation families.
Ambiguous or rights-incomplete entries go to `quarantine`. A release owner,
not the capture operator, assigns the split.

## Coverage matrix

Each pilot and later collection plan records observed coverage across all seven
matrix classes. The table is a coverage requirement, not a claim that the
requirement has already been met. Action IDs come only from the approved
`approvedActionIDs` catalog in `docs/implementation/camera-coach-contract-v2.json`;
legacy aliases are not admissible dataset labels.

| Matrix class | Include deliberate variation |
|---|---|
| `single_person` | talking head, portrait, actor, seated/standing, headroom, look-space, wardrobe and skin-tone variation |
| `two_people` | dialogue, balanced group, depth difference, partial occlusion, similar saliency, crossing, and no-random-face-selection negatives |
| `object_or_food` | selected ROI, plates/products/props, reflective surfaces, clutter, scale changes, and no-clear-subject cases |
| `interior` | rooms/workspaces, architecture, no-person scenes, distributed interest, verticals, window light, and deliberate asymmetry |
| `street_or_landscape` | horizons, architecture, moving people, wide scenes, foreground layers, intentional tilt, and no-single-subject cases |
| `difficult_light` | low-key, mixed temperature, clipping, backlight, window hotspot, practicals, flicker, and intentional silhouette |
| `already_good_frame` | centered/off-center compositions, film-like frames, balanced groups, negative space, low-key, and unconventional but strong framing |

Across the matrix, plan independent source shoots across multiple devices,
people, locations, portrait and landscape orientations, lenses, and lighting
conditions. Record what was actually captured in the manifest; never fill a
missing dimension with a synthetic or assumed value.

## Still capture

1. Set the scene and record all family/device/orientation/lens/light fields.
2. Let the operator settle the camera, then capture one intentional still
   decision for the take.
3. If a burst or rapid retry is used, keep every frame in the same
   `take_family_id` and `derivation_family_id`. Select at most one independent
   source decision. Mark adjacent frames, crops, resizes, and color variants as
   non-independent derivatives in the derivation manifest. The only closed
   derivation kinds are `original_still`, `original_temporal_sequence`,
   `original_before_after_episode`, `burst_frame`, `crop`, `resize`,
   `color_variant`, `temporal_frame`, and `episode_view`; original kinds are
   independent, while non-independent kinds never count toward quota. For a
   release split, an independent record must count toward quota; fixture and
   quarantine records never do. Record and derivation IDs are unique within a
   batch/manifest.
4. Record the asset IDs and SHA-256 hashes without copying raw media into Git.
5. Stop admission when source, rights, privacy, or family metadata is missing.

No still quota may be satisfied by burst-adjacent frames, synthetic images,
model outputs, or post-hoc crops of one decision.

## Temporal sequence capture

Capture one complete sequence per take. The record stores monotonic frame
timestamps, frame ordinals, asset IDs, and a state timeline such as
`acquire`, `stable`, `moving`, `rotation`, `lens_change`,
`lighting_transition`, or `scene_cut`.

The sequence remains one record and one split. Timeline segments must be
ordered, non-overlapping, contiguous from frame 0 through the final frame, and
cover every frame exactly once. Never split frames into separate partitions,
count each frame as an independent still, or use a later frame as a new source
shoot. Device family is also a protected split key even when scene,
take, time, location, and person families differ. Include sequences that
exercise subject acquisition,
tracking, motion, advice stability, device rotation, lens changes, lighting
transitions, and scene cuts when those conditions are available.

## Before/after episode capture

An episode contains exactly a before asset, one named action, and an after asset
from the same source context. The action must be one of the approved action IDs
in the authority catalog and `label-schema.json`. Record the action-specific
verifier and one explicit outcome. A `correct` episode additionally requires
`after.captured_at` to be later than `before.captured_at` and the matching label
verification to be `result=pass`, `measurement=before_after`. All episode
chronology is strict: `before.captured_at < action_step.performed_at <
after.captured_at`; failure or inconclusive evidence cannot be called correct:

- `correct`: the named action moves the intended condition in the expected
  direction;
- `no_op`: the action was performed but the relevant condition did not change;
- `opposite`: the condition moved in the wrong direction;
- `overshoot`: the action moved past the intended acceptable range;
- `track_loss`: the subject or reference was lost;
- `incomparable`: before and after cannot be compared safely.

The pilot must exercise correct, no-op, and opposite outcomes for each action
that it tests. Every measurable outcome (`correct`, `no_op`, `opposite`, or
`overshoot`) requires a matching action-specific verifier with `result=pass` and
`measurement=before_after` and `subject_continuity=same`; a changed, lost, or
unknown subject is not measurable proof. Use `track_loss` or `incomparable`
when continuity is not established. Overshoot, track loss, and incomparable outcomes are preserved as
failure/abstention evidence, never silently converted to `no_op`.

## Rights and provenance gate

Before a record can enter train, calibration, or holdout, the validator must
resolve:

1. `source_shoot_id` and every source asset ID in `source-shoots.jsonl`;
2. `consent_record_id` in `consent-manifest.jsonl`, with a matching source-shoot
   and asset scope, explicit admissible disposition, allowed use, evidence
   reference, and `recorded_at`;
3. `rights_record_id`, source-shoot match, asset scope, explicit disposition,
   allowed use, and its resolved consent record in `rights-manifest.jsonl`;
4. `derivation_family_id`, record link, source-shoot link, and independence in
   `derivation-manifest.jsonl`;
5. all family fields against the source-shoot entry.
6. resolved human review: a release record needs two distinct annotator votes
   that all accept, or an accepted latest adjudication covering every vote;
   conflicting, unreviewed, rejected, or missing-adjudication records stop at
   quarantine.

The resolved source-shoot entry is authoritative for `source_kind`; a record
claiming a different kind is invalid. A resolved `synthetic_fixture` source is
never eligible for train, calibration, or holdout, regardless of claimant
fields or a relabeled rights disposition. Only `approved` rights and `approved`
consent with the requested allowed use are eligible. Missing,
`denied`, `unresolved`, `pending`, `withdrawn`, or `fixture_only` rights are
not eligible for a release split. They remain quarantine/audit evidence only.
Fixture and quarantine records may retain unreviewed or partial review for
audit, but that status never satisfies a later train/calibration/holdout gate.

## Operational batch admission

Admission reads a caller-supplied record collection and four caller-supplied
JSON/JSONL manifests: source shoots, consent, rights, and derivation. It never
falls back to the embedded synthetic fixture manifests. A single `--record`
invocation likewise requires all four explicit manifest arguments;
`--fixture-mode` is an explicit test-only opt-in for the synthetic `fixture`
split.

Positive synthetic fixture-path smoke check (the flag is intentionally
explicit):

```text
python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-derivations.jsonl --fixture-mode
```

The checker must print `PASS ... camera-coach-batch` only when every record
resolves source/consent/rights/derivation references and no source, scene, take, time,
location, person, device, or derivation family crosses train, calibration, or
holdout. A protected-family crossing is a hard failure even if each record is
otherwise structurally valid. The negative fixture
`camera-coach-batch-negative-family.jsonl` exercises a train/calibration
crossing and is run with its caller-supplied negative derivation manifest.

```text
python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-negative-family.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-negative-derivations.jsonl --fixture-mode
```

The device-family isolation probe keeps every other protected family distinct
while sharing only `device_family_id`; it is admitted with the positive
caller-supplied manifests and must fail on that device family crossing (the
synthetic fixture source/rights gates also remain fail-closed):

```text
python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-negative-device.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-derivations.jsonl --fixture-mode
```

Duplicate guards run before any release use. A batch with a repeated
`record_id` fails with `duplicate_record_id`; a derivation manifest with more
than one entry for a record fails with `duplicate_derivation_record` rather
than silently selecting the last entry. Both fixtures are synthetic and use
the same four caller-supplied manifests:

```text
python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-negative-duplicates.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-derivations.jsonl --fixture-mode
python3 tools/dataset/camera_coach_check.py --batch-records tools/dataset/tests/fixtures/camera-coach-batch-positive.jsonl --source-shoots tools/dataset/tests/fixtures/camera-coach-batch-source-shoots.jsonl --consent-manifest tools/dataset/tests/fixtures/camera-coach-batch-consents.jsonl --rights-manifest tools/dataset/tests/fixtures/camera-coach-batch-rights.jsonl --derivation-manifest tools/dataset/tests/fixtures/camera-coach-batch-duplicate-derivations.jsonl --fixture-mode
```

## Auditable pilot manifest

Start from `capture-manifest-template.json`. For every entry, retain the
operator, UTC timestamp, family IDs, device/lens/light/orientation fields,
asset IDs, derivation classification, rights and consent record IDs, and an external
receipt/hash reference. A pilot audit is incomplete until each checklist item
in that template has a recorded pass/fail/blocked result and an evidence
location. Empty or unobserved fields are not passes.

Minimum pilot audit checklist:

- all seven matrix classes have a planned row and an observed status;
- stills contain one counted decision per take family;
- temporal sequences have monotonic timestamps and remain one split group;
- each exercised action has correct, no-op, and opposite episode rows;
- device, person, location, orientation, lens, and light variation is recorded;
- source, consent, rights, and derivation references resolve before annotation;
- unresolved privacy/rights/family issues are quarantined;
- no locked labels, candidate outputs, human votes, or model-quality claims are
  written into capture manifests.

The two-annotator, 35-case calibration and disagreement report belong to the
annotation workflow and remain pending HUMAN work; capture metadata cannot
close that requirement.
