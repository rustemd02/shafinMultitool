# M3-025 — scene annotation guide

Status: **implemented and verified in the coordinator session**.

`datasets/scene-generator/v1/guides/scene-annotation-guide-v1.md` (v1.0.0)
defines, per the tracker verification column: scene boundaries (split/merge
rules bound to the M3-023 schema's uniqueness and ordered ranges), entity
identity (stable typed ids, first-mention assignment, no false merges),
coreference (mention lists with UTF-8 scalar byte offsets, unresolved
left to clarification), action chronology (dense 0-based textual order),
spatial references (typed two-entity relations, text frame of reference),
acceptable alternatives (same-shape, non-contradictory), and clarification
binding (one question, enumerated options, verbatim span, request-owned
identity per M3-023).

Rights integration: annotation is restricted to admitted provenance
records (M3-024), raw text stays outside Git, and cross-family derivation
is forbidden — the guide repeats the fail-closed rights admission rules.
Human pilot for finalization is explicitly pending (M3-005); labels before
that pilot are `development_regression`.

Verification: guide content is rule-by-rule consistent with the six
authorities it cites (annotation/script/output/clarification schemas,
provenance contract, M3-005 pilot policy); no corpus, rights, or
model-quality claim is made.
