# Scene Generator annotation guide v1 (M3-025)

Version: v1.0.0. Schema authority: `datasets/scene-generator/v1/schema/scene-annotation-v1.schema.json`
(+ `scene-script-v1`, `scene-output-v1`, `scene-clarification-v1`). Rights
authority: `datasets/scene-generator/v1/provenance/scene-provenance-v1.schema.json`.
Human pilot for finalization is explicitly pending (M3-005); this guide is
the locked instruction set the pilot annotates against.

## 0. Rights before labels

Annotate only records present in the admitted set of
`source-manifest.jsonl`/`rights-manifest.jsonl`. Records marked
`quarantined`/`excluded`, or whose lawful basis is `unknown`, must not be
opened. Raw text stays outside Git; the annotation rows carry identifiers
and hashes, never pasted copyrighted text.

## 1. Scene boundaries

- One annotation row covers exactly one continuous scene: a single location,
  continuous story time, and one dramatic beat.
- Split when ANY of: location changes, time jumps, speaker-address group
  changes, or an explicit script scene heading appears.
- Merge never: overlapping/duplicate rows fail schema validation
  (`record_id` uniqueness, ordered ranges).

## 2. Entity identity

- Entities are typed (`actor`, `object`) and identified by stable lowercase
  ids (`actor_*`, `object_*`) assigned at FIRST mention and reused verbatim.
- One real-world entity = one id forever, regardless of surface form:
  «стул», «тот стул у окна», «он» (when co-referent) share the id.
- Do not merge two distinct entities that share a surface form; mark them as
  separate and let clarification resolve the ambiguity.
- Device-anchored objects marked in AR use the `object_marked_*` id form.

## 3. Coreference

- Record every co-referent mention in the mention list of the entity with
  its byte offsets (UTF-8 scalar boundaries — the schema rejects
  non-scalar offsets).
- A pronoun is co-referent only when the antecedent is unambiguous inside
  the scene; otherwise leave unresolved — clarification handles it. Do not
  guess.

## 4. Action chronology

- Actions are ordered by first textual occurrence; `order` is 0-based,
  dense, and increasing (schema-validated).
- One row per distinct action verb+target pair; repeated mentions extend
  the mention list, not the action list.
- Implied actions are not annotated; only textually present actions.

## 5. Spatial references

- Spatial relations reference two annotated entity ids plus a typed
  relation (`near`, `on`, `in_front_of`, …) exactly as enumerated in the
  schema; free-form relations are rejected.
- Frame of reference is the script text (not the camera): «слева от стула»
  is text-relative.

## 6. Acceptable alternatives

- `alternatives` lists equally valid readings, each with the same schema
  shape as the primary. Use it when the text genuinely supports multiple
  staged outcomes (object identity, count, or placement).
- Alternatives never contradict the primary annotation's scene boundaries.

## 7. Clarification

- When the text requires a human decision the schema cannot express as
  alternatives, emit a clarification question bound to the request identity:
  one question, the enumerated options, and the byte-span under question.
- Questions are quoted verbatim from the span (no interpretation); the
  answer schema (M3-023) validates identity and option membership.

## 8. Forbidden

- Hallucinated entities/actions/places absent from the text.
- Splitting or merging scenes to make counts match a target.
- Copying copyrighted source text into any Git-tracked file.
- Cross-family derivation: a derived record must keep the
  `derivation_family_id` of its provenance entry (M3-024).

## 9. Adjudication and pilot

- Two annotators annotate independently; disagreements go to the M3-005
  human calibration pilot with the disagreement reason recorded.
- The pilot's final labels are the only release-grade labels; before that,
  every set is `development_regression`.
