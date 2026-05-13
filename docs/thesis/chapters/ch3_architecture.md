---
chapter: 2_architecture
status: new
target_pages: 9-11
depends_on_claims:
  - CL-BR-001
  - CL-BR-002
  - CL-BR-003
  - CL-ARCH-001
  - CL-ARCH-002
  - CL-DES-001
  - CL-DES-002
depends_on_litreview_sections:
  - Этап предварительного производства
  - Этап съёмки
  - Заключение
last_verified_commit: 02bdf3ae0b711ed5e0b7a640cbf808196d304b62
---

# Chapter 2. Architecture

## Purpose

Describe the system architecture that bridges the litreview gap with the implemented mobile prototype: Scene Generator for previsualization and Camera Analysis for explainable shooting assistance.

## Proposed sections

Introductory architecture block without a numbered subsection:
- practical gap derived from the litreview and the role of the prototype;
- overall system scheme and data flow between the two modules;
- boundary between deterministic logic, ML/LLM components and iOS runtime.

2.1. Architecture of the structured scene generation module.
2.2. Architecture of the frame analysis and recommendation module.

## Claims and evidence

| Use | IDs |
|---|---|
| Bridge from litreview | CL-BR-001, CL-BR-002, CL-BR-003 |
| Architecture | CL-ARCH-001, CL-ARCH-002 |
| Evidence | EV-ARCH-001, EV-SG7-001, EV-SG8-001, EV-SG9-001, EV-BUNDLE-001, EV-CA-001, EV-CA-002 |

## Litreview links

| Litreview fragment | Architecture continuation |
|---|---|
| AR/previsualization and mobile constraints | Scene Generator with structured contracts and deterministic compile. |
| Explainable recommendations gap | Camera Analysis evidence-linked critique. |
| Integrated mobile solution gap | Prototype covers preproduction + shooting, montage remains limitation. |

## Tables/figures placeholders

| Placeholder | Content |
|---|---|
| Figure 2.1 | Overall system architecture Mermaid from `architecture_snapshot.md`. |
| Figure 2.2 | Scene Generator runtime flow. |
| Figure 2.3 | Camera Analysis live/pause flow. |
| Table 2.1 | Deterministic vs ML responsibilities. |
| Table 2.2 | Contracts and source files. |

## TODO

| TODO | Status |
|---|---|
| Draft BR-001 before writing full chapter. | todo |
| Add exact citations to litreview sections after final numbering. | todo |
| Ensure claims use IDs inline in draft. | todo |
