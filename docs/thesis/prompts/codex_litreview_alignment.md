# Codex Prompt: Litreview Alignment

Analyze the existing protected litreview and connect it to the practical project without editing the litreview itself.

Inputs:
- `docs/thesis/litreview*`.
- `docs/thesis/snapshots/litreview_snapshot.md`.
- `docs/thesis/07_litreview_alignment.md`.
- Relevant project snapshots.

Task:
- Identify which litreview sections need bridge paragraphs.
- Map theory topics to Scene Generator, Camera Analysis, evaluation methodology and limitations.
- Propose bridge paragraphs separately as patch proposal or new notes.
- Do not modify the original litreview.

Rules:
- Litreview claims remain `litreview_claim`.
- Do not verify bibliography through code.
- Mark unclear or unsupported theory-to-project links as `unclear` or `needs_bridge`.

Output:
1. Alignment table updates.
2. Proposed bridge paragraph outlines.
3. Claim registry bridge_claim updates.
4. Risky or out-of-scope litreview topics.
