# Swift UML Generator

`generate_swift_uml.py` builds a class-diagram source file from Swift code in this repo.
It is aimed at `SceneGeneratorModule`, where a single diagram around `SceneScript`
often needs to include nearby planning/parsing/runtime types to demonstrate system complexity.

## What It Extracts

- `class`, `struct`, `enum`, `protocol`
- nested types such as `SceneActor.ActorType`
- stored and computed properties
- enum cases
- protocol conformance / inheritance for local project types
- associations inferred from property types

## Commands

Base diagram centered on `SceneScript.swift`:

```bash
python3 docs/uml/generate_swift_uml.py \
  shafinMultitool/SceneGeneratorModule/Models/SceneScript.swift \
  -o docs/uml/scene-script-models.mmd
```

Expanded diagram for `SceneScript` plus adjacent module structures:

```bash
python3 docs/uml/generate_swift_uml.py \
  shafinMultitool/SceneGeneratorModule \
  --focus SceneScript ParsingResult PlannedScene ScenePlanIR SceneBundleScript SceneGeneratorViewModel \
  --neighbor-depth 2 \
  -o docs/uml/scene-generator-complexity.mmd
```

PlantUML source for export to SVG/PNG:

```bash
python3 docs/uml/generate_swift_uml.py \
  shafinMultitool/SceneGeneratorModule \
  --focus SceneScript ParsingResult PlannedScene ScenePlanIR SceneBundleScript \
  --neighbor-depth 2 \
  --format plantuml \
  -o docs/uml/scene-generator-complexity.puml
```

If `plantuml` is installed locally, you can render the generated file like this:

```bash
plantuml -tsvg docs/uml/scene-generator-complexity.puml
```

## Notes

- `--focus` accepts either a short type name like `SceneScript` or a full nested name.
- `--neighbor-depth 1` keeps direct neighbors only; `2` usually gives a good thesis/demo view.
- `--hide-properties` is useful when the graph gets too dense.
- Mermaid output works well in Markdown viewers and Mermaid-compatible editors.
