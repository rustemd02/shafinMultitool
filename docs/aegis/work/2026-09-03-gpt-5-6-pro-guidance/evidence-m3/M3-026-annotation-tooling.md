# M3-026 — scene annotation tooling

Status: **closed on the current store**.

`tools/scene_annotation/annotate_scene.py` scaffolds a schema-valid gold
candidate from an annotation input record: candidates and acceptable
variants deep-copied verbatim, gold pointing at the first (human) candidate
with the full variant list, empty votes/review history for the M3-005
pilot. Hard gates: preservation check (any dropped/edited alternative is a
typed failure), model-identity check (gold primary must be human or
deterministic; name/token scan), mandatory Draft 2020-12 validation with
local `$ref` registry (fail-closed offline).

Verification: `--self-test` green — positive scaffold plus 4 check-level
negatives (empty candidates, ghost primary, edited candidate, model
primary). No corpus, rights, or model-quality claim.
