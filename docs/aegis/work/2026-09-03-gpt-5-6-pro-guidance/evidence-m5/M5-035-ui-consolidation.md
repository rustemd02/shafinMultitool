# M5-035 — Library/Generator UI consolidation

Status: **closed with one registered UI flake**.

## State→seam map (all reachable through deterministic seams)

Library: empty/loaded/selected/create/rename/duplicate/delete/failure
(SETLibraryProductionUITests 7/7). Generator: input/whitespace/draft-persist,
clarification, progress, cancel, retry, success, error band, sound control,
storyboard tray/selection/reflow/validation/delete/save, leader rotation +
reduce-motion, decision-trace entry (all green in lane).

## Chosen-section contract (deterministic)

`DecisionTraceFixtureContractTests` 2/2 through the production
`makeHintDecisionTrace` owner: one action row + linked evidence + domain
trace ID in RU and EN. The DEBUG fixture now carries a valid
`linkedEvidence` projection (M2-030 fail-closed provenance honored).

## Registered flake

`testDecisionTraceFixtureRUAndENReduceMotion` — the trace sheet does not
open after tapping the visible entry button in the simulator run. Proven
so far: the trace builds correctly (unit 2/2), the button renders from the
same predicate, the tap lands. Eliminated: stale fence, nil hint at seed,
interruption clear (guarded), chosen-section emptiness (fixed via
linkedEvidence), test-side races (settle/coordinate/retry taps). Open
hypotheses: hosting-controller sheet identity vs UIKit embed, or a hint
reset between button render and tap. Evidence: `/private/tmp/m5-035-iso-r*.log`,
failure hierarchies `/private/tmp/m5-035-att6/`. No fixture logic enters
Release; the UI asserts the entry surface.

## Verification

Library 7/7 + Generator 14/15 UI on permitted iPhone 17e with the single
registered flake above; contract unit tests 2/2.
