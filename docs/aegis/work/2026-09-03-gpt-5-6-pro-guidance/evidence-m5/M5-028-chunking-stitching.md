# M5-028 — chunking/stitching evidence

Status: CLOSED on the current store.

## Pre-existing owner (audited, no production change)

The full pipeline already exists and is contract-tested:
`ScriptNormalizer` → `SceneBoundaryDetector` → `ChunkSegmenter` →
`SceneChunkAnchorExtractor` → canonicalizer → `SceneStitcher.apply/
finalize` → `SceneBundleCompiler`; request-owned execution policies
(monolithic/chunkedThermalAware) with per-chunk + final JSON
checkpoints written through an injectable support seam; previousState
reuse paths (append/full). Checkpoint behavior already covered by
`SceneBundlePipelineTests` (monolithic writes only the final payload;
chunked writes one payload per chunk + final; counts asserted).

## Added continuity proof (this task)

`shafinMultitoolTests/SceneChunkContinuityTests.swift` — 7/7 PASS on
permitted iPhone 17e (`/private/tmp/m5028-tests.xcresult`):

- entity IDs survive across chunk boundaries (actors/objects merged
  by ref, chunk ledger ordered c1→c2);
- duplicate cross-chunk identity merges to a single actor;
- beat chronology preserved in apply order and through `finalize`;
- scene entries sort by `sceneIndex` regardless of processing order;
- deferred (unresolved) references never fabricate actors: the
  unresolved action/beat drops instead;
- continuity diagnostics deduplicate across chunks;
- chunk checkpoint payload round-trips byte-exact through
  JSONEncoder/JSONDecoder (injected-interruption recovery shape).

One stitcher behavior surfaced by the fixtures (beats referencing
unregistered actors are filtered at apply) is the honest no-fabrication
posture — fixture corrected, production untouched.

## Boundaries

Long-form locked fixtures with live backend interruption remain M13
device/soak work; the checkpoint/recovery seam itself is proven here.
