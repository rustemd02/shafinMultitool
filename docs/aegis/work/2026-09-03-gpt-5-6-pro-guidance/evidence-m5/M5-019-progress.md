# M5-019 — progress

Status: **closed on the current store**.

Progress is monotonic within a request (`reading → planning → placing`
through the epoch-fenced `publishGenerationStage`), labels the actual
phase via localized status, has no indeterminate state that hides the
phase (the leader/countdown covers waiting visibly), and resets on
retry/new request (new epoch + fresh input edge; `testingResetGenerationStateTrace`
clears both traces).

Verification: `GenerationProgressTests` 1/1 on permitted iPhone 17e
(`/private/tmp/m5-019-tests-r2.xcresult`) over the new DEBUG stage-trace
hook; production path untouched.
