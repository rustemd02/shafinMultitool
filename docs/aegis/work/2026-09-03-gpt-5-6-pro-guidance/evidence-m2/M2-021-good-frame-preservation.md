# M2-021 — Good-frame preservation unit report

Task: Implement explicit already-good detection and protection against overcorrection.
Owner boundary: `SafetyPolicyOwner`. Implementation: NEW GoodFramePreservationPolicy.swift —
pure policy over the good-frame head score history (M2-017 contract head).

## KEEP predicate (stable high confidence, no dominant failure)

KEEP requires: (a) ≥ 5 consecutive frames with good-frame score ≥ 0.8 (stability window — a
single flash or a short strong history abstains), (b) no DOMINANT technical failure
(defocus/under/over/clipping) — a dominant failure contradicts the good-frame head.
Uncertain strong-looking frames → ABSTAIN, never a fix. The verdict enum has NO correction
case at all: overcorrection of a good frame is structurally inexpressible.

## Curated fixtures (GoodFramePreservationPolicyTests 8/8 PASS; xcresult
/private/tmp/shafin-m2-021.xcresult)

1. Six sustained high scores, no failure → KEEP(f5, 0.91).
2. Single 0.95 flash inside low stream → abstain historyTooShort.
3. Three high frames (< streak 5) → abstain.
4. 4-high/1-dip/4-high → streak broken → abstain.
5. 6×0.95 WITH dominant failure → abstain dominantTechnicalFailure + forbidden-correction
   assertion (no correction case in verdict).
6. Score exactly at threshold 0.8 counts (>=).
7. stableStreak = 1 keeps on the first high frame.
8. Empty history abstains.
