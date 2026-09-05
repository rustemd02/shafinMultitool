# M6-015 — AR background/foreground

Status: **production owner verified on the current store; no production change required**.

## Verified behavior

- **Background, exactly once:** `sceneDidEnterBackground` → shell dispatch
  (M1-004 single event) → scenes route `handleDidEnterBackground` → the
  single-flight `teardownAndWait()` which stops an active recording (M7-015
  background lease now covers the finalize window), persists the recoverable
  project state, and releases the AR session last in the canonical owner
  order. A second background event joins the same completed teardown
  (`testBackgroundReachesSceneWorkspaceProviderExactlyOnce`).
- **Foreground, honest recovery:** the ARSessionOwner applies interruption
  safety once per generation; on return the session relocalizes and only a
  real frame with detected planes promotes the workspace back to ready —
  otherwise the UI stays in the honest recovering/blocked state with the
  reset available through route exit. No silent ready promotion exists.

## Verification

`ARSessionOwnershipTests` 6/6 (single owner, interruption safety once,
release fencing) and `CommercialShellLifecycleAdapterTests` 7/7 (single
dispatch, lease, route exclusivity) — 13/13 in
`/private/tmp/m5-020-m6-015.xcresult` on permitted iPhone 17e.

## Honest boundary

Real ARKit relocalization behavior on device remains M13.
