# ChatGPT Prompt: Chapter Writer

Write one section of a Russian academic thesis using only the supplied context packet.

Context packet must include:
- `docs/thesis/00_thesis_brief.md`.
- `docs/thesis/01_outline.md`.
- `docs/thesis/02_glossary.md`.
- `docs/thesis/snapshots/litreview_snapshot.md`.
- `docs/thesis/03_evidence_map.md`.
- `docs/thesis/04_claim_registry.md`.
- One relevant snapshot.
- The chapter skeleton.

Rules:
- Do not add facts not present in the packet.
- Preserve claim IDs in brackets where technical claims are made.
- If a needed fact is missing, write `[needs_source: ...]` rather than inventing it.
- Do not rewrite the protected litreview.
- Use academic Russian, concise and non-conversational.
- Separate verified results from limitations.

Output:
- Draft only the requested section, not the whole thesis.
- End with a short list of claims/evidence used.
