# M2-020 — Bounded action planner: decision matrix

Task: Implement one bounded planner that selects at most one actionable recommendation from
calibrated safe candidates.
Owner boundary: `AdvicePlannerOwner`. Implementation: NEW CameraBoundedActionPlanner.swift —
CameraPlannerCandidate / CameraPlannerDecision (decision ∈ KEEP/CORRECT/SELECT_SUBJECT/WAIT/
ABSTAIN via CameraCoachDecisionV2), pure plan(safetyDecision:candidates:goodFrameScore:frameID:).

## Decision matrix (10/10 tests pin every row)

| Safety gate (M2-019) | Candidates | goodFrameScore | Decision |
|---|---|---|---|
| WAIT(reason) | any | any | WAIT(reason), no action, no target |
| SELECT_SUBJECT(reason) | any | even 0.9 | SELECT_SUBJECT(reason), no action |
| ABSTAIN(reason) | any | any | ABSTAIN(reason) |
| ALLOW | present | ≥ 0.8 | KEEP (explicit already-good, planner-side path; full protection completes in M2-021) |
| ALLOW | present | < 0.8 | CORRECT top candidate |
| ALLOW | empty | < 0.8 | WAIT calibrated_probability_missing (honest) |

Selection bound: highest calibrated probability; ties → priority band asc → stable action id
(order-independent). CORRECT carries the linked subject-displacement target (M2-004);
non-CORRECT decisions carry none. No secondary live advice: the decision struct admits exactly
one actionID.
