# Component supervision evidence v1

`camera_training_checkpoint.v2` and `camera_training_receipt.v3` add explicit
component evidence to the existing records trainer. Model input/output contracts
and training-record versions do not change. `component_supervision.py` validates
and serializes `camera-component-supervision-v1`; it never admits model quality,
rights, calibration or runtime use.

For each direct loss head, canonical `ordered_names` bind arrays of observation
counts, targets equal to one, targets equal to zero, other target values and
successful optimizer steps. Scalar heads use their head name as the one component.
For categorical cross-entropy each observed class label supervises all softmax
logits; the one/zero counts preserve which classes appeared as positives. For
regression these are literal value buckets: a known zero delta is an observed
target, while an absent delta has a zero mask and contributes no observation.
The internal embedding has no independent direct-label coverage claim.

Counters read the same augmented targets and head/intent masks used by the loss.
Zero head weights and zero focal balancing remove supervision. Counts are committed
only after a successful train optimizer step. Validation, failed steps and fully
masked batches do not add counts. Ranking pairs are counted separately and do not
establish absolute good-frame supervision. Repeated epochs/sampling add repeated
observations; these numbers are not unique-image counts or quality metrics.

`source` records the declared dataset SHA, a fingerprint of the actually supplied
records/targets/masks/pixels/intent, the model contract SHA, effective loss SHA and
resume semantics SHA. `processed_batches_sha256` chains the prepared record IDs,
targets, effective masks and ranking-pair counts of committed steps. The checkpoint
preserves this lineage atomically with optimizer, sampler and RNG state. A resumed
run must match the source identities and canonical component order.

The latest checkpoint and each selected best state retain their own evidence.
The result's `component_supervision` describes its selected model state;
`final_component_supervision` describes the final completed training state.
Later epochs cannot retroactively establish supervision for an earlier best state.
Early stopping saves the last completed epoch before leaving the loop.

The compatibility `trained_head_mask` now means that at least one component has
observed direct supervision. It never means that all components are covered.
`enabled_head_mask` separately records the configured objective availability.
Component states are `observed_direct_supervision`,
`no_observed_direct_supervision` or `unknown`. A zero count in a fresh run means no
observed direct supervision; a missing legacy prefix means unknown. Existing v1
checkpoints remain immutable. They may resume with an unknown prefix and counts
for subsequent actual steps; an aggregate legacy flag cannot manufacture counts.
A v2 checkpoint missing its required evidence is rejected rather than downgraded.

`export_v2.py` keeps seeded tooling export and additionally accepts an explicit
records checkpoint plus its matching training config. It validates format,
config semantics, candidate, manifest, selected epoch, finite state tensors,
strict state-dict loading and selected-state component bindings. Research export
preserves legacy unknown evidence. `--require-component HEAD:NAME` is a connected
fail-closed export requirement: every named component must have observed direct
supervision. No option grants release admission. Exported packages and sidecars
contain component metadata and remain research/tooling-only with
`release_admissible=false`; the app's existing research-bundle exclusion remains
the runtime/release barrier.

The separate legacy Stage-2/v1 converter also writes component metadata: absent
evidence is unknown, independently of its historical three-head declaration.
Neither converter upgrades old checkpoints or receipts. Conversion must pass
nonempty, finite, shape-correct PyTorch/Core ML comparisons at fixed
atol=0.005 and rtol=0.01. Parity establishes numerical transfer only; it does not
establish useful advice or model quality.
