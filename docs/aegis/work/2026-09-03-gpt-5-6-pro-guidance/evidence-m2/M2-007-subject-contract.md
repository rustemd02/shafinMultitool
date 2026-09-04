# M2-007 — Subject resolution contract

Task: Define subject candidates, group union, user selection, ambiguity reasons, track identity,
and selected-subject provenance.
Owner boundary: `SubjectResolutionOwner`. Implementation: NEW
shafinMultitool/Models/CameraAnalysis/SubjectResolutionContracts.swift (existing primitives
SubjectCandidate/SubjectKind/NormalizedRect reused).

## Contract

- `SubjectTrackIdentity` — stable trackID + firstSeenFrameID + camera generation (M2-010
  consumes; M2-011 invalidates on lens/orientation/route change).
- `SubjectAmbiguityReasonV2` — tie_between_persons, person_and_group_overlap,
  low_detection_confidence, conflicting_evidence, no_candidate.
- `SubjectSelectionSourceV2` — automatic / userTap / groupUnion (provenance).
- `SubjectGroupUnionV2.union(of:)` — bounding-box union of ≥2 region-bearing candidates; nil
  otherwise (fail closed).
- `SubjectResolutionV2` — resolution ∈ automatic/user_selected/group/unknown; throwing
  validation: unknown ⇒ no candidate AND ≥1 ambiguity reason (fail-closed SELECT_SUBJECT);
  non-unknown ⇒ candidate; group ⇒ union; automatic ⇒ confidence ∈ [0,1]. Confidence and
  ambiguity are separate axes: user taps resolve ambiguity with nil confidence.
- Provenance: decidedAtFrameID on every resolution (envelope frame, M2-005).

## Tests (SubjectResolutionContractsTests 9/9 PASS; xcresult /private/tmp/shafin-m2-007.xcresult)

Automatic person resolution valid; automatic without confidence throws; out-of-range confidence
throws; unknown requires reason and never names a candidate; group union spans member regions /
single-candidate and missing-region nil / group-without-union invalid; tied candidates resolve
to unknown with reasons (no guessing); confidence vs ambiguity separation (user tap, nil
confidence, reasons preserved); Codable round-trips for person/user/object/group/unknown
shapes; track identity validation.
