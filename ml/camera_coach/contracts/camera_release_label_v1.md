# Camera Coach release label contract v1

Status: **release-label contract; schema version `1.0.0`**.

The machine-readable owner is `camera_release_label_v1.schema.json`. The
positive fixture is `fixtures/camera_release_label_v1.valid.json`; the named
negative and boundary cases are in
`fixtures/camera_release_label_v1.invalid.json`.

## Boundary

This is the label/evidence boundary for release-capable Camera Coach records.
It is not a model-output schema and does not promote silver or research
records. Every root field is required, so omission cannot silently become a
negative label.

- `verdict` uses the app `FrameVerdict` raw values: `good`, `mixed`, and
  `needs_fix`. A null verdict is only the explicit abstention path.
- `issues[].status` is `present`, `absent`, or `not_observed`. `absent` is an
  explicit negative; `not_observed` is unknown/masked. The release label must
  contain every one of the eight frozen `IssueTypeV1` IDs and seven
  `TechnicalQualityIssueType` IDs exactly once. No parallel issue taxonomy is
  added.
- `action.action_id` is the exact union of the app's 26
  `SemanticActionType` IDs and seven `TechnicalQualityActionType` IDs. A
  corrective action may reference only issue heads whose status is `present`.
- `magnitude.status=not_observed` is different from a measured zero. An
  observed magnitude uses the frozen `delta_x`, `delta_y`, `scale_delta`,
  `light_delta`, or `horizon_delta` axes and the normalized `[-1, 1]` range.
- `risk.status=not_observed` carries `probability=null`; an observed zero is a
  measured low-risk value, not missing data.
- `abstention.status=abstain` requires `verdict=null`, `action=null`, and at
  least one existing V3/action-verifier reason. `status=none` requires a
  non-null app verdict and an empty reason list.
- Camera/object/lighting actions that act on a recipient require a resolved
  target with a non-empty region. Physical subject/object moves additionally
  require `movability.status=movable` and `permission=allowed`; uncertainty or
  denial fails closed.

## Identity, regions, and provenance

`source` binds a stable source family, frame, content SHA-256, and UTC capture
instant. `target.entity_ref` and intent subject references are opaque stable
IDs from the V3 entity graph (for example `lampA`), not a new `entity-*`
namespace. `target.kind` and `role` reuse V3's `person`, `object`, `group`,
`light` and `target`, `protected`, `context` values.

Regions contain only the four `CameraAnalysisV3Region` values (`x`, `y`,
`width`, `height`) in the record's existing frame-reference orientation and
transform context. The contract adds no parallel coordinate-space claim. JSON
Schema checks each scalar; the persistent validator also checks finite values
and unit-square containment (`x + width <= 1`, `y + height <= 1`).

`provenance.origin=model_proposal` is permanently non-gold and
non-release-admissible. Only `human_adjudication`, with at least two review
IDs and an adjudicator ID, can carry `human_gold=true` and
`release_admissible=true`. A model proposal may be retained as `proposal_id`,
but it cannot self-promote through a boolean edit.

`intent.selection`, `intent.styles`, and `intent_revision` reuse the exact
`CaptureIntentSelection` and `CaptureStyle` raw values. Empty styles remain
unknown; they are never silently promoted to `natural`.

## Before/after evidence

Comparable evidence requires same-target identity, matching
`target_ref`, distinct before/after frame IDs, `comparability=same_capture`,
and the measured verifier metric. An `improved` result must clear its
deadband. A `fixed` result additionally requires
`metric.goal_satisfied=true` and a non-empty `metric.objective_predicate`,
which records the objective predicate used by `ActionVerifier`/V3's
`goalSatisfied` evidence. `not_observed` is explicit; it is not an
`unchanged` result.

An incomparable result carries a reason. Identity/continuity-unproven reasons
(`frame_identity_missing`, `subject_identity_mismatch`, `scene_mismatch`,
`geometry_mismatch`, or `target_missing`) cannot claim `same_target=true`;
non-identity reasons such as `metric_unavailable` may preserve same-target
identity, but then must name the root target.

## Validation

Run the persistent, dependency-light validator from the repository root:

```bash
python3 ml/camera_coach/contracts/validate_camera_release_label.py
```

It validates the Draft 2020-12 schema and then enforces cross-field rules the
schema cannot express: exhaustive issue coverage and references, rectangle
containment, frame identity, fixed-goal evidence, target consistency, and
incomparable reason semantics. The command also runs every named negative
mutation and the accepted `metric_unavailable` boundary case.
