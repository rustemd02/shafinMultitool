# Camera Coach backlog — wave M0

Волна создаёт проверяемую производственную базу. Она не реализует StoreKit, backend или массовый UI-рефакторинг до закрытия соответствующих evidence gates.

## CC-000 — синхронизировать Product и Deep Research

- Lane: Sol.
- State: `accepted`.
- Ownership: `docs/app-store-product-plan.md`, orchestration/tracker docs.
- Result: beachhead narrowed; local core free; public paid model deferred; subscription/credits conditioned on beta; Scene Mode secondary.
- Acceptance: current sections do not require subscription, paid history or paid Scene Mode before evidence.

## CC-001 — Release bundle inventory

- Lane: Luna / Max.
- State: `ready`.
- Dependencies: bootstrap commit.
- Ownership: create only `docs/implementation/audits/release-bundle-inventory.md`.
- Read: `project.pbxproj`, build phases, asset catalogs, model/resource references, current built app under a fresh worker-derived directory.
- Must report: every file/class over 1 МБ; source path; reason it enters bundle; Debug/Release necessity; license/provenance state; keep/exclude/on-demand/download candidate; exact owning build setting or project reference.
- Must not edit: Xcode project, source, resources or product plan.
- Verification: clean generic Release build with signing disabled if buildable; `du`/bundle inventory commands; `git diff --check`.
- Acceptance: report explains the 1,0 ГБ GGUF, benchmark packs and all material bundle contributors and provides an exact implementation sequence without deleting files.

## CC-002 — Exclude research assets from Release

- Lane: Luna / Max.
- State: `draft` until CC-001 accepted.
- Ownership: exact project/resource files named by accepted CC-001; focused regression tests if needed.
- Objective: Release contains only explicitly allowed production resources while DEBUG/device benchmark flows remain reproducible.
- Constraints: no deletion of datasets or models; no loss of test/eval evidence; no change to product behavior beyond resource availability by configuration.
- Verification: Debug build-for-testing; Release build/archive-equivalent; bundle inventory asserts forbidden assets absent and required assets present.
- Acceptance: Release bundle size reduction is measured, resource access fails explicitly outside supported configurations, tests pass.

## CC-003 — Privacy and permissions inventory

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/privacy-permissions-inventory.md`.
- Read: usage descriptions, camera/microphone/Speech/Photos call sites, telemetry/offloading code, dependencies and App Store privacy requirements already cited in product docs.
- Must report per permission/data type: trigger, purpose, timing, allowed/denied/restricted behavior, stored/transmitted fields, current user-facing copy, missing tests, privacy manifest/API-reason impact, and exact production owner candidate.
- Must not invent processor, region, retention or legal claims.
- Verification: exhaustive `rg` call-site queries recorded; plist validation; `git diff --check`.
- Acceptance: every permission and external-data path has a disposition and executable follow-up; unknowns are explicit.
- Evidence: `docs/implementation/audits/privacy-permissions-inventory.md`; accepted after path-only diff, plist validation and parent negative/call-site checks.

## CC-004 — Dependency, model and media provenance inventory

- Lane: Luna / Max.
- State: `in_progress`.
- Ownership: create only `docs/implementation/audits/dependency-provenance-inventory.md`.
- Read: `Podfile`, `Podfile.lock`, vendored frameworks/packages, Core ML packages, GGUF, images, USDZ/Reality Composer assets and acknowledgements.
- Must report: component, version/hash where observable, runtime role, source, license evidence path, redistribution status, privacy/network behavior, bundle impact and disposition `verified / missing / replace / exclude`.
- Must not assert a license from filename or memory.
- Verification: filesystem/hash/package metadata commands and `git diff --check`.
- Acceptance: every shipped third-party binary/model/media family is covered; missing provenance becomes a blocking follow-up rather than guessed approval.

## CC-005 — Test topology and UI-test target plan

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/test-topology.md`.
- Read: Xcode targets/schemes, all test files, test host settings, benchmark/UI-labelled tests and existing test documentation.
- Must report: which tests compile/run under which target; UI tests incorrectly living in unit target; conditional skips/false-green risks; simulator/device requirements; exact new UI-test target/file membership/scheme plan; minimal CI matrix.
- Verification: `xcodebuild -list`; build-for-testing; targeted dry enumeration where supported; `git diff --check`.
- Acceptance: report provides a mechanical implementation packet for a true UI-test target and separates unit, integration, benchmark and device-only gates.
- Evidence: `docs/implementation/audits/test-topology.md`; accepted after path-only diff, generic iOS test build and parent workspace enumeration.

## CC-006 — Runtime entry and legacy route audit

