# Intent: assisted visual review prefetch

- Outcome: keep the annotator ahead of the user with current + five visual proposals.
- Scope: existing loopback reviewer, Command Code media boundary, journal, keyboard UI and documentation.
- Non-goals: iOS code, model training, production admission, human-gold promotion, changing the selected model.
- Baseline: `docs/aegis/plans/2026-09-15-camera-visual-prefetch-review.md` and the existing frozen v2 issue/action vocabulary.
- Risk: paid concurrency, cache identity, pixel egress without ZDR and accidental machine-to-gold promotion.
- Stop: implementation and bounded verification complete, or exact provider/validation blocker recorded.

