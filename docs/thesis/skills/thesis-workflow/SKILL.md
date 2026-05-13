---
name: thesis-workflow
description: Use this skill when working on dissertation/thesis materials, evidence maps, claim verification, chapter scaffolding, literature-review alignment, or thesis updates after repository changes.
---

# Thesis Workflow

## Source of truth

Use these files in priority order:

1. `docs/thesis/litreview*` - protected existing theory/literature review.
2. `diploma.md` - chronological project development log.
3. `docs/SGv7pipeline/**`, `docs/SGv8pipeline/**`, `docs/SGv9pipeline/**` - Scene Generator data/training/eval pipelines.
4. `docs/cameraanalysis/**` - Camera Analysis design and eval.
5. `experiments/sc_benchmark/**` - benchmark artifacts.
6. `shafinMultitool/SceneGeneratorModule/**`, `shafinMultitool/Multitool2Module/**`, `shafinMultitoolTests/**` - implementation and behavior.

## Automatic context routing

Before reading large amounts of thesis material, open:

1. `docs/thesis/08_agent_context_router.md`
2. the smallest task-matched packet from its routing table

Do not load the whole `docs/thesis/` directory by default.

Use these defaults:

- If the user asks `о чем писать` - open the chapter skeleton and matching snapshot first.
- If the user asks `напиши раздел` - open skeleton + snapshot + glossary + evidence map + claim registry.
- If the user asks `проверь текст` - open claim registry + evidence map + exact source files for referenced claims.
- If the user asks `свяжи litreview с практикой` - open litreview snapshot + litreview alignment + target practical snapshot.
- If the user asks `обнови thesis после изменений` - open dynamic update protocol + evidence map + claim registry + changed source files.

## Protected litreview policy

- Do not edit `docs/thesis/litreview*` unless the user explicitly asks.
- Treat litreview claims as `litreview_claim`.
- Do not verify litreview bibliography through project code.
- Write alignment suggestions in `docs/thesis/07_litreview_alignment.md` or separate notes.

## Evidence-first writing

Before writing practical chapters:

1. Update `docs/thesis/03_evidence_map.md`.
2. Update `docs/thesis/04_claim_registry.md`.
3. Update relevant snapshots.
4. Only then draft chapter text.

Every technical claim needs a code/docs/test/benchmark/log source. If no source exists, mark `needs_source`.

## Claim registry rules

Allowed statuses:
- `verified`
- `partially_verified`
- `needs_source`
- `obsolete`
- `conflicts_with_current_code`
- `litreview_unchecked`

Metrics require exact values and exact source file. Do not invent metrics.

## Dynamic update protocol

After repository changes:

1. Compare changed files to `last_verified_commit`.
2. Identify affected evidence, claims, snapshots and chapters.
3. Mark affected chapters `needs_update`.
4. Update `last_verified_commit` only after verification.
5. Do not rewrite existing chapters automatically.

## Bridge-section workflow

Bridge sections connect litreview to project implementation:

- Start from `litreview_snapshot.md` and `07_litreview_alignment.md`.
- Use bridge claims (`bridge_claim`) rather than pretending theory claims are code-verified.
- Make limitations explicit, especially automated editing and hybrid neural Camera Analysis.

## Prohibitions

- Do not fabricate metrics, filenames, commits or results.
- Do not edit production Swift/Python app code during thesis tasks.
- Do not rewrite protected litreview.
- Do not turn negative results into positive claims.

## Final report format

When finishing thesis workflow tasks, report:

1. Found litreview file.
2. Created/updated files.
3. Summary of thesis infrastructure changes.
4. Remaining `needs_source` or `partially_verified` items.
5. Chapters already covered by litreview.
6. Chapters to write next.
7. Recommended next prompt.
