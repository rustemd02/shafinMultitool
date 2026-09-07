# M6-016 + M6-017 — world map save/restore evidence

Status: CLOSED on the current store (simulator-provable half; hardware
capture is M13).

## Pre-existing owner (audited, no production change)

`DBService.saveUnifiedSceneProject(_:worldMap:expectedUpdatedAt:)`
writes project + `archivedWorldMap` into ONE versioned file
(`schemaVersion` 1) under a single atomic write on the serial
persistence queue; the M1-015 optimistic-conflict guard
(`DBServiceError.staleSnapshot`) rejects stale callers. Load decodes
project and map together (`loadUnifiedSceneProject`); the VM
restore path injects the loaded map as `initialWorldMap` into the
next AR session configuration (one-session-owner generation fence,
M6-002); no anchor duplication occurs because restore is
configuration-input, not runtime mutation.

## Added contract proof

`shafinMultitoolTests/ARWorldMapPersistenceTests.swift` — 4/4 PASS on
permitted iPhone 17e (`/private/tmp/m616-tests.xcresult`):

- file schema carries versioned `schemaVersion` + `project` (the
  optional `archivedWorldMap` member appears via encodeIfPresent —
  key present only when a map exists);
- project without map loads with an honest nil map;
- corrupt `archivedWorldMap` payload fails closed: the loader never
  surfaces a bogus map and never crashes (typed nil overall or nil
  map);
- stale optimistic write throws `staleSnapshot` and leaves the
  stored file (id + updatedAt) untouched.

Two fixture corrections during the run reflect the real contract:
nil maps omit the key (encodeIfPresent), and a stale caller is one
presenting an outdated `expectedUpdatedAt` (a caller with a current
expectation writing old data is outside the M1-015 contract).

## Boundaries

Real `ARWorldMap` capture/relocalization requires a live ARSession —
physical qualification (capture success, relocalization quality,
fallback-to-reset on incompatible maps) remains M13 per the plan's
simulator-work-is-contract-evidence rule.
