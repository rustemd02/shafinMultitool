# AGENTS.md

## Thesis / Dissertation workflow

- `docs/thesis/litreview*` is protected existing theory/literature-review material. Do not edit it unless the user explicitly asks for litreview changes.
- `diploma.md` is the chronological project source-of-truth for research and development history.
- `docs/thesis/**` is the thesis workspace for briefs, outlines, snapshots, evidence maps, claim registry, prompts, chapter scaffolding and workflow docs.
- For autonomous thesis-related LLM work, start routing from `docs/thesis/08_agent_context_router.md` instead of loading the whole thesis workspace.
- Do not write unsupported thesis claims. Every technical claim must link to code, docs, tests, benchmark artifacts or `diploma.md`.
- Update `docs/thesis/03_evidence_map.md` and `docs/thesis/04_claim_registry.md` before editing practical/experimental chapters.
- Litreview claims are not automatically verified by code. Use `litreview_claim` and `litreview_unchecked` unless a separate bibliography verification task is performed.
- After code, benchmark or project-doc changes, update affected thesis artifacts and mark affected chapters `needs_update` when needed.
- Do not make incidental production app-code changes during thesis tasks.
- Do not run heavy ML training, benchmark generation or live simulator smoke tests unless explicitly requested.

Fast thesis checks:

```bash
find docs/thesis -name '*.md' -type f | sort
rg -n 'needs_source|conflicts_with_current_code|obsolete' docs/thesis
rg -n 'last_verified_commit' docs/thesis
```
