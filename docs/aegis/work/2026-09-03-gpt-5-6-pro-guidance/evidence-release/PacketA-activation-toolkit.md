# Packet A — activation toolkit (rights → attribution → split groups)

Status: **needs_review**. No rights decision was made by the agent. All outputs
stay `pending` / fail-closed until the owner fills the attestation files.

## 1. Status and what remains an external owner decision

Nothing is admitted. `datasets/camera-coach/v1/rights-manifest.jsonl` is still
`record_count=0`, `template_only=true`. The toolkit makes the owner's decision
one-shot machine-readable, but the decision itself is external:

- **A1 (cinematic CC-BY):** may CC-BY 3.0 Blender derivative frames go into the
  App Store app / release bundle with attribution? Legal decision.
- **Author strings:** the manifest has `kind, license, origin, origin_url,
  source, timestamp_s, title` — **no `author` field**. CC-BY needs an author/
  licensor statement. The agent will not infer it from the title or the license
  text; the owner must supply an attribution map with an explicit author per
  film.
- **A4 (AVA / AADB / EVA):** confirm they stay research-only forever; the
  validator rejects any attempt to mark them production/redistribution/admitted.
- **Count discrepancy:** manifest has 319 frames, `queue-v3-cinematic.jsonl` has
  313 cinematic frames. The 6 missing are all `tos_teaser`
  (`frame_0002/0004/0018/0020/0022/0024_00`); the cinematic receipt records
  `added_now=6` from `tos_teaser`, i.e. the queue predates the teaser add. That
  is the observed explanation, but the owner must still confirm it explicitly
  (`--count-discrepancy-note`), the tool will not accept it silently.

## 2. Files (new only; existing templates untouched)

| file | sha256 | why |
|---|---|---|
| `tools/datasets/validate_rights_attestation.py` | `845ff07d9a885a12015bd92f44b38ac6b1bf91c77d165c5fb87dd98275357033` | validates the owner attestation; exit 1 on any missing field, `admitted` without linked basis, or AVA/AADB/EVA production/admitted claims |
| `tools/datasets/emit_attribution_notices.py` | `02cbfe4e522de3841f73c38c7cb7729b9a05d488cc602488a0d4c24774004e2e` | emits per-frame CC-BY notices from an owner attestation + owner author map; refuses (exit 1) and writes nothing otherwise; `--dry-run` prints what is missing per film |
| `tools/datasets/build_split_groups.py` | `e8ef179cb259408284090b7385808b4962967dd9655060aabb8dcbbad973f13e` | groups frames by origin family (clip/derivative/episode) and emits splits only when the rights manifest is admitted; refuses per-jpg splits |
| `tools/tests/test_rights_activation_toolkit.py` | `3084a9c226ff1c44a539f8d0a3e2c62ae526e80d44342fdff961042981e60eeb` | fail-closed tests (a)–(e) |
| `datasets/camera-coach/v1/rights-attestation.template.json` | `ae1a484f1d0405d5f3f1bd4412e05a97e2cc8e7cde44a5274e43b4e2628a92e1` | empty owner decision template |
| `datasets/camera-coach/v1/attribution-map.template.json` | `94860969f3168cc04db5edd846939483de587e7ea61b74fff96f3d545dcec1b7` | empty per-film author/license/attribution map for the 3 films |
| `datasets/camera-coach/v1/cinematic-attribution-requirements.draft.json` | `c99ae6c5497500810277ec4b0bc1eeaccee83980fac701add9798b994bdb3b39` | machine-readable `admission_status: pending` requirement list (146/167/6 frames) |
| `datasets/camera-coach/v1/cinematic-origin-groups.draft.jsonl` | `d46a2ce7133406d45433606b5b067739c17cce85b631dd71ae851542497fb0c7` | origin-family grouping only, `split: null`, `admission_status: pending` |

No existing file under `docs/cameraanalysis/**`, `ml/**`, `shafinMultitool/**`,
`docs/thesis/**`, `backend/**`, `project.pbxproj` and no existing dataset
template was modified. No commits, no reset/stash, no network egress.

## 3. Commands and real results

| command | exit | result |
|---|---|---|
| `python3 -m pytest tools/tests/ -q` | 0 | **174 passed** (148 pre-existing + 26 new) |
| `validate_rights_attestation.py --attestation rights-attestation.template.json --print-missing` | 1 | `REFUSED: … 20 problem(s)`, lists every unfilled owner field |
| `emit_attribution_notices.py --dry-run` | 0 | prints `frames: 319 across 3 film family(ies)`, `NO 'author' field`, and required fields for `big_buck_bunny`/`tears_of_steel`/`tos_teaser`; nothing written |
| `emit_attribution_notices.py` (no attestation) | 1 | `missing --attestation … missing attribution map …`; no output files |
| `build_split_groups.py --dry-run` | 1 | prints 3 clip families (167/146/6); `REFUSED to emit splits: rights manifest is not admitted`; nothing written |
| `build_split_groups.py` (no `--dry-run`) | 1 | same refusal; nothing written |
| fixture runs in pytest | 0/1 | valid attestation emits 7/7 notices with required fields; AVA/AADB/EVA attestations rejected; admitted fixture emits 3 atomic groups with `cross_split_leak_count=0`; all `--dry-run` produce zero files |

