# V9.1 Reviewer / Red-Team

## proposal
- Require every deterministic semantic repair to emit reason codes.
- Treat coverage verifier issues as patchable diagnostics, not proof of semantic correctness.
- Keep `screen_text` overlay-only to avoid action enum inflation.

## risks
- Silent semantic drift remains possible when patch retry adds rows that satisfy structure but not intent.
- Hard-case mining can overfit to known Russian patterns if it replaces real screenplay eval.

## required_tests
- Coverage verifier must emit `missing_event_for_beat`.
- Collective enrichers must emit V9 reason codes.
- Stage notes must not leak into dialogue.

## open_conflicts
- Release/demo gate still needs live-model parity examples, not only unit tests.

## approval
PASS for hardening patch, CONDITIONAL for demo gate until live-model parity is rerun.
