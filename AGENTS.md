# AGENTS.md

## Local project data (owner instruction, 2026-09-16)

- Store datasets, annotation journals, checkpoints, Colab bundles and task snapshots in `/Users/unterlantas/Documents/XCode/setos-backend/local-data/SETOS/`, never in Library/Application Support.
- Do not create new project data under `/Users/unterlantas/Library` or `/Library`. This rule concerns development artifacts, not iOS sandbox APIs.
- Keep raw media out of this iOS repository and Xcode bundles. Backend `local-data/` is local-only, excluded from Git and must not be deployed or published.
- Historical receipts/manifests retain their original bytes and old absolute paths. See `../setos-backend/LOCAL_DATA.md` for the relocation mapping; do not rewrite hash-bound evidence in place.

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
