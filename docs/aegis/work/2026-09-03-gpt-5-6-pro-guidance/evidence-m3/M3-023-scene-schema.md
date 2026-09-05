# M3-023 — Scene Generator schema v1 evidence

Status: FIX-FIRST correction complete on the isolated `codex/set-os-m3-023` lane.

Base commit: `effcbd4` (`state: start independent M3-023 schema lane`).
No `EXECUTION_STATE.md` or production Swift file was changed. The existing
`SceneScript` Codable projection is compatible with the frozen `camelCase`
script schema, so no compatibility edit was necessary.

## Delivered contract

The new versioned contract under `datasets/scene-generator/v1/schema/` covers:

- the snake-case app request envelope (`scene-input-v1`), including RU/EN
  source text, marked-object IDs, optional source scene ranges, constraints,
  previous-job and consent fields;
- the existing `SceneScript` camel-case projection (`scene-script-v1`) with
  bounded actors, objects, beats/actions, camera targets, spatial relations,
  optional source/fallback text and stable ID namespaces;
- complete and clarification-required response branches
  (`scene-output-v1` and `scene-clarification-v1`). The clarification branch
  is one request-owned `SceneClarificationPayload` mirroring the existing
  Swift owner: request UUID/epoch, stable payload ID, prompt, target
  reference, bounded observed options, free-text limit, diagnostics and
  attempt. It deliberately has no invented multi-question envelope;
- dataset annotation records (`scene-annotation-v1`) retaining scene
  boundaries, marked objects, human/deterministic/model candidates, acceptable
  structured variants, forbidden hallucinations, gold references, and
  append-only vote/review history;
- shared Draft 2020-12 definitions in `scene-contract-v1.schema.json`.

`validate_scene_schema.py` requires Draft 2020-12 shape validation and combines
it with a stdlib semantic checker. It rejects dangling actor/object/camera/
relation/holding references, duplicate IDs, invalid marker bindings, malformed
ranges, stale clarification request UUID/epoch, unknown options outside the
submitted binding snapshot, contradictory validation statuses, gold candidates
that are not validation-valid, unresolved `object_marked_*` references in
every validation-valid candidate and gold-listed variant, input boundary sets
that exceed `constraints.maximum_scenes`, and non-monotonic provenance history.
Every input file is size-bounded before it is read; an unavailable `jsonschema`
validator fails closed. Rights/license/source ownership is intentionally left
to M3-024; this schema does not invent a rights disposition.

## Fixtures

Positive fixtures:

1. `input-valid-ru.json` — RU request with marked object and source text.
2. `script-valid-en.json` — EN SceneScript with two actors, marked object,
   ordered beats/actions, camera target and spatial relation.
3. `output-valid-complete.json` — complete response.
4. `clarification-valid.json` — one request-owned clarification payload with
   stable ID and observed options.
5. `annotation-valid.json` — human/model candidates, acceptable variant,
   forbidden hallucination and append-only votes/reviews.
6. `input-valid-ru-emoji-boundaries.json` — declared UTF-8 byte boundaries
   across Cyrillic and emoji.
7. `output-valid-clarification.json` — clarification payload in the output
   branch.
8. `clarification-case-valid.json` — payload options resolving in the
   submitted binding snapshot.

Negative fixtures:

1. `script-invalid-target.json` — action target is not in the entity registry.
2. `output-invalid-target.json` — output action points at a missing actor.
3. `annotation-invalid-history.json` — review sequence moves backwards.
4. `annotation-invalid-gold-candidate.json` — gold points to a candidate whose
   validation is not valid.
5. `annotation-invalid-marked-reference.json` — gold SceneScript references
   an undeclared marked object.
6. `clarification-case-invalid-stale-request.json` — payload UUID does not
   match the submitted snapshot.
7. `clarification-case-invalid-stale-epoch.json` — payload epoch does not
   match the submitted snapshot.
8. `clarification-case-invalid-unknown-option.json` — option is not present in
   the submitted snapshot.
9. `annotation-invalid-secondary-marked-reference.json` — a secondary
   validation-valid candidate references an undeclared marked object.
10. `input-invalid-boundary-count.json` — two valid boundaries exceed a
    `maximum_scenes` constraint of one.

## Verification

Commands run from repository root:

```text
python3 datasets/scene-generator/v1/schema/validate_scene_schema.py --self-test
PASS M3-023 self-test: 8 positive, 10 negative fixtures, and target mutation

python3 datasets/scene-generator/v1/schema/validate_scene_schema.py
PASS M3-023 positive fixture set

python3 -S datasets/scene-generator/v1/schema/validate_scene_schema.py --self-test
exit 1; FAIL Draft 2020-12 validator unavailable; refusing to validate

python3 -m py_compile datasets/scene-generator/v1/schema/validate_scene_schema.py
PASS

python3 -m json.tool datasets/scene-generator/v1/schema/<each JSON file>
PASS all JSON files
```

The self-test also mutates a valid output target to `object_999` and confirms
that the semantic checker rejects the mutation. The `python3 -S` run confirms
the checker refuses to proceed without Draft 2020-12 validation rather than
silently accepting fixtures. No simulator or physical-device verification is
applicable to this dataset/schema-only task.

## Changed files

- `datasets/scene-generator/v1/schema/README.md`
- `datasets/scene-generator/v1/schema/scene-contract-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-input-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-script-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-output-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-clarification-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-annotation-v1.schema.json`
- `datasets/scene-generator/v1/schema/validate_scene_schema.py`
- eighteen JSON fixtures in `datasets/scene-generator/v1/schema/fixtures/`
- this evidence report

## Known limits and handoff

- M3-024 source/license/consent/derivation manifests remain a separate task;
  the annotation record deliberately contains no fabricated rights metadata.
- M3-025 annotation guidance and M3-026 annotation tooling are not included.
- The schema/checker is not a production network validator and does not import
  Swift runtime code; M12-003 must adopt the schemas at the backend boundary.
- The clarification binding sidecars are checker-only projections of the
  M5-016 submitted snapshot; they do not become a second runtime owner.
- A raw SceneScript has no added `schemaVersion` property, preserving existing
  Codable compatibility; the version is carried by input/output envelopes.
- No M3 gate or milestone status is claimed by this evidence report.
