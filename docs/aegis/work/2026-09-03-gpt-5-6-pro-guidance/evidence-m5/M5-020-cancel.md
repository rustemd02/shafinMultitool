# M5-020 — generation cancel

Status: **production owner verified on the current store; no production change required**.

## Verified behavior

`SceneGeneratorViewModel.cancelGeneration` is idempotent (guards
execution-in-flight or clarification), publishes the typed `.cancelling`
state under the request UUID+epoch fence, cancels and awaits the generation
task, bumps the epoch so late parser/binding callbacks lose the
`generationIsCurrent` fence, clears the leader presentation, returns to the
editable `.input` draft with the clarification projection cleared, and never
publishes success after a cancel. Local parser work has no backend to
cancel; the same fences cover the parse/binding continuation (M1-008 fence
suites).

## Verification

`testClarificationCancelReturnsDraftAndClearsRequest` (draft preserved,
request cleared), the M1-008 request-fence suite (7/7: stale completions
lose, in-flight writes invalidated), and the M5-014 request state machine
tests. 13/13 + 8/8 across the two focused runs on permitted iPhone 17e
(`/private/tmp/m5-020-m6-015.xcresult`, `/private/tmp/m5-020-r2.xcresult`).
