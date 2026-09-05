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
| `scene-clarification-v1.schema.json` | clarification branch | bounded question IDs/options; no guessed answer |
| `scene-annotation-v1.schema.json` | dataset annotation | source boundaries, candidates, alternatives, forbidden hallucinations, append-only votes/reviews |
| `scene-contract-v1.schema.json` | shared definitions | IDs, enums, entities, SceneScript, validation records |

The version lives on the envelope. A raw `SceneScript` intentionally has no
added `schemaVersion` field, so decoding and encoding remain compatible with
the current Swift model and its existing `SceneScript` JSON projection.

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
- source scene boundaries are ordered, non-overlapping character ranges;
- clarification options are bounded and every non-free-text question exposes
  an option;
- annotation gold IDs resolve to candidates/variants, validation status agrees
  with its issue list, and vote/review histories have unique, strictly
  increasing append-only sequence numbers;
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

The checker uses the installed JSON Schema validator when available and keeps
a stdlib semantic checker as the source of cross-reference and append-only
checks. It never imports or invokes production Swift code.