## 4. Exact fields the owner must fill

`rights-attestation.template.json` (all 22 required; `null`/empty/`pending` = not
decided):

```
attestation_schema_id, attestation_version,
attester.attester_id, attester.attester_name, attester.attester_role,
attested_at,
corpus.corpus_id, corpus.source_id, corpus.manifest_sha256,
license.license_id, license.license_url, license.attribution_required,
permissions.production_allowed, permissions.redistribution_allowed,
people.people_present, people.consent_obtained, people.consent_reference,
basis.basis_type, basis.basis_reference, basis.basis_url (or basis.basis_sha256),
decision.admitted, decision.decision, decision.decision_scope
```
Plus `attribution.attribution_map_ref` (or `attribution.per_film`) when the
license requires attribution.

`attribution-map.template.json` — **required per film** (`author`,
`license_url`, `attribution_string`, `source_url`; optional `author_url`,
`title`) for exactly these three film keys:

| film_key | title | frames |
|---|---|---|
| `big_buck_bunny` | Big Buck Bunny (Blender Open Movie) | 146 |
| `tears_of_steel` | Tears of Steel (Blender Open Movie) | 167 |
| `tos_teaser` | Tears of Steel — teaser (Blender Open Movie) | 6 |

After filling, the owner (or an agent on the owner's behalf) runs:

```bash
python3 tools/datasets/validate_rights_attestation.py --attestation <attestation.json> --print-missing   # expect 0
python3 tools/datasets/emit_attribution_notices.py \
    --attestation <attestation.json> \
    --attribution-map <map.json> \
    --annotation-queue "$HOME/Library/Application Support/SETOS/annotation/queue-v3-cinematic.jsonl" \
    --count-discrepancy-note "<owner-confirmed reason>"
```
This writes `cinematic-attribution.draft.jsonl`, `…notices.draft.txt`,
`…summary.draft.json`. To emit splits, an admitted record must be appended to
`rights-manifest.jsonl` (the toolkit never overwrites the template), then:
`python3 tools/datasets/build_split_groups.py`.

## 5. Proof that nothing advances without a decision, and AVA/AADB/EVA cannot be cleared

- **No attestation → no output.** `emit` returns 1 and `build_split` returns 1,
  both before any write; tests assert the output dir stays empty.
- **No invented author.** The source manifest provenance has no `author`; the
  emitter refuses unless every film has owner-provided `author`,
  `license_url`, `attribution_string`, `source_url`. Dry-run names the 3 films
  and fields.
- **admitted without basis rejected.** Validator errors on
  `decision.admitted=true` without `basis_type`+`basis_reference`+(`basis_url` or
  `basis_sha256`). Covered by `test_validator_rejects_admitted_without_basis`.
- **AVA/AADB/EVA cannot be production-cleared.** Token match on
  corpus/source; `production_allowed=true`, `redistribution_allowed=true`, or
  `admitted=true` all produce errors. Parameterized test covers
  `ava_hf_mirror`, `aadb_official`, `eva_official`, `research/eva/fb40a9f1`;
  an `admitted=true` variant with both permission flags false is also rejected.
  `build_split` carries the same barred-token check as defense in depth.
- **Family leakage.** Splits are assigned to whole origin families, so
  neighbouring frames of one clip cannot cross splits; summary asserts
  `cross_split_leak_count=0`.
- **Non-admitted rights manifest.** Real template (`record_count=0`,
  `template_only=true`) → refusal reason printed verbatim.

## 6. Honestly NOT done

- No rights decision taken, no attestation filled, no admitted rights record,
  no admitted corpus (still 0).
- No real attribution `.draft.jsonl` was produced: that requires the owner's
  admitted attestation plus author map, so the emitter correctly wrote nothing.
  Only `pending` requirement/grouping drafts were produced.
- The admitted split path was exercised only with synthetic fixtures, never on
  the real 319 frames, because rights are not admitted.
- The 313/319 explanation (teaser frames added after the queue was built) is an
  observation from receipt/queue data, not an owner-confirmed admission; the
  tool still requires `--count-discrepancy-note`.
- No legal review of CC-BY for App Store distribution; no second independent
  annotator; no human-gold. Those remain outside Packet A.
