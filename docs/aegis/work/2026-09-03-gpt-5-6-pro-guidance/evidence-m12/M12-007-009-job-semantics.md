# M12-007 + M12-008 + M12-009 — backend job semantics evidence

Status: all three CLOSED on the current store (one reference batch).

## Delivered

- `backend/scene_job_store.py` (M12-007 + M12-008): thread-safe
  single-service job owner. Idempotency: same installation+key+hash
  replays the same job; same key with a different hash raises
  `IdempotencyConflict`; keys are installation-scoped. Lifecycle:
  `queued → running → {awaiting_clarification ↔ running,
  succeeded, failed, cancelled, expired}`; transitions atomic +
  versioned (`VersionConflict` on stale epoch, `IllegalTransition`
  on forbidden edge); terminal states immutable except `delete()`;
  provider work runs at most once per accepted job (`accept`
  serializes concurrent callers); bounded client polling via
  version-change reads; `expire_overdue` sweeps non-terminal jobs
  past their deadline.
- `backend/scene_provider_policy.py` (M12-009): frozen policy —
  provider timeout ≤45 s, at most one retry for retryable transport
  failures inside a 60 s job deadline, no retry on invalid
  output/content, circuit opens after 3 consecutive failures and
  half-opens after 30 s, explicit client-visible retryability
  (`retryable` / `terminal` / `clarify`).
- `backend/tests/test_scene_job_semantics.py`: 17 tests covering
  replay, conflict, installation scoping, at-most-once provider
  (incl. 8-thread concurrent accept and concurrent create), the full
  legal chain incl. clarification round-trip, terminal immutability
  for all three terminal states, stale-version conflict, versioned
  polling, overdue expiry, all five policy behaviors plus frozen
  constant bounds. Three test-side defects found and fixed during
  the run (`accept` returns the provider result, not the job —
  tests now re-read via `poll`). Result: 26/26 PASS with the
  M12-004 limits suite.

## Boundaries

Reference semantics only — the deployed service must enforce them
identically (deployment + provider selection remain external).
No network code, no credentials, no host selection in this task.
