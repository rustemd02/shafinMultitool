# M0-008 — route reachability

Status: **verified on the current store; no production change required**.

| Route | Entry condition | Build config | Owner | Reachable states | Teardown boundary | Status |
|---|---|---|---|---|---|---|
| camera (Coach) | eager default section | app target, Debug+Release | `CommercialCameraCoachRoute` | entry/intro/permission/request/live/pause + recording subflow | `reportSceneInactive` (idempotent) | public |
| scenes (Generator/AR/Storyboard) | lazy on select | app target, Debug+Release | `CommercialSceneLibraryRoute` | workspace + review player + share + alerts | awaited `teardownAndWait` single-flight | public |
| history | lazy on select | app target, Debug+Release | history route (no-op teardown) | stub surface | no-op | internal stub |

Verified by `CommercialShellRoutingTests` (10 tests: eager/lazy, single
child, owner-order release, blocked deactivation, mode lock, coalescing)
and `CommercialShellLifecycleAdapterTests` 7/7 (single event forwarding,
background lease). All routes build in both configurations (M0-005/006).
