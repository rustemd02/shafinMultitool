# Production-level goal and acceptance contract

Status: active, supersedes the weaker local-RC `done` boundary in
`docs/aegis/work/2026-08-15-camera-coach-release/10-intent.md`.

Date adopted: 2026-08-15.

## Requested outcome

Autonomously bring the complete Shafin system to a production-level,
submission-ready App Store candidate:

- Camera Coach is the primary product and solves the complete local coaching
  loop without payment or server dependency;
- Scene Mode remains a reliable secondary workflow and preserves existing
  projects;
- Deep Review and monetization ship only with measured product and economic
  evidence, but the final candidate must contain an explicit monetization
  decision and a verified StoreKit path when a paid product is selected;
- UI/UX is intentionally designed, satisfying to use, accessible and free of
  the banned vibe-code patterns in the product baseline;
- release, privacy, provenance, device, benchmark and operational evidence is
  reproducible from a clean checkout.

Public App Store submission, paid infrastructure purchases, account/legal
attestations and public rollout still require explicit owner authority. The
autonomous technical target stops immediately before those external actions,
not before production evidence exists.

## Completion states

Only these whole-goal states are permitted:

- `done`: every mandatory gate in this document is supported by fresh evidence.
- `needs-verification`: implementation exists, but any required benchmark,
  physical-device, beta, privacy, legal, commercial or release evidence is
  missing. This is not completion.
- `blocked`: no remaining safe independent work exists and progress requires an
  unavailable device, credential, paid action, owner decision, external user or
  legal attestation. A blocked item does not permit a narrower `done` claim.
- `scope-exceeded`: the next action is publication, purchase, push/PR, destructive
  migration, irreversible user-data change or another action outside granted
  authority.

Completing a task, milestone, build, benchmark or Luna packet never completes
the whole goal. The orchestrator continues with another independent in-scope
slice until `done` or until every remaining path is genuinely blocked.

## P0/P1 severity contract

- `P0`: data loss, privacy/security breach, unusable primary flow, crash/hang in
  a supported normal flow, false purchase/entitlement, release contamination,
  illegal/unresolved shipped artifact, or advice likely to make capture
  materially worse in a protected/forbidden case.
- `P1`: repeatable failure of a required 1.0 scenario, inaccessible critical
  control, recording/save failure with recovery, contradictory or unstable
  coaching, major orientation/lifecycle defect, or benchmark bucket below its
  mandatory floor.
- `P2`: bounded defect with a safe recovery that does not invalidate a launch
  claim.

`done` requires zero open P0 and zero open P1. P2 items require explicit owner,
impact, workaround and post-launch disposition.

## Gate A — product and scope integrity

1. Camera Coach is the default launch benefit and first-use promise.
2. A free user can complete `understand -> act -> verify` locally, including a
   useful result and honest abstention, without account, server or paywall.
3. Coach is default; Pro Controls can be entered and exited without losing the
   camera session or coaching context.
4. Scene Mode is secondary, does not reappear as the product's first screen and
   does not create a second camera/session owner.
5. Existing saved scenes open without destructive migration or silent loss.
6. Every 1.0 feature traces to the main pain, the coaching loop, reliability,
   privacy, payment or App Store requirements.
7. Deferred features remain absent from promises and metadata.

Evidence: approved state specification, traceability matrix, end-to-end tests,
saved-project compatibility fixtures and final product audit.

## Gate B — functional end-to-end behavior

The following scenarios must pass through production owners, not mocks alone:

1. first launch and camera permission `notDetermined/allowed/denied/restricted`;
2. Camera Coach live -> action -> verification -> live continuation;
3. pause analysis -> explanation -> resume;
4. Coach <-> Pro Controls switching;
5. portrait <-> landscape during preview and recording;
6. background/foreground, interruption and route teardown;
7. recording start/stop/failure, optional audio policy, local finalization,
   Photos authorization/save and deterministic temporary-file cleanup;
8. low storage, memory pressure and thermal degradation;
9. offline, server timeout, malformed response, quota and retry;
10. Scene Mode create/save/reopen/rehearse/record and legacy-scene opening;
11. purchase/pending/cancelled/restore/refund/expiration when monetization ships;
12. accountless reinstall/entitlement behavior under the selected policy.

Evidence: unit/integration/UI tests plus physical-device scripted runs. No P0/P1.

## Gate C — Camera Coach benchmark quality

### C1. Dataset structure

Maintain three disjoint evaluation layers:

1. `regression`: current VCR/curated/public/synthetic cases used during
   development; never reported as an unseen holdout.
2. `locked_holdout`: images and transformations not used for threshold tuning;
   provenance and hashes frozen before the evaluated build.
3. `live_device`: scripted real-camera sequences on physical devices, including
   motion, lighting transitions and user action/verification.

Every record must include source/provenance, rights disposition, content hash,
split, scene/quality tags, expected actions, forbidden actions, confidence
target and review status. Silver/AI-first-pass labels may guide development but
cannot alone close production accuracy. Generated and deterministic synthetic
cases remain separate buckets and cannot hide weak organic performance.

Minimum locked still-image coverage before `done`:

