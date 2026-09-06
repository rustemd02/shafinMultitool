# M3-002 — camera data schema

Status: **verified on the current store; no schema change required**.

The versioned `datasets/camera-coach/v1/label-schema.json` represents every
verify column: seven issue classes (via `issue` defs), multi-valid actions
(`acceptable_action_ids` + `forbidden_action_ids` + `selected_action_id`),
selected subject (`subject.status/candidates/selected_subject_id` with
`selected/ambiguous/none/abstain`), intentional style
(`styleIntent.style_id/intentional/basis`), abstention (subject + label
`abstention` + `selection_status`), action-specific verification
(`verification` + `verificationActionId` enum), provenance
(`source_shoot_id/asset_ids/derivation_family/rights_record_id/disposition/source_kind/raw_storage`),
and review status (`review.status/vote_history/adjudication_history`).

## Verification

Schema-def audit above (each column → named defs/fields) plus the M3-001
governance self-test green (`fixture_sha256=1ab4d87…`) on this checkout.
No corpus, rights, or model-quality claim.
