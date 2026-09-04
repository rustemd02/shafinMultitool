# M1-008 — Scene parse/generation request-generation transition trace

Task: Fence SceneGenerator parse/generation tasks with request IDs and owner generation.
Owner boundary: `SceneGenerationOwner`. Rollback: revert SceneParserService.swift fence diff + delete SceneParseRequestFenceTests.swift.

## Pre-existing fencing (verified, unchanged)

- VM `generateScene()` (SceneGeneratorViewModel.swift:1316): single-flight via `generationTask`;
  `generationEpoch &+= 1` per request; `generationToken` captured; every await boundary in
  `performGeneration` re-checks `generationIsCurrent(token)` (Task.isCancelled + isWorkspaceReleased +
  epoch equality) before publishing stage/status/error/result.
- Teardown path (SceneGeneratorViewModel.swift:1127–1131): bumps `generationEpoch`, cancels
  `generationTask`, awaits it, nils it. Stale completion cannot pass the VM fence.
- SceneParseCoordinator: stateless per call (no instance mutation across requests).

## Gap found (M1-002 audit HAZ cluster "SceneWorkspaceOwner" / parse side)

`SceneParserService` pipelines (LLMParserService, SceneBundlePipeline) contain no cancellation
checks (grep: no `Task.isCancelled` / `checkCancellation` / `CancellationHandler`). A cancelled
generation's parse therefore runs to completion and its shared-context side effects fire late:

| Shared state written late | Write site | Reader on next generation |
|---|---|---|
| `lastBundleResult`, `lastExecutionTrace`, `lastDocumentState`, `lastChunkState`, `lastRuntimeTrace` | `updateBundleContext(with:)` after `bundlePipeline.parse/parseAsync` | VM commit block: `sceneChunkState = parserService.lastChunkState`, `visualOverlays = parserService.lastBundleResult?.visualOverlays` (VM:1546–1547); `lastRuntimeTrace` read at VM:1421 |
| `lastRuntimeTrace`, `lastChunkState` | after `makeParseCoordinator().parseAsync` (state path) | same |

Effect before fix: cancel/background/new-request → stale parse publishes context over a newer
request — violates "cannot publish an older result, progress update, or error".

## Fix (minimal fence, no concurrency rewrite)

New `ParseRequestFence` (SceneParserService.swift, lock-guarded monotonic epoch):
`begin() -> UInt` invalidates all earlier tokens; `isCurrent(token)` is true only for the latest.
Lock-guarded because parse awaits resume off the caller's executor.

Wired call sites (token at entry, currency re-checked immediately before each context write):

| Call site | Token | Guarded writes |
|---|---|---|
| `parseAsync(_:markedObjects:state:)` (state ≠ nil) | `parseToken` | `lastRuntimeTrace`, `lastChunkState` |
| `parseBundle(...)` | `parseToken` | whole `updateBundleContext` |
| `parseBundleAsync(...)` | `parseToken` | whole `updateBundleContext` |
| `resetRuntimeContext()` | `begin()` (invalidation) | clears all five context fields; in-flight parses can no longer repopulate |

Stale completions still return their result to the caller (the caller's own VM epoch fence
discards it); only the shared-context side effect is suppressed. Stale-path trace uses plain
`print` (release-stripped module-wide) — the shared diagnostics logger's static DateFormatter is
not thread-safe and stale completions may resume off-main (pre-existing logger hazard, M1-020 scope).

## Transition matrix (fence semantics)

| Event sequence | Token state | Published? |
|---|---|---|
| A begins → A completes, no newer request | A current | yes |
| A begins → B begins → A completes late | A stale, B current | A write suppressed |
| A begins → B begins → B completes | B current | B writes |
| A begins → resetRuntimeContext → A completes late | A invalidated | A write suppressed |
| A begins → VM teardown bumps epoch, cancels task → A completes late | A stale (parser) + VM fence discards result | nothing publishes |
| Concurrent `begin()` from many tasks | unique monotonic tokens | only last-issued current |

## Narrow verification

- `shafinMultitoolTests/SceneParseRequestFenceTests.swift` (7 tests): out-of-order completion
  (delayed stale completion loses to newer request), reset invalidation, uniqueness under 64
  concurrent begins, unsuperseded token stays current, and service-level integration: current
  request still publishes context; reset clears context.
- Regression: SceneParserServiceTests, SceneBundlePipelineTests, SceneV8PipelineTests
  (existing parse behavior unchanged under the fence).
