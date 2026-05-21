# Agent Context Router

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

This file is for LLM agents working with the thesis workflow. Its job is to answer one question:

`For this user request, which thesis files should I open first?`

## Core rule

Do not load all of `docs/thesis/` by default.

Start with the smallest packet that matches the task. Expand only if blocked.

## Always-open baseline

For any thesis-related request, first inspect:

1. `docs/thesis/00_thesis_brief.md`
2. `docs/thesis/01_outline.md`
3. `docs/thesis/04_claim_registry.md`
4. `docs/thesis/skills/thesis-workflow/SKILL.md`

If the request mentions litreview or theory, also inspect:

5. `docs/thesis/snapshots/litreview_snapshot.md`
6. `docs/thesis/07_litreview_alignment.md`

## Routing table

| User asks | Open first | Then open if needed | Do not open by default |
|---|---|---|---|
| “О чем писать во 2 главе?” | `00_thesis_brief.md`, `01_outline.md`, `07_litreview_alignment.md`, `snapshots/architecture_snapshot.md`, `chapters/ch3_architecture.md` | `03_evidence_map.md`, `04_claim_registry.md`, `litreview_snapshot.md` | full `litreview.md`, full `diploma.md`, codebase |
| “Напиши раздел главы 2” | `00_thesis_brief.md`, `02_glossary.md`, `snapshots/architecture_snapshot.md`, `03_evidence_map.md`, `04_claim_registry.md`, `chapters/ch3_architecture.md` | targeted code/docs for exact claim IDs | whole thesis folder |
| “О чем писать в 3 главе?” | `00_thesis_brief.md`, `01_outline.md`, `snapshots/implementation_snapshot.md`, `snapshots/model_eval_snapshot.md`, `chapters/ch3_scene_generation.md` | `03_evidence_map.md`, `04_claim_registry.md`, `02_glossary.md` | full litreview |
| “Напиши раздел главы 3” | `02_glossary.md`, `snapshots/implementation_snapshot.md`, `snapshots/model_eval_snapshot.md`, `03_evidence_map.md`, `04_claim_registry.md`, `chapters/ch3_scene_generation.md` | exact Scene Generator code/docs/eval files from snapshots | unrelated Camera Analysis docs |
| “О чем писать в 4 главе?” | `00_thesis_brief.md`, `01_outline.md`, `snapshots/camera_analysis_snapshot.md`, `chapters/ch4_camera_analysis.md` | `03_evidence_map.md`, `04_claim_registry.md`, `02_glossary.md` | full codebase |
| “О чем писать в 5 главе?” | `00_thesis_brief.md`, `01_outline.md`, `snapshots/model_eval_snapshot.md`, `snapshots/camera_analysis_snapshot.md`, `03_evidence_map.md`, `04_claim_registry.md`, `chapters/ch5_experiments.md` | exact benchmark/eval artifact files named in snapshots | whole codebase |
| “Дай точные метрики / таблицу экспериментов” | `snapshots/model_eval_snapshot.md`, `snapshots/camera_analysis_snapshot.md`, `03_evidence_map.md`, `04_claim_registry.md` | exact benchmark/eval artifact files named in snapshots | `diploma.md` unless metric is missing in artifacts |
| “Свяжи litreview с проектом” | `snapshots/litreview_snapshot.md`, `07_litreview_alignment.md`, `00_thesis_brief.md` | `snapshots/architecture_snapshot.md`, `03_evidence_map.md` | editing `litreview.md` |
| “Проверь, не врёт ли глава / черновик” | `04_claim_registry.md`, `03_evidence_map.md`, relevant chapter skeleton, relevant snapshot | exact code/docs/eval artifacts for referenced claims | whole thesis folder |
| “Что обновить после новых изменений в repo?” | `06_dynamic_update_protocol.md`, `03_evidence_map.md`, `04_claim_registry.md`, relevant snapshots | `diploma.md`, changed code/docs/eval files | rewriting full chapters |
| “Собери prompt для ChatGPT” | `05_writing_workflow.md`, `prompts/chatgpt_chapter_writer.md`, `prompts/chatgpt_scientific_editor.md` | relevant chapter skeleton and snapshot | whole repo |

## Source-of-truth escalation order

If the first packet is not enough, expand in this order:

1. relevant chapter skeleton
2. relevant snapshot
3. `03_evidence_map.md`
4. `04_claim_registry.md`
5. exact project docs or eval artifacts referenced by evidence
6. exact code/test files
7. `diploma.md` only for historical context, negative results, or when no machine-readable artifact exists
8. `docs/thesis/litreview.md` only when the request is specifically about theory/litreview wording

## Special rules

### If the task is planning

Prefer:
- brief
- outline
- chapter skeleton
- relevant snapshot

### If the task is writing prose

Prefer:
- glossary
- relevant snapshot
- evidence map
- claim registry
- chapter skeleton

### If the task is verification

Prefer:
- claim registry
- evidence map
- exact source files for the claims being checked

### If the task is litreview-related

Prefer:
- litreview snapshot
- litreview alignment
- protected litreview only if necessary

Never rewrite the litreview unless explicitly requested.

## One-line routing heuristic

If the user asks:

- `what to write` -> open skeleton + snapshot
- `write text` -> open skeleton + snapshot + glossary + claims/evidence
- `verify text` -> open claims/evidence + exact source files
- `update after repo change` -> open dynamic protocol + evidence/claims + changed sources
- `connect theory to practice` -> open litreview snapshot + alignment + target practical snapshot
