# M5-013 — Library downstream links

## Boundary

The production Library open path now carries the persisted project UUID from
the typed presenter into `SORouter.loadScene(id:)`. `DBService` performs one
strict, read-only aggregate load by the canonical UUID filename, decodes the
versioned M5-002 envelope, resolves M5-012 recording references through
`RecordingArtifactStore`, and returns a link classification before the
existing `SceneGeneratorViewModel` is constructed. The VM receives that loaded
aggregate directly, so its project identity is not re-derived from the
mutable display name.

Link statuses are `healthy`, `compatibleLegacy`, `optionalMissing`, and
`blocking`. Missing optional screenplay, AR, storyboard, world-map, or media
data remains truthful metadata/legacy state. A malformed aggregate, future
schema, mismatched project identity, malformed downstream identity, or
declared recording reference that is foreign, unsafe, missing, empty, or
undecodable returns the existing typed `.persistence`/`.missingProject`
failure before workspace construction. No read path repairs or rewrites a
project, and no fixture or placeholder is used as persisted downstream data.

## Verification

All checks used the ordinary `iPhone 17` iOS `26.5` simulator only; no physical
device was targeted.

| Check | Result |
| --- | --- |
| `xcodebuild ... build-for-testing` with `-destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5'` | passed |
| `xcodebuild test ... -only-testing:shafinMultitoolTests/SceneProjectOpenTests` | 6 tests, 0 failures |
| Targeted regression: `SceneProjectSchemaMigrationTests`, `DBServiceConcurrencyTests`, `SETLibraryModelTests`, `RecordingArtifactPromotionTests` | 53 tests, 0 failures |
| `git diff --check` | passed |

The focused open tests cover current healthy UUID preservation, compatible
legacy byte preservation, missing/corrupt/future project recovery, optional
media absence, foreign/missing required recording artifacts, malformed
downstream identity, immutable-ID retry, and the actual
`SOModuleBuilder`/presenter/router boundary.
