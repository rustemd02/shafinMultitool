# Runtime Source Expectations v1

## Purpose

This contract defines deterministic source-side predicates used by `low_quality_accept_v1` in Track 10 runtime feedback normalization.

Version id:
- `runtime_source_expectations_v1`

## Inputs

- `source` (normalized user text)
- `marked_objects` (list with `name` and stable marker identity metadata)
- frozen unsupported lemma list from:
  - [unsupported_action_lemmas_v1.txt](/Users/unterlantas/Documents/XCode/shafinMultitool/docs/SGv7pipeline/runtime_feedback/contracts/unsupported_action_lemmas_v1.txt)

## Output Fields

- `expected_multi_beat: bool`
- `expected_marked_object_mentions: int`
- `unsupported_action_present: bool`

## Deterministic Rules

### 1. Text normalization

Before matching:
- lowercase
- Unicode NFC normalization
- `ё -> е`
- collapse spaces
- strip edge punctuation

### 2. expected_multi_beat

Set `expected_multi_beat=true` when source contains at least two phase cues from different groups:
- movement cues: `идут`, `подходят`, `двигаются`
- stop cues: `останавливаются`, `останавливается`, `стоп`
- pass-by cues: `проходят мимо`, `проходит мимо`
- sequencing cues: `затем`, `после этого`, `потом`
- action-start cues: `начинает`, `начинают`

Else:
- `expected_multi_beat=false`

### 3. expected_marked_object_mentions

For each marked object:
- match by exact normalized name OR lemma match
- count each object at most once

Result:
- `expected_marked_object_mentions = number_of_unique_matched_marked_objects`

### 4. unsupported_action_present

Set `unsupported_action_present=true` if any lemma from frozen unsupported list is present in normalized source.

Else:
- `unsupported_action_present=false`

## Failure Handling

If any output field cannot be computed deterministically:
- mark case with `expectation_compute_failed`
- do not treat the case as `low_quality_accept`
- keep case in bronze and route to review queue only if other hard conditions (`merge|reject|manual incorrect`) are met

