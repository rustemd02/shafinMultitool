# Writing Workflow

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

## Core rules

1. `docs/thesis/litreview.md` is protected and is not rewritten automatically.
2. Before writing practical chapters, update `03_evidence_map.md`, `04_claim_registry.md` and relevant snapshots.
3. A technical paragraph must cite claim IDs and evidence IDs.
4. A litreview claim must stay `litreview_claim` unless a separate bibliography check verifies it.
5. If source is missing, mark `needs_source`; do not invent.

## Recommended order

| Step | Output | Tool/persona |
|---|---|---|
| 1 | Bridge sections between litreview and project. | Codex for evidence, ChatGPT for prose. |
| 2 | Chapter 3 architecture. | Codex verifies architecture, ChatGPT writes coherent academic text. |
| 3 | Chapter 4 implementation. | Codex maps files/tests, ChatGPT drafts sections from packets. |
| 4 | Chapter 5 experiments. | Codex extracts exact metrics, ChatGPT writes interpretation. |
| 5 | Chapter 6 conclusion. | ChatGPT summarizes only verified claims; Codex checks no new claims. |
| 6 | Scientific editing. | ChatGPT/Canvas edits style without changing claim IDs or technical meaning. |

## Context packet pattern

Do not paste the whole repository or whole litreview. Use packets:

| Packet | Include |
|---|---|
| Theory bridge packet | `litreview_snapshot.md`, `07_litreview_alignment.md`, relevant litreview section only. |
| Architecture packet | `00_thesis_brief.md`, `01_outline.md`, `architecture_snapshot.md`, relevant evidence/claims. |
| Implementation packet | `implementation_snapshot.md`, selected code snippets, relevant tests, evidence/claims. |
| Experiments packet | `model_eval_snapshot.md`, `camera_analysis_snapshot.md`, exact benchmark/eval files, claim IDs. |
| Editing packet | Draft chapter, `02_glossary.md`, `04_claim_registry.md`, style constraints. |

## Codex responsibilities

| Responsibility | Rule |
|---|---|
| Evidence extraction | Read repo files, docs, tests, benchmark artifacts. |
| Claim verification | Mark statuses honestly: verified, partially_verified, needs_source, obsolete, conflicts. |
| Dynamic updates | Compare changes to last verified commit and update affected artifacts. |
| Protection | Do not edit litreview or production app code during thesis tasks unless explicitly requested. |

## ChatGPT/Canvas responsibilities

| Responsibility | Rule |
|---|---|
| Academic prose | Turn verified evidence into coherent Russian academic text. |
| Editing | Improve transitions, remove conversational phrasing, preserve claim IDs. |
| No fabrication | If a fact is not in packet, ask for source or mark as TODO. |

## Chapter writing loop

1. Select one chapter skeleton from `docs/thesis/chapters/`.
2. Pull only its listed claims/evidence and snapshots.
3. Ask Codex to verify the claim subset.
4. Ask ChatGPT to draft one section, not the whole thesis.
5. Ask Codex to run `codex_claim_verifier` prompt on the draft.
6. Update claim statuses and `last_verified_commit` if needed.
