# Camera Coach assisted visual review and rolling prefetch

## Aegis Visibility

This slice changes the external-media boundary, paid-request scheduling, append-only annotation journal, and the distinction between an AI proposal and a human-confirmed research label.

## Plan basis

- User-approved flow: show each photo/video, let the selected VLM assess it first, accept with the keyboard or replace the assessment with natural-language feedback.
- User amendment: while item N is visible, preprocess N through N+5 in the background so navigation does not wait on the provider.
- Baseline: `tools/camera_annotation/language_review.py`, `language_labels.py`, `language_review.html`, `README_REVIEW.md`; the frozen Camera Coach v2 output vocabulary remains the downstream compatibility boundary.
- M3 independence boundary: assisted proposals are research-only and never become human-gold automatically; the blind annotation flow remains separate.

## Requirement Ready Check

- Goal: rolling visual analysis for photos and video excerpts with keyboard-first confirmation/correction.
- Acceptance: current plus five upcoming records are queued; only one paid request is in flight; exact cache hits are reused; photos and three representative video frames are actually sent; the UI polls and displays ready results without blocking; Enter confirms, E edits, Cmd/Ctrl+Enter translates a correction, Cmd/Ctrl+Shift+Enter confirms it, S skips, B goes back, Space plays/pauses video.
- Boundary: no model choice substitution, no automatic retry after ambiguous billing, no automatic human confirmation, no production-model admission.
- Open blockers: the selected Command Code model may reject image parts; the implementation must surface that provider failure and stop further automatic dispatches.
- Decision: ready.

## Change Necessity

- A static page cannot perform paid background inference or durable deduplication safely.
- The existing loopback server already owns authentication, media integrity, provider calls, and append-only events.
- Minimum change: extend that owner and the existing page; do not introduce another service, database, dependency, or queue daemon.
- Decision: code-change.

## Existence Check

- Reuse Pillow already required by the annotation tooling for in-memory EXIF-aware JPEG derivatives.
- Reuse source-frame IDs already present in `temporal.jsonl` and their rows in the package `manifest.jsonl`; do not add video decoding.
- Reuse the existing HTTP polling endpoint and a single Python worker thread; no WebSocket, job framework, or persistent cache database.
- Decision: reuse-existing.

## TDD Route

- Mode: off
- Decision: skipped
- Strict authority: not applicable
- Strict signals: external API, persistence, concurrency
- Light eligibility: not applicable
- TDD-fit exception: project instructions prohibit adding tests unless explicitly requested.
- Test posture: post-change runnable self-check plus a real one-record provider probe and browser smoke.
- Reason: verify the trust boundary without creating a new test suite.
- Verification: `language_labels.py`; `language_review.py --self-check`; `py_compile`; `git diff --check`; authenticated browser flow.

## Compatibility and data contract

- Existing `camera-human-language-review-v1` rows remain immutable and readable.
- New events use `camera-human-visual-review-v2` and may include `spatial_requests`; the frozen network projection keeps these untrained and lists the missing admission requirement.
- AI events are `human_gold=false`. Only explicit `visual_confirmed` or corrected `confirmed` events record human confirmation, and even those remain research-only until independent adjudication.
- Cache identity includes record ID, source SHA-256, exact model, visual prompt/schema SHA-256, and derivative recipe. A version change invalidates old proposals without deleting them.
- Journal records derivative SHA-256/byte count/recipe, never the API key or base64 pixels.

## Files

- Modify `tools/camera_annotation/language_labels.py`: visual schema/prompt/validation/summary and compatible spatial request projection.
- Modify `tools/camera_annotation/language_review.py`: media derivatives, multimodal request, exact journal cache, one-worker rolling scheduler, prefetch/confirm APIs, self-check.
- Modify `tools/camera_annotation/language_review.html`: automatic proposal state, polling, prefetch window, accept/edit/skip/back/video shortcuts.
- Modify `tools/camera_annotation/README_REVIEW.md`: operator flow, privacy/cost/failure semantics.
- Update existing project/thesis evidence artifacts only where the implementation changes a supported claim; do not touch protected literature review.

## Tasks

1. Add the visual interpretation contract while keeping the frozen model projection fail-closed.
2. Build verified in-memory JPEG parts for a photo or first/middle/last package frames for a video.
3. Add append-only `visual_dispatch`/`visual_proposal`/`visual_error`/`visual_confirmed` events and an exact cache lookup.
4. Add a replaceable rolling queue for at most six allowlisted record IDs and one background worker.
5. Wire `/api/prefetch`, queue status, visual confirmation, and multimodal correction requests.
6. Update the page to request the current-plus-five window, poll status, display the proposal, and support all keyboard paths.
7. Update usage/privacy documentation and durable evidence references.
8. Run the narrow self-checks, one selected-model visual probe, and browser smoke; restart the desktop launcher server without persisting the key.

## Risks and retirement

- The provider does not expose a verified monetary-cost endpoint: the persisted hard request count remains the local guard; stop on any ambiguous paid result.
- The selected model has no ZDR-capable upstream: the UI must disclose that reduced pixels leave the Mac before connection/use.
- One worker is intentionally a throughput ceiling for a single annotator. Replace it only if measured latency still prevents the six-item lookahead from keeping up.
- Source video frames are package-derived and may be up to 0.5 seconds from ideal boundaries; add native exact timestamp extraction only if review evidence shows this harms judgments.
- Retire visual v2 only through an explicit migration after the canonical spatial operation contract is admitted; never silently coerce `spatial_requests` into v2 deltas.

## Execution result

Implemented and verified on 2026-09-15. The selected model accepted image parts; six serial proposals filled the requested rolling window. A real correction mapped `стол → center` with no `unmapped` residue. No proposal was human-confirmed during verification. See the external receipt and `docs/aegis/work/2026-09-15-camera-visual-prefetch-review/90-evidence.md`.
