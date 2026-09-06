# M5-023 — retry/idempotency

Status: **closed on the current store**.

## Distinguished paths

- **Transport retry: not applicable locally.** No backend transport exists
  (M5-025 external); there is nothing to retry at the transport layer, and
  no fake retry loop was added.
- **Clarification continuation: same UUID+epoch.** Proven by the M5-017
  suite (stale/repeated answers rejected, exactly one commit).
- **New edited request: new epoch.** A submit after a terminal/retryable
  result clears the previous identity and issues a new epoch; the editable
  draft is preserved.
- **Duplicate success coalesced.** Concurrent submits join the single
  in-flight generation task (`if let generationTask { await value; return }`)
  — one request owner, one validating edge.

## Verification

New `GenerationRetryIdempotencyTests` 3/3 on permitted iPhone 17e
(`/private/tmp/m5-023-tests-r2.xcresult`): single-flight coalescing,
new-epoch resubmit, clarification cancel retires without spawning a job.
