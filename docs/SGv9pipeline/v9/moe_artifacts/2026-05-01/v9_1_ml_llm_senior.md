# V9.1 ML / LLM Senior

## proposal
- Expand patch retry from structural-only to semantic coverage issues: missing beat event, collapsed dialogue, collective motion not expanded, unsupported action missing text.
- Permit patch `add` operations explicitly in prompt: add row, then replace allowed fields.
- Keep dynamic per-slot GBNF disabled; small model gets slot constraints via prompt plus verifier/patch.

## risks
- Agent process did not complete independently and was closed; integrator applied this role's planned checks directly in code.
- One retry is a mobile-safe compromise, not a guarantee.

## required_tests
- `containsFixableVerifierIssues` supports prefixed semantic issue codes.
- Patch prompt documents add+replace row workflow.

## open_conflicts
- True ML quality requires next dataset/Colab cycle; V9.1 is no-retrain runtime hardening.

## approval
INTEGRATOR-APPLIED, not independent approval.
