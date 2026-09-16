//
//  SubjectTapSelector.swift
//  shafinMultitool
//
//  M2-009 SubjectSelectionOwner: tap-to-select for ambiguous people, groups,
//  objects and scene regions. Pure and deterministic: converts a display-space
//  tap through the M2-003 inverse display transform, hit-tests the injected
//  candidates with a forgiving touch slop, and routes the tap to exactly one
//  intent — subject selection, recoverable empty feedback, an explicitly
//  coordinated focus action, or ignore. Focus never fires implicitly during
//  subject clarification, so the two behaviors cannot conflict.
//

import Foundation

/// The single decision a tap can produce.
enum SubjectTapIntentOutcome: Equatable, Sendable {
    /// A candidate was hit: S05 resolves with this subject.
    case subjectSelected(SubjectCandidate)
    /// Clarification tap on empty space: recoverable feedback, no focus.
    case clarificationEmptyTap
    /// Normal (non-clarification) mode: an explicit, coordinated focus action
    /// at the tapped scene point. Future focus/exposure implementation must go
    /// through this outcome instead of adding a parallel tap path.
    case focusRequested(sceneX: Double, sceneY: Double)
    /// Nothing to do (focus unavailable and no clarification active).
    case ignored
}

enum SubjectTapSelector {

    /// Forgiving touch area around a candidate region, in normalized units.
    static let touchSlop: Double = 0.04

    /// Hit-test in scene space: points inside the region inflated by
    /// `touchSlop` hit; the nearest candidate center wins; equal distances
    /// resolve by ascending candidate id (deterministic).
    static func hitTest(
        sceneX: Double,
        sceneY: Double,
        candidates: [SubjectCandidate],
        touchSlop: Double = SubjectTapSelector.touchSlop
    ) -> SubjectCandidate? {
        var best: (candidate: SubjectCandidate, distance: Double)?
        for candidate in candidates {
            guard let region = candidate.region else { continue }
            let insideInflated = sceneX >= region.x - touchSlop
                && sceneX <= region.x + region.width + touchSlop
                && sceneY >= region.y - touchSlop
                && sceneY <= region.y + region.height + touchSlop
            guard insideInflated else { continue }
            let centerX = region.x + region.width / 2
            let centerY = region.y + region.height / 2
            let distance = ((sceneX - centerX) * (sceneX - centerX)
                + (sceneY - centerY) * (sceneY - centerY)).squareRoot()
            switch best {
            case nil:
                best = (candidate, distance)
            case let .some(existing):
                if distance < existing.distance
                    || (distance == existing.distance && candidate.id < existing.candidate.id) {
                    best = (candidate, distance)
                }
            }
        }
        return best?.candidate
    }

    /// Routes one display-space tap. `transform` is the active M2-003 display
    /// transform (orientation + mirroring), so the same physical tap resolves
    /// to the same scene candidate in every orientation.
    static func route(
        displayX: Double,
        displayY: Double,
        candidates: [SubjectCandidate],
        clarificationActive: Bool,
        focusEnabled: Bool,
        transform: CameraDisplayTransform
    ) -> SubjectTapIntentOutcome {
        let clampedX = displayX.isFinite ? min(1, max(0, displayX)) : 0.5
        let clampedY = displayY.isFinite ? min(1, max(0, displayY)) : 0.5
        let scene = transform.inverse.apply(x: clampedX, y: clampedY)

        if clarificationActive {
            if let candidate = hitTest(sceneX: scene.x, sceneY: scene.y, candidates: candidates) {
                return .subjectSelected(candidate)
            }
            // Empty clarification tap: recoverable feedback — the S05 state
            // stays up; focus must not fire here or it would steal the
            // selection gesture.
            return .clarificationEmptyTap
        }

        guard focusEnabled else { return .ignored }
        return .focusRequested(sceneX: scene.x, sceneY: scene.y)
    }
}

// CC-O02: tap-grounding for tracked object instances. When two foreground
// instances overlap, an object-targeted correction is ambiguous until the
// operator names the target; a tap is that naming gesture. Pure and
// deterministic — the same hit/slop/nearest-center contract as the subject
// selection above.
extension SubjectTapSelector {
    struct TrackedInstanceHit: Equatable, Sendable {
        let trackID: String
        let region: NormalizedRect
    }

    static func hitTestTrackedInstances(
        sceneX: Double,
        sceneY: Double,
        instances: [(trackID: String, region: NormalizedRect)],
        touchSlop: Double = SubjectTapSelector.touchSlop
    ) -> TrackedInstanceHit? {
        var best: (trackID: String, region: NormalizedRect, distance: Double)?
        for instance in instances {
            let region = instance.region
            let insideInflated = sceneX >= region.x - touchSlop
                && sceneX <= region.x + region.width + touchSlop
                && sceneY >= region.y - touchSlop
                && sceneY <= region.y + region.height + touchSlop
            guard insideInflated else { continue }
            let centerX = region.x + region.width / 2
            let centerY = region.y + region.height / 2
            let dx = sceneX - centerX
            let dy = sceneY - centerY
            let distance = (dx * dx + dy * dy).squareRoot()
            if best == nil || distance < best!.distance {
                best = (instance.trackID, region, distance)
            }
        }
        guard let hit = best else { return nil }
        return TrackedInstanceHit(trackID: hit.trackID, region: hit.region)
    }
}
