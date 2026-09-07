# M3-005 + M3-006 — Camera annotation guide & tooling evidence

Status: M3-005 CLOSED (verify-and-close), M3-006 CLOSED (tool
delivered with tests). The human PILOT (M3-009) that consumes both
remains external.

## M3-005 — annotation guide (verify-and-close)

`datasets/camera-coach/v1/annotation-guide.md` (269 lines, v1.0.0)
is the operational rubric: eligibility/quarantine before labeling,
subject selection discipline (selected/ambiguous/none/abstain with
the null-ID rule), approved action IDs mirrored from
`docs/implementation/camera-coach-contract-v2.json` (no free-form
advice, no legacy aliases, no model output), explicit abstention
reasons including `rights_or_privacy_blocker`, and the owned record
schemas (unknown fields rejected recursively). It is aligned with
the visible UI actions and the verifier predicates referenced by the
CC contract. Writing the guide required no human annotators; the
two-annotator calibration PILOT that applies it is M3-009 (external).

## M3-006 — annotation tooling (delivered)

`tools/camera_annotation/annotate_camera.py`:

- append-only JSONL store — votes are never rewritten or removed;
- hidden QC by construction: any record whose tree contains
  candidate/model field names (`candidate*`, `model*`, `*score*`,
  `probability`, `prediction`, …) is rejected at admission AND on
  load (a poisoned store fails closed); annotator prose is free text;
- adjudication is a separate record type referencing vote IDs — the
  adjudicator resolves without overwriting votes (byte-identical
  votes proven after adjudication);
- vote discipline: verdict/subject-state vocabularies, null
  `selected_subject_id` required for ambiguous/none/abstain,
  abstention requires a reason;
- thread-safe appends (lock) — concurrent distinct annotator IDs all
  persist;
- `export` emits a review bundle with counts and the full
  append-only record list.

## Verification

`backend/tests/test_camera_annotation_tool.py`: 6/6 PASS (round-trip
export, hidden-QC key leak rejection incl. poisoned store load,
8-thread concurrent annotator IDs, adjudication append-only
discipline, adjudication required fields, subject-state null-ID
rules) — 32/32 across the backend suite. CLI smoke:
`vote`/`adjudicate`/`export` subcommands with fail-closed exit codes.
