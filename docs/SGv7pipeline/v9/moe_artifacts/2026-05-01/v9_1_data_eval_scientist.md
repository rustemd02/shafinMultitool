# V9.1 Data/Eval Scientist

## proposal
- Add chunk-oriented metrics on top of event semantic counts: event coverage, continuity placeholders, playback intent pass.
- Add hard-case mining script clustered by dialogue+action, collective motion, reciprocal movement, stop-near-object, temporal connectors, and unsupported described actions.

## risks
- Coverage metrics can be misleading if gold rows are incomplete; report them as semantic coverage, not structural validity.
- Playback intent needs real-app parity labels before it can become a release gate.

## required_tests
- Missing event row should reduce `chunk_event_coverage_rate`.
- Existing structural/semantic/degradation summary must stay backward compatible.

## open_conflicts
- No live-model benchmark was run in this patch; mining output is preparation for next retrain.

## approval
PASS for eval gate at V9.1 runtime/eval-first scope.
