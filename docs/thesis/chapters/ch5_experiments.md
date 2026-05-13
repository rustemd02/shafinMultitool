---
chapter: 4_experiments
status: new
target_pages: 10-14
depends_on_claims:
  - CL-MET-001
  - CL-MET-002
  - CL-MET-003
  - CL-MET-004
  - CL-MET-005
  - CL-MET-006
  - CL-MET-007
  - CL-MET-008
  - CL-CA-001
  - CL-CA-002
depends_on_litreview_sections:
  - Методология
  - Заключение
last_verified_commit: 02bdf3ae0b711ed5e0b7a640cbf808196d304b62
---

# Chapter 4. Experiments

## Purpose

Present experimental evidence from frozen benchmark/eval artifacts and clearly separate confirmed metrics, partially verified live smoke evidence and limitations.

## Proposed sections

1. Experimental methodology and source-of-truth artifacts.
2. Scene Generator metrics and evaluation sets.
3. Base/v6/v7/v7_orpo comparison.
4. V8 plan/compile comparison.
5. V9 slot/event table comparison.
6. Live smoke evidence and negative results.
7. Camera Analysis deterministic evaluation.
8. Camera Analysis hybrid smoke and mobile-blocked limitation.
9. Threats to validity.

## Claims and evidence

| Use | IDs |
|---|---|
| SG metrics | EV-MET-001, EV-MET-002, EV-MET-003, EV-MET-004 |
| Live smoke | EV-LIVE-001, EV-LIVE-002 |
| Camera Analysis | EV-CA-EVAL-001, EV-CA-EVAL-002 |
| Limitations | EV-LIM-001, CL-LIM-002 |

## Litreview links

| Litreview fragment | Experiments continuation |
|---|---|
| Mobile performance and quality tradeoff | Compare structured output reliability, fallback rate and strict success across SG versions. |
| Need for explainable recommendations | Use unsupported claim rate and explanation faithfulness in Camera Analysis eval. |
| Methodology section | Do not reuse litreview method as project eval method; introduce separate benchmark methodology. |

## Tables/figures placeholders

| Placeholder | Content |
|---|---|
| Table 4.1 | Scene Generator metric definitions. |
| Table 4.2 | Base/v6/v7/v8/v9 comparison. |
| Table 4.3 | V9 event raw metrics. |
| Table 4.4 | Camera Analysis deterministic comparison. |
| Table 4.5 | Limitations and validity threats. |

## TODO

| TODO | Status |
|---|---|
| Attach final live smoke artifacts before final defense. | todo |
| Decide whether to show percent or decimal consistently. | todo |
| Do not claim hybrid neural uplift until mobile gate passes. | always |
