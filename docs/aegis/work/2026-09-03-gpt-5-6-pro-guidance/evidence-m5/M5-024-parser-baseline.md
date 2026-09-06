# M5-024 — local parser baseline

Status: **closed on the current store**.

## Production fixes (the tracker's "no silent semantic repair")

The baseline matrix exposed three real fabrication paths that are now closed:

1. **Default actor (`extractActors`).** An empty extraction minted a phantom
   `actor_1`. Removed — an empty extraction is now an honest no-actor
   result; diagnostics already carries the explicit "no actors" penalty and
   the `missingActors` flag.
2. **Phantom `actor_1` references (`determineActorForAction`).** Three
   `?? "actor_1"` fallbacks produced actions pointing at a nonexistent
   actor. The function now returns `String?`; the complex-pattern path
   skips actor-less actions (`continue`), and the simple-keyword path is
   guarded by `actors.first`.
3. **Fallback plan invention (`SceneBundlePipeline`).** Two fallback
   branches fabricated stand/talk beats on phantom first/second/third
   actors for any non-empty text, and `enrichRuleFallbackPlan` minted
   ordinal actors. Both fallback branches are removed; the ordinal
   synthesizer is gated behind an explicit `requiredCount` parameter.
4. **Described-action minting.** `enriched.actors.append` for unsupported
   actions is guarded: the action is recorded only for a real extracted
   actor.

Representability preserved: a static object-only scene (extracted objects,
no actions) compiles to objects + empty beats via the `isStaticObjectScene`
path in `ScenePlanCompiler` — no phantom actor, no fabricated beat. Added
RU plural keyword forms (столы/стулья/диваны) so legitimate plural inputs
resolve.

## Baseline matrix (`SceneParserBaselineTests`, 8 tests)

Valid RU scripts (two-actor approach, Oleg/phone/table, marked table),
EN action tokens on supported nouns, explicit failure (empty),
no-repair (gibberish invents nothing, confidence < 0.5), ambiguity flagged
(unresolved pronouns). Honest boundary: the local noun vocabulary is RU
(actor/object keyword tables); EN legs use the mixed-utterance real path.

## Verification

`SceneParserBaselineTests` 8/8 + `SceneParserServiceTests` 14/14 (22/22)
on permitted iPhone 17e (`/private/tmp/m5-024-tests-r8.xcresult`).
Affected lane: bundle pipeline + teardown + save/load + schema/open
149/151 — one registered pre-existing store failure
(`testDemoScenarioProviderPathRepairsTransferObjectsAndSourceOrder`) and
one unrelated order-dependent save/load case under separate classification
(`testArtifactCleanupFailureDoesNotChangeSuccessfulMetadataDeletion`,
parser-independent: the test never invokes the parser).