- at least 250 distinct images;
- good/mixed/bad and preserve/correct/abstain represented;
- people, groups, objects, landscape, architecture, food/product, pets,
  low-light, backlight, deliberate cinematic styling and ambiguous scenes;
- blur, clipping, under/overexposure, tilted horizon, edge cutoff, tiny subject,
  clutter, obstruction and background competition;
- a separately reviewed critical forbidden-action set;
- no train/eval or tuning/holdout overlap under exact file hash and derivation
  family.

### C2. Still-image full-runtime gates

The production candidate must use `fullRuntime` output from the actual Swift
pipeline. Proxy, oracle and `lightweightTest` outputs cannot close this gate.

Mandatory locked-holdout thresholds:

- `record_count >= 250`;
- `pass_rate >= 0.90`;
- `expected_action_hit_rate >= 0.90`;
- `forbidden_action_violation_rate <= 0.02`;
- `good_frame_preservation_rate >= 0.95`;
- `technical_failure_gate_rate = 1.00`;
- `confidence_band_accuracy >= 0.90`;
- `demo_priority_pass_rate >= 0.90`;
- every material organic source bucket has `pass_rate >= 0.80`;
- every synthetic/adversarial bucket has `pass_rate >= 0.65`;
- zero critical forbidden-action violations in the reviewed safety set;
- no hard technical fault is suppressed solely by an aesthetic score;
- an unavailable model signal remains unavailable, never fabricated as zero,
  one or a positive confidence.

Threshold changes require a documented evidence-based decision before looking
at final holdout results. Threshold tuning against record IDs, labels or source
buckets is prohibited.

### C3. Live sequence gates

On physical-device guided sequences:

- the first useful or honest-abstention state appears with `p50 <= 3 s` and
  `p95 <= 8 s` after the scene becomes analyzable;
- one user-visible primary action is shown at a time;
- advice does not change more than once within 3 seconds unless a safety/
  technical condition materially changes;
- action completion and verification are independently observed rather than
  inferred from time alone;
- forbidden-action violations are zero in scripted critical sequences;
- no hang, stale-frame advice or post-release callback occurs;
- thermal degradation reduces cadence gracefully and never fabricates quality.

At least 30 guided sequences across the device matrix are required.

## Gate D — Scene Generator and Scene Mode quality

1. The production parser/model artifact has exact source, license,
   redistribution evidence, checksum and reproducible delivery/build recipe.
2. The strict fresh leakage-free benchmark is run with predictions regenerated
   for the production checkpoint; historical contaminated predictions are not
   reused as unseen evidence.
3. Required thresholds on the locked production contract:
   - `json_valid_rate = 1.00`;
   - `schema_valid_rate = 1.00`;
   - `target_resolution_accuracy >= 0.98`;
   - `chronology_phase_accuracy >= 0.98`;
   - `action_recall >= 0.98`;
   - `runtime_fallback_rate <= 0.01`;
   - no silent repair that changes actor/action meaning.
4. At least 30 owner-independent natural-language scene prompts are retained as
   a locked qualitative/live parity set.
5. Chunking/stitching and multi-actor/multi-object continuity are measured,
   not left as null metrics.
6. Saved project migration and scene recording pass on physical devices.

## Gate E — UI/UX and accessibility

1. Every product state has entry, primary action, recovery and exit.
2. No dead end, debug surface, unexplained score or disabled-looking active
   control ships.
3. Portrait and landscape are intentionally designed, not mechanically scaled.
4. VoiceOver labels/order, Dynamic Type, contrast, Reduce Motion, Reduce
   Transparency, hit targets and permission copy pass automated and manual QA.
5. Golden screenshots cover all critical states on compact and large devices;
   visual diffs are reviewed intentionally.
6. Banned vibe-code patterns from the product plan are absent.
7. In external beta, at least 85% of relevant participants complete the first
   coaching loop without intervention; no repeated critical confusion remains.

## Gate F — reliability, performance and device coverage

Required physical matrix:

- oldest supported iPhone/SoC;
- one representative mid-tier supported device;
- one current high-tier device;
- supported iOS minimum and current public iOS where hardware permits.

Required evidence:

- clean install, upgrade, repeated launch and background/foreground soak;
- 30-minute camera/analysis soak per device/orientation;
- 10 repeated recording/save cycles per device;
- bounded memory with no monotonic leak/OOM;
- thermal-state transition evidence;
- no crash/hang in scripted acceptance runs;
- external beta contains at least 200 meaningful sessions and reports
  `crash_free_sessions >= 0.995` before public go/no-go.

Performance budgets that depend on hardware are stored per device and measured
on the same build. Missing budgets or measurements mean `needs-verification`.

## Gate G — tests and reproducibility

1. Focused tests pass after each slice.
2. Full unit/integration/UI suite passes on a clean checkout.
3. The canonical Debug/Release, privacy, provenance, safety and contamination
   release gates pass from clean HEAD with deterministic output roots.
4. A true UI-test target runs the critical launch/permission/orientation/
   Camera Coach/Scene Mode scenarios in a separate process.
5. Release Archive and Apple Validate pass with the intended entitlements,
   manifests and bundle allowlist.
