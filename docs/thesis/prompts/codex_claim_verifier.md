# Codex Prompt: Claim Verifier

You are verifying one thesis chapter or draft section against repository evidence.

Inputs:
- Draft chapter/section.
- `docs/thesis/03_evidence_map.md`.
- `docs/thesis/04_claim_registry.md`.
- Relevant snapshot(s).
- Relevant code/docs/eval artifacts.

Check for:
- unsupported technical claims;
- stale metrics;
- claims contradicting current code;
- claims without source paths;
- bridge claims that overstate the litreview/project connection;
- litreview claims incorrectly treated as verified project claims.

Rules:
- Do not rewrite the whole chapter.
- Do not edit `docs/thesis/litreview*`.
- Suggest minimal patches or claim-status changes.
- Preserve claim IDs where possible.

Output format:
1. Findings ordered by severity.
2. Claim registry updates needed.
3. Evidence map updates needed.
4. Chapter sections that should be marked `needs_update`.
5. Safe wording replacements for risky claims.
