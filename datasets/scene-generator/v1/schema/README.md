# Scene Generator schema v1

This directory is the versioned dataset/transport contract for the Scene
Generator. It is deliberately separate from the runtime owners: the existing
`SceneScript` Codable aggregate remains the projection target and no Swift
domain model is introduced here.

## Contract map

| File | Boundary | Encoding and authority |
|---|---|---|
| `scene-input-v1.schema.json` | app → Scene service | snake_case request envelope; `script_text` is retained verbatim |
| `scene-script-v1.schema.json` | validated SceneScript | camelCase fields matching `SceneScript.swift` Codable keys |
| `scene-output-v1.schema.json` | model/service → app | exactly `complete` or `clarification_required` |
| `scene-clarification-v1.schema.json` | request-owned clarification surface | one immutable `SceneClarificationPayload` with bounded observed options; no guessed answer |
| `scene-annotation-v1.schema.json` | dataset annotation | source boundaries, candidates, alternatives, forbidden hallucinations, append-only votes/reviews |
| `scene-contract-v1.schema.json` | shared definitions | IDs, enums, entities, SceneScript, validation records |

The version lives on the transport envelope. A raw `SceneScript` intentionally
has no added `schemaVersion` field, so decoding and encoding remain compatible
with the current Swift model and its existing `SceneScript` JSON projection.
The clarification schema mirrors the request-owned Swift payload exactly:
`id`, `requestID`, `epoch`, `prompt`, optional `targetReference`, `options`,
`allowsFreeText`, `maximumFreeTextCharacters`, `observedDiagnostics`, and
`attempt`. It exposes one payload rather than a collection of independent
question records, so the request owner remains the sole source of truth.

Scene boundary `start`/`end` values are half-open UTF-8 byte offsets into the
owning `script_text`/`source_text`. The checker requires both offsets to fall
on UTF-8 code-point boundaries, so Cyrillic and emoji cannot be split.

## Semantic invariants

JSON Schema covers shape, bounded text, enums and ID syntax. The checker also
enforces the invariants that JSON Schema cannot express across sibling arrays:

- actor/action/target/holding/relation/camera references resolve to the same
  SceneScript entity registry;
- IDs are unique within their namespace and beat/action order is retained;
- marked object references use exact `object_marked_*` IDs; same-type markers
  are not collapsed;
- `talk` has dialogue and `described_action` has both `sourceText` and
  `fallbackText`;
- source scene boundaries are ordered, non-overlapping UTF-8 byte ranges;
- clarification payload IDs deterministically include request ID, epoch,
  target reference (or `parser`) and attempt;
- clarification options are bounded observed candidate IDs; the fixture
  harness checks that payload request ID/epoch and every option resolve against
  the submitted binding snapshot, rejecting stale requests/epochs and unknown
  options;
- annotation gold IDs resolve to candidates/variants, validation status agrees
  with its issue list, the primary candidate is validation-valid, every
  validation-valid candidate and all gold marked-object references resolve to
  declared markers, and vote/review histories have unique, strictly
  increasing append-only sequence numbers;
- declared input scene boundaries are valid UTF-8 byte ranges and their count
  cannot exceed `constraints.maximum_scenes`;
- JSON source text is UTF-8 and never contains NUL; raw rights disposition is
  not invented here and is owned by M3-024 provenance manifests.

No fixture is a production dataset, a rights grant, or model-quality evidence.
Fixtures are synthetic and exist only to test contract behavior.

## Checks

From the repository root:

```bash
python3 datasets/scene-generator/v1/schema/validate_scene_schema.py --self-test
python3 datasets/scene-generator/v1/schema/validate_scene_schema.py
```

The checker requires an installed Draft 2020-12 JSON Schema validator and keeps
stdlib semantic checks for cross-references and append-only history. It fails
closed if `jsonschema` is unavailable and bounds every file read to 2 MiB. It
never imports or invokes production Swift code.

`clarification-case-*.json` files are checker-only verification sidecars. They
contain a payload plus the minimal identity/candidate projection of the
submitted M5-016 binding snapshot; the production `SceneClarificationPayload`
does not duplicate that snapshot.
