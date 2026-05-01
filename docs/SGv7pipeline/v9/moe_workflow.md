# V9 Mixture Of Experts Workflow

This workflow is a required gate for V9 changes.

## Roles

1. `ML/LLM Senior Agent`
2. `Runtime Architect Agent`
3. `Data/Eval Scientist Agent`
4. `Swift/iOS Runtime Agent`
5. `Reviewer/Red-Team Agent`
6. `Integrator/Senior Architect Agent`

## Required Artifacts Per Role

Each role produces one short artifact in `docs/SGv7pipeline/v9/moe_artifacts/<date>/<role>.md`:

- `proposal`
- `risks`
- `required_tests`
- `open_conflicts`

## Decision Gates

1. `contract_gate`
2. `data_gate`
3. `runtime_gate`
4. `eval_gate`
5. `demo_gate`

Each gate must include approvals from at least two roles.

## Integrator Rules

- Aggregates all role artifacts into one implementation decision log.
- Resolves conflicting proposals explicitly.
- Blocks implementation if any gate is missing required approvals.
- Emits final spec in `final_v9_spec.md`.
