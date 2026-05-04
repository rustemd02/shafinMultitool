# V9.1 Runtime Architect

## proposal
- Make screenplay parsing bundle-first: preserve pre-heading montage as non-AR scene, keep first physical scene as active AR scene.
- Extend normalizer with inline speaker cues, stage notes, screen text, long-dialogue splitting, and implicit post-dialogue shot detection.
- Preserve bundle overlays through `SceneBundleParsingResult`, `ScriptDocumentState`, and runtime UI.

## risks
- Active scene selection must not jump to later implicit shots and surprise AR playback.
- Append ranges still need future hardening for overlays if non-tail edits become finer than scene-level reparse.

## required_tests
- Inline `Ведущий: text` split.
- Montage screen text overlay.
- Real series fragment: montage + TV dialogue + Rustam implicit shot.

## open_conflicts
- Dynamic per-slot grammar remains deferred; verifier/patch is the enforcement layer in V9.1.

## approval
PASS for runtime/contract gate after build-for-testing evidence.
