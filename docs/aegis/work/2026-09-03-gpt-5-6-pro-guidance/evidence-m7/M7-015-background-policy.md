# M7-015 — background policy

Status: **implemented and verified on the current store**.

## Behavior delivered

- `CommercialShellViewController.handleSceneDidEnterBackground` opens exactly
  one UIKit background task lease (`SceneBackgroundTaskCoordinator`, name
  `set-scene-background-flush`) covering the whole lifecycle dispatch —
  including the awaited scene workspace teardown that stops and finalizes an
  active recording — and ends the lease exactly once when the dispatch
  completes. The camera-route and no-route paths end it synchronously.
- Expiration: UIKit invokes the coordinator's expiration handler shortly
  before revocation; it ends the currently live identifier exactly once.
  Because the recording stop/finalize is single-flight on the serialized
  owners, an expired lease can never produce a second finalize or a hidden
  second clip.
- Cold-recovery sufficiency: a finalize flushed under the lease (or lost to
  suspension) converges through the M7-019 journal / M7-021 cold-launch
  maintenance on the next launch — `pending`/`promoting` records plus the
  pending file are exactly the durable state recovery classifies.
- "Background stop starts once": the awaited scene teardown is the M1-009
  single-flight operation (regression green in the same lane).

## Verification

`CommercialShellLifecycleAdapterTests` 7/7 on permitted iPhone 17e
(`/private/tmp/m7-015-tests-r4.xcresult`): lease begun once per event and
ended after the scene dispatch flushes; no-route path begins and ends
immediately; a second background event cannot end a stale lease; the four
M1-004 forwarding regressions stay green.

## Honest boundary

Physical suspension timing, task-expiration budgets under load, and
real background audio-session behavior remain M13 device qualification.
