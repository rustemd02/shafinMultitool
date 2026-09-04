# M2-019 — Safety policy matrix (forbidden-action and abstention gates)

Task: Implement deterministic forbidden-action and abstention gates after neural inference.
Owner boundary: `SafetyPolicyOwner`. Implementation: NEW CameraAdviceSafetyGate.swift —
CameraAdviceSafetyInput (evidence snapshot from the M2-005 envelope + M2-012…016/M2-018
owners), CameraAdviceActionFamily, CameraAdviceSafetyGate.evaluate (pure, deterministic).

## Policy matrix (evaluation order = priority)

| # | Gate | Decision |
|---|---|---|
| 1 | Unknown lens generation | ABSTAIN lens_generation_unknown (all families) |
| 2 | Subject track lost | ABSTAIN subject_identity_lost (overrides family gates) |
| 3 | Subject unresolved/ambiguous | SELECT_SUBJECT subject_ambiguous |
| 4 | Motion ≠ still | WAIT motion_not_still |
| 5 | Exposure contradiction (under+over) | WAIT exposure_contradiction |
| 6 | Family: horizon | horizon evidence unavailable/nil → ABSTAIN horizon_evidence_unavailable |
| 6 | Family: focus | focus evidence not admitted/nil → ABSTAIN focus_evidence_not_admitted |
| 7 | Calibrated probability missing | ABSTAIN calibrated_probability_missing |
| 8 | Calibrated probability < threshold | WAIT calibrated_probability_low |
| — | All gates pass | ALLOW |

## Tests (CameraAdviceSafetyGateTests 12/12 PASS; xcresult /private/tmp/shafin-m2-019.xcresult)

Per-family table (horizon/focus require their evidence incl. nil fail-closed; exposure/
composition/keep carry no family gate); unknown generation abstains every family; lost identity
abstains corrections and OVERRIDES family gates; unresolved/ambiguous subject → SELECT_SUBJECT;
motion → WAIT; exposure contradiction → WAIT; calibration missing → ABSTAIN, low → WAIT, at
threshold → ALLOW.
