# M2-008 — Automatic subject resolution: decision table

Task: Implement automatic face/person/group subject resolution using Apple Vision and attention
saliency.
Owner boundary: `SubjectResolutionOwner`. Implementation: NEW SubjectResolver.swift — pure and
deterministic, consumes VisionTrackingResult (Apple Vision faces + human rectangles + attention
saliency), produces the M2-007 SubjectResolutionV2 contract.

## Decision table (pinned by SubjectResolverTests 10/10)

| Input | Outcome |
|---|---|
| 0 subjects | unknown [.noCandidate] — fail closed |
| 1 person (conf ≥ 0.5) | automatic person; face merged into its human rectangle (max confidence preserved) |
| 1 person (conf < 0.5) | automatic + [.lowDetectionConfidence] reason |
| face inside human box | merged: person box, max confidence, face detail |
| 2+ people, top-two confidence within 0.15 tie threshold, both ≥ 0.5 | group union of all detected boxes, [.personAndGroupOverlap] |
| saliency center endorses exactly one subject (conf ≥ 0.5) | automatic that subject |
| saliency endorses low-confidence region | unknown [.conflictingEvidence, .lowDetectionConfidence] |
| clear confidence gap (no tie), top ≥ 0.5 | automatic top candidate |
| 2 tied low-confidence people | unknown [.tieBetweenPersons, .lowDetectionConfidence] |

No random selection anywhere: ambiguity returns unknown (SELECT_SUBJECT) with reasons.

## Tests (SubjectResolverTests 10/10 PASS; xcresult /private/tmp/shafin-m2-008.xcresult)

0/1/2/3 synthetic subjects; face-in-person merge (box + max confidence); tie → group union;
saliency endorsement picks one of two; low-confidence conflict; tied low-confidence double
reason; distinct-gap elects higher candidate; missing-subject fail-closed.

Attempts: 1) test-side NormalizedRect.minX accessor; 2) REAL decision-table gap found by tests
(clear-gap case fell through to unknown) — fixed: explicit no-tie automatic branch; 3) Float
VNConfidence precision in expectations — accuracy comparisons. 10/10 PASS.
