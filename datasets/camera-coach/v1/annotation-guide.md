# Camera Coach annotation guide v1

Status: operational draft; `schema_version=v1.0.0`.

This guide describes human labels for the three record types in this
directory. It is a rubric, not a taste poll. Annotators write only the
approved IDs from `docs/implementation/camera-coach-contract-v2.json` as
mirrored by `label-schema.json`; legacy aliases, free-form advice, model
output, locked labels, and candidate identity are not part of this contract.

## 0. Eligibility before looking at the label

Confirm that the record is readable, its source shoot and source assets resolve,
its rights disposition is explicit, and its family IDs are present. If any
check fails, do not force a label: preserve the record as quarantine evidence
or use `ABSTAIN` with `rights_or_privacy_blocker` where appropriate.

## 1. Subject

The subject is the person, group, object, or scene the camera decision is meant
to serve. Choose the smallest stable reference that can be checked again:

- `selected`: exactly one candidate and `selected_subject_id` points to it;
- `ambiguous`: two or more plausible candidates, no forced winner;
- `none`: no meaningful subject (for example, an interior or landscape test);
- `abstain`: subject cannot be referenced safely.

For `ambiguous`, `none`, or `abstain`, leave `selected_subject_id` null. For
`selected`, the ID must resolve to exactly one candidate; never use a guessed
or unresolved reference as a selected subject.

Candidate `kind` is `face`, `person`, `object`, `group`, `scene`, or `unknown`.
The reference is an asset-local stable ID, not a guessed name. Do not select a
random face in a two-person frame. If the intended subject is unclear, use
`ambiguous` or `abstain`, and record the reason.

## 2. Intentional style

`style_intent.style_id` is the visible or briefed visual intent:
`naturalistic`, `cinematic`, `documentary`, `commercial`, `stylized`,
`already_good`, or `unknown`. Set `intentional=true` only when the framing,
light, or treatment appears deliberate or is documented by the capture brief.
Use `basis=capture_brief` or `annotator_observed`; use `not_available` when no
intent can be established. Style is context, not a quality score: an
intentional silhouette can still have a readability issue, and an
`already_good` frame still needs a safe KEEP decision.

## 3. Issues

Add an issue only when there is visible or temporal evidence. Use the narrowest
closed ID:

| Issue | Operational question |
|---|---|
| `insufficient_look_space` | Does the subject face/attention run into the frame edge? |
| `subject_edge_pressure` | Is a person pushed uncomfortably against an edge? |
| `object_edge_pressure` | Is the selected object clipped or edge-bound? |
| `tight_framing` | Is useful breathing room or context missing? |
| `weak_subject_prominence` | Is the intended person too small or visually subordinate? |
| `weak_object_prominence` | Is the intended object too small to read? |
| `camera_height_mismatch` | Does camera height undermine the intended relationship? |
| `perspective_mismatch` | Does the viewpoint distort or weaken the intended read? |
| `background_competition` | Does another region compete with the intended subject? |
| `tilted_horizon` | Is an unintended horizon/vertical tilt visible? |
| `weak_subject_background_separation` | Does subject and background merge? |
| `flat_depth` | Are intended depth layers unreadable? |
| `front_light_deficit` | Is the subject unreadable because useful front light is missing? |
| `prop_breaks_balance` | Does a prop disrupt the composition without being the subject? |
| `object_conflicts_with_subject` | Does an object compete or merge with the subject? |
| `face_contour_occlusion` | Does an object cross the selected face contour? |
| `subject_blends_into_dark_background` | Does low light remove subject readability? |
| `bright_background_pull` | Does a bright background pull attention away? |
| `unclear_focus_hierarchy` | Is it unclear what should be read first? |
| `timing_blocker_in_frame` | Is a transient person/object blocking an otherwise usable view? |
| `background_clutter` | Is stable background detail unnecessarily busy? |

Severity is `minor`, `moderate`, `major`, or `critical`. Add at least one
evidence kind (`visible_composition`, `subject_relation`, `lighting`,
`horizon`, `motion`, `temporal_change`, `before_after_metric`, or
`human_context`). An issue may list more than one acceptable action and more
than one forbidden action. The global action lists must remain consistent with
the issue lists.

## 4. Actions: acceptable versus forbidden

`acceptable_action_ids` are physically plausible ways to improve the same
issue; they are not an instruction to perform all of them. Select one only
when the evidence supports a preferred action. `selection_status=multiple_valid`
is required when two or more alternatives are genuinely acceptable.

The v1 closed action catalog is:

- camera: `shift_frame_left`, `shift_frame_right`, `shift_frame_up`,
  `shift_frame_down`, `step_back`, `step_closer`, `lower_camera`,
  `raise_camera`, `change_camera_angle`, `level_horizon`;
- subject: `rotate_subject_toward_light`, `move_subject_left`,
  `move_subject_right`, `move_subject_away_from_background`;
- object/prop: `move_object_left`, `move_object_right`,
  `move_object_forward`, `move_object_back`, `remove_distracting_object`,
  `reposition_prop_for_balance`;
- light: `add_front_fill_light`, `add_background_light`,
  `remove_background_hotspot`;
- cleanup/timing: `simplify_background`, `wait_for_background_clearance`;
- no-change: `keep_current_setup` only for a KEEP label.

