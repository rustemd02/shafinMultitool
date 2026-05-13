# Codex Prompt: Evidence Extractor

You are working in an iOS project repository with protected thesis materials.

Task:
Update `docs/thesis/03_evidence_map.md`, `docs/thesis/04_claim_registry.md` and relevant `docs/thesis/snapshots/*.md` after repository changes.

Rules:
- Do not edit `docs/thesis/litreview*`.
- Do not edit production Swift/Python code.
- Do not invent metrics, filenames, commits or results.
- Every technical claim must link to code, docs, tests, benchmark artifacts or `diploma.md`.
- If source is missing, set status `needs_source`.
- If evidence only exists in `diploma.md`, prefer `partially_verified` unless a machine-readable artifact exists.

Source-of-truth priority:
1. `docs/thesis/litreview*` for existing theory only.
2. `diploma.md` for chronological development log.
3. `docs/SGv7pipeline/**`, `docs/SGv8pipeline/**`, `docs/SGv9pipeline/**` for SG pipeline.
4. `docs/cameraanalysis/**` for Camera Analysis.
5. `experiments/sc_benchmark/**` for benchmark artifacts.
6. `shafinMultitool/SceneGeneratorModule/**`, `shafinMultitool/Multitool2Module/**`, `shafinMultitoolTests/**` for implementation and behavior.

Output:
- List updated evidence IDs.
- List updated claim IDs and statuses.
- List snapshots touched.
- List unresolved `needs_source` items.