- Lane: Luna / Max.
- State: `accepted`.
- Ownership: create only `docs/implementation/audits/runtime-entry-routing.md`.
- Read: `AppDelegate`, `SceneDelegate`, `SOModuleBuilder`, scene overview/stage selection, `ContentView`, camera shell entry points and benchmark environment route.
- Must report: launch graph, navigation owners, orientation assumptions, camera owners created per route, persistent-state dependencies, candidate commercial shell seam, routes safe to retire later and required negative tests.
- Must not change navigation or delete legacy code.
- Verification: call graph searches, compile baseline reference and `git diff --check`.
- Acceptance: one lowest-risk seam for Camera Coach default entry is recommended with explicit compatibility and retirement boundaries.
- Evidence: `docs/implementation/audits/runtime-entry-routing.md`; accepted after `git diff --check`, source-citation spot checks and generic iOS `build-for-testing` (`** TEST BUILD SUCCEEDED **`).

## CC-007 — Commercial shell and Camera Coach default route

- Lane: Luna / Max after Sol architecture packet.
- State: `draft`.
- Dependencies: CC-006 and CC-008.
- Ownership: exact shell/entry files selected after audit; no camera/session internals.
- Objective: app opens Camera Coach by default and exposes secondary Scene Mode without duplicating camera ownership.
- Verification: unit/navigation tests, true UI smoke when target exists, portrait/landscape launch checks and Scene Mode saved-project access.
- Acceptance: no scene-first onboarding, no dead end, no regression in opening existing scenes, no vibe-code navigation patterns.

## CC-008 — UI/UX state specification

- Lane: Sol owns decisions; bounded Luna tasks may produce artifacts after specification.
- State: `proposed_for_owner_acceptance`.
- Ownership: `docs/implementation/ux/**` only until implementation packets are approved.
- Must specify: onboarding, permissions, live Coach, one-tip lifecycle, tap-to-clarify, action detected, before/after verification, keep-as-is, abstention, pause summary, recording, offline, thermal, server consent/timeout/quota, History if retained, Scene Mode entry and both orientations.
- Visual constraints: native hierarchy, semantic system materials/colors, restrained motion/haptics, no dashboard-card grid, gradient-everything, fake AI glow, oversized marketing hero inside tools, decorative glass stacks or arbitrary pill overload.
- Acceptance: every state has entry/exit, primary action, recovery, accessibility, analytics event and screenshot acceptance criteria; no open decision is delegated to Luna.

## CC-009 — Camera/session owner and lifecycle audit

- Lane: Luna / Max audit; implementation may route to Terra / High.
- State: `in_progress`.
- Ownership: create only `docs/implementation/audits/camera-session-ownership.md`.
- Read: `CameraManager`, `CameraViewModel`, recording service, AR camera shell/container, overlays and app lifecycle/orientation hooks.
- Must report: session creation/destruction, queues/actors, frame consumers, record/save owner, background/foreground behavior, rotation path, permission assumptions, thermal/memory controls, duplicated ownership and concurrency risks.
- Verification: call-site graph with exact paths/symbols, current build evidence and `git diff --check`.
- Acceptance: identifies canonical owner candidate and separates mechanical fixes from high-complexity migration work.

## CC-010 — Camera foundation migration

- Lane: Terra / High only if CC-009 confirms concurrency or wide-blast-radius complexity; otherwise decompose for Luna.
- State: `draft`.
- Dependencies: CC-009, CC-007 interfaces.
- Objective: one camera/session owner with reliable lifecycle, recording, rotation and resource cleanup.
- Boundary: saved Scene Mode data remains compatible; no StoreKit/backend/UI redesign.
- Verification: focused unit/integration tests, simulator lifecycle tests and required physical-device smoke matrix.

## CC-011 — Reproducible release gates

- Lane: Luna / Max.
- State: `draft`.
- Dependencies: CC-001, CC-005.
- Objective: documented local commands and CI-ready scripts for Debug test build, focused unit suites, Release build, bundle allowlist, privacy manifest and true UI smoke.
- Ownership: new scripts/config/docs selected after audits; no product behavior.
- Acceptance: a clean checkout can run gates with deterministic pass/fail and without relying on generated files in the developer's home directory.

## CC-012 — Coaching-loop analytics contract

- Lane: Sol defines semantics, Luna / Max implements after UX spec.
- State: `draft`.
- Dependencies: CC-008, privacy boundary from CC-003.
- Required events: first verified helpful loop, tip shown/stable/rejected, subject clarification, action detected, verification result, keep-as-is, abstention, record success/failure, Deep Review consent/request/lift/exhaustion, server latency/error/cost and crash/thermal signals.
- Constraints: no raw media or hidden identifier by default; event properties must not claim causality the client cannot observe.
- Acceptance: schema is versioned, testable, privacy-mapped and sufficient for subscription-versus-credits decision after beta.
