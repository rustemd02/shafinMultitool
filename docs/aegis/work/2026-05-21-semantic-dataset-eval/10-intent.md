# Semantic Dataset Eval Intent

Date: 2026-05-21.

## Requested Outcome

Use `docs/cameraanalysis/31-dataset-eval-implementation-plan.md` to check how
the current Camera Analysis system behaves against the 107 labeled images, then
fix the path toward correct semantic/technical hints.

## Goal

Build a reproducible semantic label eval, produce a current baseline report, and
rank the next implementation work by measured failures instead of intuition.

## Goal Refresh 2026-05-22

The eval bridge now exists, so the active goal is stricter than the initial
"make baseline measurable" slice:

```text
По плану docs/cameraanalysis/31-dataset-eval-implementation-plan.md построить
воспроизводимую проверку текущей Camera Analysis системы на размеченных снимках,
зафиксировать фактические ошибки подсказок и исправить логику/калибровку так,
чтобы live/pause semantic tips корректно проходили dataset/eval criteria для
good/mixed/bad кадров с confidence и forbidden-tip контролем.
```

This goal is still active after accepted `R10a`. The latest replay is better
than `R09b`, but it is not yet product-ready because mixed-frame semantics,
object/multi-subject grounding and continued per-action confidence calibration
remain weak. `R10a` only fixed one overconfident mixed corrective export case;
it did not solve semantic grounding.

## Success Evidence

- `semantic_labels_v1.jsonl` validates against images.
- Eval can compare candidate outputs to labels.
- Good-frame preservation, forbidden tips, technical failures and confidence are separate metrics.
- A current baseline report exists and clearly says whether it is real runtime or proxy.
- Remaining app work is ranked from eval failures.
- Latest candidate improves measured failures without hiding regressions in
  good-frame preservation, forbidden-action rate or confidence.
- Remaining failures are turned into bounded implementation slices, not ad hoc
  threshold tuning.

## Stop Condition

- `done`: real runtime baseline exists, tests pass, the current target metrics are
  met or explicitly revised, and remaining work is externalized as follow-up.
- `needs-verification`: implementation exists but tests or reports were not generated.
- `blocked`: real runtime replay requires unavailable simulator/CoreML path.
- `scope-exceeded`: continuing would require implementing full technical IQA/VLM app features in the same slice.

## Non-Goals

- Do not claim proxy metrics as real app performance.
- Do not silently move technical/IQA actions into semantic actions.
- Do not edit protected thesis/litreview material.
- Do not train or download ML models.

## Baseline Read Set

- `docs/cameraanalysis/31-dataset-eval-implementation-plan.md`
- `docs/cameraanalysis/dataset/inbox/semantic_labels_v1.jsonl`
- `docs/cameraanalysis/eval/*`
- `shafinMultitool/Multitool2Module/Models/CameraAnalysis/CameraAnalysisDomainContracts.swift`
- `shafinMultitool/Multitool2Module/Services/Pipeline/AnalysisPipeline.swift`

## Risk Hints

- Still-image replay through actual Swift/CoreML pipeline exists, but depends on a simulator/CoreML path and can still be command-line flaky.
- Proxy baseline is useful for prioritization but insufficient for dissertation performance claims.
- Technical/IQA failures dominate the bad public-image tail.