Do not list opposing moves as both acceptable actions. Do not make an action
acceptable merely because it is available in the UI. An action that would
damage the selected subject, erase an intentional style, or contradict the
visible issue is forbidden. `acceptable_action_ids` and
`forbidden_action_ids` must be disjoint.

## 5. KEEP

Use KEEP when the current frame is already usable for its stated intent and no
corrective action is needed. Encode:

```json
{
  "keep_decision": "keep",
  "acceptable_action_ids": ["keep_current_setup"],
  "selected_action_id": "keep_current_setup",
  "selection_status": "single",
  "abstention": {"status": "none", "reasons": []},
  "verification": [{"action_id": "keep_current_setup", "verifier_id": "frame_remains_acceptable", "result": "not_run", "measurement": "single_frame"}]
}
```

`keep_current_setup` is the only approved no-change action and may be listed
only when the same no-change decision is explicit. KEEP does not mean
the frame is universally beautiful or that a model is accurate. A frame can
have strengths and still be KEEP; any visible major issue requires a corrective
action or ABSTAIN.

## 6. ABSTAIN

Use ABSTAIN instead of guessing when the subject or issue is unclear, visibility
is insufficient, style intent cannot be separated from a defect, rights/privacy
blocks review, or a before/after pair is not comparable. Encode:

```json
{
  "acceptable_action_ids": [],
  "forbidden_action_ids": [],
  "selected_action_id": null,
  "selection_status": "abstain",
  "keep_decision": "uncertain",
  "abstention": {"status": "abstain", "reasons": ["subject_unclear"]},
  "verification": [{"action_id": "abstain", "verifier_id": "insufficient_evidence", "result": "inconclusive", "measurement": "not_observed"}]
}
```

Never convert `incomparable`, `track_loss`, or an unresolved hard disagreement
into a corrective action. ABSTAIN is a valid safety outcome and remains
quarantine/holdout evidence until human review resolves it.

## 7. Action-specific verification

Every acceptable action has one corresponding `verification` entry. The
verifier states what observable condition would confirm that action; it is not
a model score. Use `not_run` for a still label without an after state,
`temporal_timeline` for a sequence, and `before_after` for an episode.

| Action | Verifier |
|---|---|
| `shift_frame_left` | `framing_left_improves` |
| `shift_frame_right` | `framing_right_improves` |
| `shift_frame_up` | `headroom_or_upper_boundary_improves` |
| `shift_frame_down` | `lower_frame_context_improves` |
| `step_back` | `framing_breathing_room_increases` |
| `step_closer` | `subject_prominence_increases` |
| `lower_camera`, `raise_camera` | `perspective_height_improves` |
| `change_camera_angle` | `background_or_perspective_improves` |
| `level_horizon` | `horizon_tilt_decreases` |
| `rotate_subject_toward_light` | `subject_light_direction_improves` |
| `move_subject_left` | `subject_position_improves_left` |
| `move_subject_right` | `subject_position_improves_right` |
| `move_subject_away_from_background`, `add_background_light` | `subject_separation_increases` |
| `move_object_left` | `object_position_improves_left` |
| `move_object_right` | `object_position_improves_right` |
| `move_object_forward` | `object_depth_relation_improves_forward` |
| `move_object_back` | `object_depth_relation_improves_back` |
| `remove_distracting_object`, `simplify_background`, `remove_background_hotspot` | `background_competition_decreases` |
| `reposition_prop_for_balance` | `object_balance_improves` |
| `add_front_fill_light` | `subject_exposure_improves` |
| `wait_for_background_clearance` | `transient_blocker_clears` |
| `keep_current_setup` | `frame_remains_acceptable` |
| ABSTAIN | `insufficient_evidence` |

For an episode, `episode.action_step.action_id` must be one of the acceptable
actions and `outcome_verifier` must be the matching predicate. All timestamps
must satisfy `before.captured_at < action_step.performed_at <
after.captured_at`. `correct` is valid only when that chronology holds and the
matching label verification is `pass` with `before_after` measurement. Record
the outcome as `correct`, `no_op`, `opposite`, `overshoot`, `track_loss`, or
`incomparable`; failure or inconclusive verification cannot be relabeled as
correct, and no outcome implies a model-quality metric.

## 8. Temporal records

Annotate the sequence as one record. Frame ordinals are contiguous, timestamps
are strictly increasing, and all frames share the source shoot, take family,
derivation family, and split. Use the timeline to mark acquisition, stable
periods, movement, rotation, lens change, lighting transition, or scene cut.
Never make a frame-by-frame vote look like independent still evidence.

## 9. Review and disagreement

`review.vote_history` is append-only. Each independent annotator submission is
a new vote entry; do not replace a previous vote. `adjudication_history` is a
separate append-only array and may reference prior vote IDs. Candidate/model
outputs are never written into either array. An `adjudicated` status requires
the evidence of the votes and a separate adjudication event; it does not erase
the disagreement history.

Hard disagreements include subject identity mismatch, acceptable versus
forbidden action conflict, KEEP versus corrective action, ABSTAIN versus a
forced action, and non-comparable before/after states. Preserve the conflict
and route it to adjudication or holdout; do not average semantics.

### Pending HUMAN work

The required calibration exercise is not completed by this draft: two human
annotators must independently label a 35-case packet, then an adjudicator must
produce a disagreement report and any versioned guide corrections. Until that
report exists, no human agreement, calibration quality, or release readiness
claim may be made.
