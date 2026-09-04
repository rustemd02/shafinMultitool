# SET OS v2.3 + Phase 0 revision — intent

## Requested outcome

Сохранить принятые behavior/architecture decisions v2.1, опубликовать owner
visual corrections O-5/O-6 как SET OS Visual Policy v2.3 и переработать Phase 0
DesignSystem gallery для отдельного owner approval.

## Scope

- v2.3 changelog, precedence, state, micro-motif, marker semantics, montage
  reflow, font provenance и copy tables;
- Camera Coach approval-направление: `ink / warmWhite / setOrange`, короткая
  команда и action-linked пометка «маркером на стекле»;
- плоские цифровые non-live surfaces; плёнка/перфорация только как детали;
- approved mobile Scene direction A/C/D; из B — только transition impact;
- только O-1 superseded visual assertions;
- tokens, fonts, String Catalog, deterministic fixtures, gallery;
- focused tests, build и simulator evidence.

## Non-goals

- production-screen integration до approval;
- бумажные столы, ticket CTA, tape/clip/pencil props, literal stamp/slate и
  material skeuomorphism;
- route/teardown/accessibility-ID changes;
- History, DebugOverlay, PerformanceOverlay, app icon, thesis litreview.

## BaselineReadSetHint

- `docs/implementation/ux/set-os-visual-policy.md` v2.3;
- `docs/implementation/ux/set-os-policy-critique.md`, owner table + O-1…O-6;
- `docs/implementation/ux/camera-coach-state-spec.md`;
- `docs/aegis/plans/2026-08-17-camera-coach-fullscreen-navigation.md`;
- current shell/presentation source and tests.

## BaselineUsageDraft

- Required refs: all refs above.
- Acknowledged before planning: yes.
- Cited in plan: `docs/aegis/plans/2026-08-17-set-os-v2-1-phase-0.md`.
- Missing: none.
- Decision: continue.

## ImpactStatementDraft

The slice adds a shared visual system and DEBUG fixture surface, but deliberately does not move product state ownership. The temporary icon-only shell implementation is retained until the gallery gate; its rejected presentation is no longer treated as canonical acceptance.

## Stop condition

Stop after v2.3 is published, the revised Phase 0 gallery is freshly
built/tested/visually inspected and owner approval is requested. The v2.1
gallery verdict is `revise`; do not start Phase 1 without a new explicit
approval.
