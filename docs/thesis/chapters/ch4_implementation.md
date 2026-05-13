---
chapter: 3_implementation
status: new
target_pages: 14-18
depends_on_claims:
  - CL-IMPL-001
  - CL-IMPL-002
  - CL-DES-001
  - CL-DES-002
  - CL-CA-001
depends_on_litreview_sections:
  - Этап предварительного производства
  - Этап съёмки
last_verified_commit: 02bdf3ae0b711ed5e0b7a640cbf808196d304b62
---

# Chapter 3. Implementation

## Purpose

Describe the concrete implementation of Scene Generator and Camera Analysis without changing production code and without inventing behavior beyond code/docs/tests.

## Proposed sections

1. Scene data contracts: `SceneScript`, `ScenePlanIR`, V9 event table, bundle contracts.
2. Scene Generator runtime implementation.
3. Local LLM integration and GBNF-constrained output.
4. SG v7 offline pipeline implementation.
5. SG v8 plan/compile implementation.
6. SG v9 event/verifier/compiler implementation.
7. Chunk-native bundle pipeline.
8. Camera Analysis implementation: snapshots, semantics, critique, recommendations.
9. Neural evidence wrapper and hybrid fusion boundary.
10. Test coverage map.

## Claims and evidence

| Use | IDs |
|---|---|
| Scene Generator implementation | EV-IMPL-001, EV-LLM-001, EV-GBNF-001, EV-BEAT-001, EV-BUNDLE-001 |
| Data pipelines | EV-SG7-002, EV-SG8-002, EV-SG9-002 |
| Camera Analysis | EV-CA-001, EV-CA-002, EV-CA-003 |
| Tests | `implementation_snapshot.md` test table |

## Litreview links

| Litreview fragment | Implementation continuation |
|---|---|
| Need for mobile previsualization | Scene Generator turns text/script chunks into structured scene contracts. |
| Need for explainable shooting advice | Camera Analysis emits critique reports with evidence refs. |
| Mobile compute constraints | Local inference is bounded by deterministic contracts and fallback/policy gates. |

## Tables/figures placeholders

| Placeholder | Content |
|---|---|
| Table 3.1 | Swift modules and responsibilities. |
| Table 3.2 | Python/data/eval modules and responsibilities. |
| Figure 3.1 | V9 event table verification/compile pipeline. |
| Figure 3.2 | Camera Analysis contract pipeline. |

## TODO

| TODO | Status |
|---|---|
| Add line-level references if final chapter requires code citations. | todo |
| Use exact code-level names `ExplainabilityTraceItem` and `ExplainabilityTraceBundle` when chapter cites concrete Camera Analysis types. | noted |
| Keep code changes out of thesis work unless explicitly requested. | always |
