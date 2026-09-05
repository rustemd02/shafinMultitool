# M3-024 — scene provenance and rights manifests

Status: **implemented and verified in the isolated M3-024 lane**.

## Contract delivered

`datasets/scene-generator/v1/provenance/scene-provenance-v1.schema.json`
(Draft 2020-12) closes the versioned provenance surface:

- two header types (`source_manifest`, `rights_manifest`) and two entry
  types (`source_entry`, `rights_entry`), all bound to one corpus snapshot
  via a shared `manifest_sha256`;
- lawful bases `owner_authored | licensed | public_domain | synthetic`
  with per-basis typed evidence objects (author attestation, license,
  public-domain basis, complete synthetic lineage with declared parents);
- `copyrighted_screenplay_excerpt` as an explicit source kind that the
  validator can never admit;
- `raw_text_location` and `rights_uncleared_location` are schema-const
  `outside_git` — raw text and rights-uncleared material cannot travel
  inside Git-borne manifests.

`validate_scene_provenance.py` (stdlib runner, mandatory Draft 2020-12 via
`jsonschema`, fail-closed without it) enforces the cross-record rules JSON
Schema cannot express: header/count agreement, unique record identifiers,
source↔rights linkage and hash/kind agreement, approved-basis evidence
presence, unknown-basis approval rejection, copyrighted-excerpt exclusion,
synthetic lineage parents resolving to declared sources, and the
production-manifest non-empty rule.

## Production manifests

`source-manifest.jsonl` / `rights-manifest.jsonl` ship as
`template_only=true` with zero records — the honest statement that no real
scene corpus has been admitted yet. Both validate against the contract.
This slice makes no corpus-volume, human-review, training, or model-quality
claim.

## Verification

`python3 validate_scene_provenance.py --self-test` — positive synthetic
pair (2 source / 2 rights records) validates; **7 negative fixtures are
rejected** with pinned messages: unknown-basis approval, copyrighted
excerpt admitted, missing rights link, header count mismatch, content-hash
disagreement, undeclared synthetic lineage parent, production manifest
with zero records. Production manifests validate separately. Raw scene
text and rights-uncleared records remain outside Git.
