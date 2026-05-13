# Dynamic Update Protocol

Last verified commit: `02bdf3ae0b711ed5e0b7a640cbf808196d304b62`

## After a new PR or repository change

1. Identify changed files since the chapter or thesis artifact `last_verified_commit`.
2. Classify changed files: code, docs, tests, benchmark/eval artifact, litreview, thesis-only.
3. Update `03_evidence_map.md` if new source-of-truth evidence appears.
4. Update `04_claim_registry.md` for affected claims.
5. Update affected snapshots.
6. Mark chapter skeleton/frontmatter `status` as `needs_update` if its dependencies changed.
7. Update `last_verified_commit` only after the relevant docs are reviewed.
8. Do not rewrite completed chapter prose automatically; prepare a patch proposal or change note.

## Finding affected claims

| Changed area | Affected artifacts |
|---|---|
| `SceneGeneratorModule/**` | architecture, implementation, model eval if behavior changed; architecture, implementation and metric claims. |
| `Multitool2Module/**` | camera snapshot, implementation, camera eval claims. |
| `docs/SGv7pipeline/**` | SG v7 evidence, training/eval claims. |
| `docs/SGv8pipeline/**` | SG v8 snapshot and metrics. |
| `docs/SGv9pipeline/**` | SG v9 snapshot and metrics. |
| `experiments/sc_benchmark/**` | model_eval_snapshot, metric claims. |
| `docs/cameraanalysis/eval/**` | camera_analysis_snapshot and camera metric claims. |
| `docs/thesis/litreview*` | protected theory; requires explicit litreview review. |

## Chapter status update rules

| Condition | Status |
|---|---|
| Dependency unchanged and claims verified | keep current status |
| Evidence changed but chapter text not updated | `needs_update` |
| Claim source missing after change | affected claim `needs_source`; chapter `needs_update` |
| Code contradicts chapter claim | affected claim `conflicts_with_current_code`; chapter `needs_update` |
| Only formatting/docs prompt changed | no chapter status change unless content dependency changed |

## Distinguishing practical vs theoretical changes

| Change | Practical impact | Theoretical/litreview impact |
|---|---|---|
| Code/test/eval changes | Usually yes. Update evidence/claims/snapshots. | Usually no. Do not edit litreview. |
| Benchmark metrics change | Yes. Update model/camera eval snapshots and metric claims. | No, unless bridge interpretation changes. |
| New litreview source or claim | No direct code impact. | Requires litreview-specific review and alignment update. |
| New project module | Yes. Update repository map and architecture snapshot. | Only bridge if it changes practical gap framing. |

## Litreview protection policy

1. `docs/thesis/litreview.md` is a protected existing theory/literature-review source.
2. Do not edit it unless the user explicitly asks to modify litreview.
3. Suggestions go to `07_litreview_alignment.md` or a separate review notes file.
4. Litreview claims are not automatically verified by code.
5. If a litreview statement conflicts with the current project, write a bridge/limitation note rather than silently rewriting the litreview.

## Lightweight verification commands

Use only fast checks unless explicitly asked for heavier validation:

```bash
find docs/thesis -name '*.md' -type f | sort
rg -n 'needs_source|conflicts_with_current_code|obsolete' docs/thesis
rg -n 'last_verified_commit' docs/thesis
```

Do not run heavy ML training, benchmark generation or simulator live smoke as part of routine thesis updates.
