# M3-023 — Scene Generator schema v1 evidence

Status: implementation complete on the isolated `codex/set-os-m3-023` lane.

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
  (`scene-output-v1` and `scene-clarification-v1`), with bounded candidate
  entity IDs/options and no guessed clarification answer;
- dataset annotation records (`scene-annotation-v1`) retaining scene
  boundaries, marked objects, human/deterministic/model candidates, acceptable
  structured variants, forbidden hallucinations, gold references, and
  append-only vote/review history;
- shared Draft 2020-12 definitions in `scene-contract-v1.schema.json`.

`validate_scene_schema.py` combines Draft 2020-12 shape validation (when the
already-installed `jsonschema` package is available) with a stdlib semantic
checker. It rejects dangling actor/object/camera/relation/holding references,
duplicate IDs, invalid marker bindings, malformed ranges, invalid clarification
options, contradictory validation statuses, and non-monotonic provenance
history. Rights/license/source ownership is intentionally left to M3-024; this
schema does not invent a rights disposition.

## Fixtures

Positive fixtures:

1. `input-valid-ru.json` — RU request with marked object and source text.
2. `script-valid-en.json` — EN SceneScript with two actors, marked object,
   ordered beats/actions, camera target and spatial relation.
3. `output-valid-complete.json` — complete response.
4. `clarification-valid.json` — bounded non-free-text clarification with valid
   alternatives.
5. `annotation-valid.json` — human/model candidates, acceptable variant,
   forbidden hallucination and append-only votes/reviews.

Negative fixtures:

1. `script-invalid-target.json` — action target is not in the entity registry.
2. `output-invalid-target.json` — output action points at a missing actor.
3. `annotation-invalid-history.json` — review sequence moves backwards.

## Verification

Commands run from repository root:

```text
python3 datasets/scene-generator/v1/schema/validate_scene_schema.py --self-test
PASS M3-023 self-test: 5 positive and 3 negative fixtures

python3 datasets/scene-generator/v1/schema/validate_scene_schema.py
PASS M3-023 positive fixture set

python3 -m py_compile datasets/scene-generator/v1/schema/validate_scene_schema.py
PASS

python3 -m json.tool datasets/scene-generator/v1/schema/<each JSON file>
PASS all JSON files
```

The self-test also mutates a valid output target to `object_999` and confirms
that the semantic checker rejects the mutation. No simulator or physical-device
verification is applicable to this dataset/schema-only task.

## Changed files

- `datasets/scene-generator/v1/schema/README.md`
- `datasets/scene-generator/v1/schema/scene-contract-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-input-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-script-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-output-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-clarification-v1.schema.json`
- `datasets/scene-generator/v1/schema/scene-annotation-v1.schema.json`
- `datasets/scene-generator/v1/schema/validate_scene_schema.py`
- eight JSON fixtures in `datasets/scene-generator/v1/schema/fixtures/`
- this evidence report

## Known limits and handoff

- M3-024 source/license/consent/derivation manifests remain a separate task;
  the annotation record deliberately contains no fabricated rights metadata.
- M3-025 annotation guidance and M3-026 annotation tooling are not included.
- The schema/checker is not a production network validator and does not import
  Swift runtime code; M12-003 must adopt the schemas at the backend boundary.
- A raw SceneScript has no added `schemaVersion` property, preserving existing
  Codable compatibility; the version is carried by input/output envelopes.
- No M3 gate or milestone status is claimed by this evidence report.