6. No test may pass only by skipping the production owner it claims to verify.
7. Flaky tests are defects; retries may diagnose but cannot define acceptance.

## Gate H — privacy, security, provenance and legal readiness

1. Every shipped model, binary, image, font, media and SDK is `verified`,
   `replaced` or `excluded`; no unknown allowlist entry remains.
2. License and NOTICE obligations are present in app acknowledgements and the
   release evidence packet.
3. Privacy manifest, App Privacy answers, privacy policy, usage descriptions,
   retention/deletion rules and processor/region decisions match runtime.
4. Camera/video/image data is not uploaded by default without explicit user
   action and disclosure.
5. Server auth, rate limiting, request validation, secret handling, abuse and
   budget caps pass negative tests.
6. Logs/analytics contain no raw frames, voice, unrestricted text or stable
   fingerprinting identifiers unless separately justified and disclosed.
7. Dependency and secret scans have no unresolved high/critical finding.

Engineering provenance evidence is not legal advice. Any required legal owner
attestation remains an external completion dependency.

## Gate I — Deep Review, server and economics

If Deep Review is part of 1.0:

- on the locked hard-case comparison set it improves successful/helpful results
  over the local baseline by at least 10 percentage points and is preferred in
  blinded pairwise review at least 60% of the time;
- `success_rate >= 0.98`, `p95 latency <= 15 s` and malformed-response rate is
  zero after client schema validation;
- retries are bounded and idempotent; outage leaves local Coach fully usable;
- provider region, retention and deletion are documented and tested;
- per-review cost is measured, capped and fits the selected price after Apple
  commission, taxes and allowance usage;
- a kill switch disables Deep Review without disabling local Coach.

If these conditions fail, Deep Review is removed from 1.0 promises and paid
scope rather than hidden behind optimistic copy.

## Gate J — monetization

1. Beta evidence selects subscription, credits, one-time paid capability or an
   explicit delayed-monetization release; the decision and falsifiers are
   recorded.
2. A paid choice requires StoreKit 2 products and server entitlement/quota
   behavior to match exactly.
3. Purchase, pending, cancellation, restore, refund/revocation, billing retry,
   expiration/consumption, reinstall and offline cache states pass end-to-end.
4. The free local coaching loop, both camera UI levels and user-created media
   remain accessible without payment.
5. Paywall appears only in context after demonstrated local value and meets
   accessibility/localization requirements.
6. Unit economics include Apple commission, provider cost, free allowance,
   refund/fraud/error margin and a hard monthly budget cap.

Delayed monetization is a valid product decision only if explicitly accepted;
it does not silently satisfy the original monetization objective.

## Gate K — external beta and product evidence

Before a public release recommendation:

- at least 15–20 relevant external users participate;
- at least 200 meaningful sessions are observed;
- at least 85% complete the first coaching loop without intervention;
- helpfulness, abstention, repeated use, trust failures and Deep Review demand
  are measured under the event contract;
- no open P0/P1 remains from feedback;
- App Store promise and monetization decision are reconciled with beta evidence.

Desk research, AI review and simulator replay cannot substitute for this gate.

## Gate L — App Store submission readiness

1. Clean Release Archive and Apple Validate pass.
2. Bundle ID, signing, entitlements, versions and export-compliance answers are
   final.
3. Privacy policy, Support URL, age rating and App Privacy are ready.
4. Localized title/subtitle/description/keywords, screenshots and optional
   preview reflect only proven behavior.
5. Review notes and demo instructions reproduce camera, microphone, Photos,
   server and purchase paths.
6. Deep Review has rollback/kill-switch and cost monitoring.
7. Support, incident, data-deletion and phased-rollout procedures exist.
8. Final independent review finds no P0/P1, false readiness claim or missing
   acceptance evidence.

Actual TestFlight/App Store upload, submission and public rollout require a
separate explicit owner authorization.

## Overnight execution policy

While the owner is unavailable:

1. Continue with safe local implementation, test, benchmark, documentation and
   non-paid dataset work.
2. Prefer existing VCR/thesis benchmark images first.
3. New evaluation images must be self-created, generated, public-domain or
   permissively licensed, with source/rights/hash recorded.
4. Keep regression and locked holdout splits separate before tuning.
5. Never weaken a threshold merely to make a run green.
6. Preserve negative results and classify the cause before changing code.
7. Do not perform paid API calls, publication, push/PR, destructive migration,
   credential changes or legal attestations.
8. If one slice blocks, checkpoint it and continue another independent slice.
9. Stop globally only when all remaining work requires an unavailable external
   dependency or when every mandatory gate is proved.

## Current known acceptance blockers

This list is not exhaustive and must be updated by the active tracker:

- external beta and human usability evidence;
- physical-device matrix;
- Apple Developer signing/Validate credentials and submission authority;
- final asset/model rights and legal attestations;
- server provider/region/retention and paid budget decisions;
- final monetization decision;
- current NIMA provenance/replacement and DETR runtime-contract hardening;
- locked production Camera Coach holdout and live-sequence results;
- fresh leakage-free Scene Generator production rerun;
- real UI-test target and final production shell/UI implementation.
