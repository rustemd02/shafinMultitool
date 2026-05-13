# Codex Prompt: Dynamic Thesis Update

Compare the current repository with a base branch or the `last_verified_commit` recorded in thesis artifacts.

Task:
Find thesis-relevant changes and update only affected thesis infrastructure.

Steps:
1. Determine base commit from chapter/snapshot frontmatter or user-provided base.
2. List changed files.
3. Classify changes: code, docs, tests, benchmark/eval, litreview, thesis-only.
4. Update affected `03_evidence_map.md`, `04_claim_registry.md`, snapshots and chapter statuses.
5. Do not rewrite chapters in full.
6. Do not edit `docs/thesis/litreview*`.
7. Do not edit production app code.

Special handling:
- If metrics changed, update exact values and sources.
- If source disappeared, mark claim `needs_source`.
- If code contradicts a claim, mark `conflicts_with_current_code`.
- If litreview changed, update `litreview_snapshot.md` and `07_litreview_alignment.md`, but do not judge bibliography unless asked.

Output:
- Changed thesis files.
- Affected evidence IDs.
- Affected claim IDs and status changes.
- Chapters marked `needs_update`.
- Recommended next prompt for writing or verification.
