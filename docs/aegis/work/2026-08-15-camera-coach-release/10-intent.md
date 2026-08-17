# Camera Coach release intent

## Requested outcome

Запустить автономный pipeline main-chat Sol-оркестратор → отдельные user-visible Codex threads GPT-5.6 Luna / Max и довести всю систему до production-level, submission-ready App Store candidate по `docs/implementation/PRODUCTION_ACCEPTANCE.md`.

## Durable orchestration policy amendment

The active system goal text is immutable through the goal API while it is active. This file and `20-checkpoint.md` are the durable goal-policy amendment for the orchestration boundary.

- Every new executor, reviewer, correction-loop or verification worker for this project MUST be created as a separate USER-VISIBLE Codex chat/thread, never as a hidden collaboration subagent.
- When continuing the current checkout, create that thread in the project-local environment (`environment.type=local`) with explicit `model=gpt-5.6-luna` and `thinking=max`. Hidden collaboration spawning is forbidden.
- The main chat is the sole Sol orchestrator.
- Visible Luna / Max threads own all implementation, testing, correction loops, task-level independent review and verification.
- The parent/main-chat Sol may own architecture, low-level task contracts, the tracker and one bounded risk-based milestone acceptance only. It may create/manage visible Luna / Max threads, but MUST NOT create hidden workers or any Sol, Terra or inherited-model worker thread.
- If a visible Luna / Max thread cannot be created, fail closed. Never silently use a hidden task/subagent or substitute another model.
- Existing mentions of past Sol reviews or verification in checkpoint, status and backlog evidence are historical evidence only; they are not current routing permission and must not be rewritten as if they were current policy.

## Core-first delivery mode (owner directive, 17 August 2026)

The purpose of this mode is to ship a useful Camera Coach, not to optimize
isolated release-hardening artifacts before the product loop works.

- Prioritize the complete local coaching loop over onboarding polish, shell
  chrome, screenshot-perfect evidence, tracker maintenance or speculative
  architecture: allowed camera → useful live advice → user action → honest
  verification/result; then pause/resume and record/finalize/save recovery.
- A Luna task must be one vertical product slice with an explicit user-visible
  outcome, narrow ownership and a bounded test set. Do not create a large plan
  or a long task tree for a secondary screen when a core-loop state is still
  missing or unproven.
- Every slice gets one implementation pass and at most one evidence-driven
  correction loop. A second issue is a new backlog item unless it blocks the
  same user journey with P0/P1 severity. Never turn visual polish into an
  open-ended shell/lifecycle refactor during the same slice.
- Sol does not poll, narrate or intervene on each intermediate compiler/test
  event. It provides the contract, waits for the bounded worker result, then
  performs one factual acceptance review of the final diff and evidence.
- UI must remain free of AI-slop/VibeCode patterns, but visual review happens
  once at the slice boundary. It may reject a shipped screen, not delay core
  implementation through iterative aesthetic micro-tuning.
- Tests are proportional evidence, not the product objective. A green narrow
  suite cannot justify expanding a secondary task; a failed core journey takes
  priority over a cosmetic or host-capture issue.
- New docs are written only for a genuine new owner, contract, compatibility,
  privacy, persistence or release boundary. Routine task narration and
  duplicated tracker prose are forbidden.

## Goal and stop condition

- `done`: все обязательные gates из `docs/implementation/PRODUCTION_ACCEPTANCE.md` подтверждены fresh evidence; task/milestone/build completion недостаточны.
- `blocked`: вся доступная безопасная независимая работа исчерпана, а продолжение требует отсутствующей внешней зависимости, полномочия, устройства, пользователя или решения владельца.
- `needs-verification`: реализация существует, но benchmark/device/beta/privacy/legal/commercial/release evidence недостаточно; это не завершение цели.
- `scope-exceeded`: продолжение требует push/PR, расходов, публикации, юридического решения, необратимой миграции или изменения утверждённого product scope.
- `orchestration-stop`: если отдельный user-visible thread GPT-5.6 Luna / Max нельзя создать, работа останавливается в fail-closed состоянии; Sol не использует скрытый task/subagent и не подменяет его другой моделью или native role.

## Scope and non-goals

Scope: production-level whole system; Camera Coach first, Scene Mode secondary, free complete local loop, evidence-gated Deep Review and monetization, full benchmark/device/privacy/release proof. Не-цели: универсальный AI director, курсы, social, mandatory account, StoreKit до beta evidence, скрытая публикация или расходы.

## Baseline read set

- `docs/app-store-product-plan.md`
- `docs/implementation/STATUS.md`
- `docs/implementation/BACKLOG.md`
- `docs/implementation/orchestration-setup.md`
- `docs/implementation/PRODUCTION_ACCEPTANCE.md`
- релевантные technical source-of-truth документы только по конкретному slice

## Impact and risk

Работа затрагивает release bundle, app entry, Camera/AR lifecycle, UX, privacy, server boundary и позднее StoreKit. Persistent Scene Mode data защищены. Worker reports не считаются приёмкой.
