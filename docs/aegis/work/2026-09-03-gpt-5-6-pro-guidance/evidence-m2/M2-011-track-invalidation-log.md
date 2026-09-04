# M2-011 — Track lifecycle invalidation log

Task: Invalidate subject tracks and coaching episodes on lens, orientation, route, camera
generation, or materially changed scene.
Owner boundary: `SubjectTrackingOwner`. Implementation: SubjectTracker.swift additions —
`SubjectTrackLifecycleContext`, `SubjectTrackLifecycleGuard`, `CoachingEpisodeToken`,
`SubjectTracker.invalidate(cause:frameID:)`.

## Invalidation causes (priority order of detection)

camera_generation_change → lens_change → orientation_change → route_exit → background →
scene_cut (deterministic signature inequality).

## Episode token semantics

`CoachingEpisodeToken` (UUID + generation) rotates on every invalidation. Consumers (advice,
verifier results) stamp results with the token; `isStale(token)` mismatches discard the result
(nil token always stale). No advice or verifier result survives an invalidating generation
change.

## Sequence tests (SubjectTrackLifecycleTests 7/7 PASS; xcresult /private/tmp/shafin-m2-011.xcresult)

1. Cumulative six-change sequence (generation → lens → rotation → stop → background → scene
   cut): each change detected with exactly its cause.
2. Unchanged context: no invalidation.
3. Route stop → restart: stop invalidates; restart moves context without duplicate cause.
4. Episode token: unchanged context keeps token; invalidation rotates; old token stale, new
   current, nil fails closed.
5. Verifier result stamped before a generation change is stale after it (must be discarded).
6. Tracker integration: invalidation of an active track reports its identity and loses the
   track; re-invalidation of a lost track reports nil.
7. Scene-cut sequence: guard detects, tracker loses, episode rotates, old advice stale.

Attempts: test built contexts non-cumulatively (generation re-detected instead of lens);
invalidate() reported already-lost track ids; argument order in cumulative contexts. All
test-side except the invalidate() active-only fix (production: lost tracks report nil).
