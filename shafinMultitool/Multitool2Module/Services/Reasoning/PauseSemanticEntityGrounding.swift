import Foundation

/// A lookup over the local evidence sent for one accepted pause image. These
/// references name regions in that image; they are not temporal track identities,
/// proof of physical scene control, or an action-completion predicate.
struct PauseSemanticEntityGrounding: Sendable {
    let frameID: String
    let entities: [VLMGroundedEntity]

    struct Resolution: Equatable {
        let region: NormalizedRect?
        let allowsAction: Bool
    }

    func resolve(targetEntityRef: String?,
                 targetEntityKind: TargetEntityKind,
                 actionType: SemanticActionType,
                 actionFrame: SemanticActionFrame,
                 plannedSubjectRegion: NormalizedRect?,
                 expectedFrameID: String) -> Resolution {
        guard !frameID.isEmpty, frameID == expectedFrameID else {
            return Resolution(region: nil, allowsAction: false)
        }

        let needsResolvedTarget = actionFrame == .moveObject || actionFrame == .moveSubject
            || Self.requiresSamePlannedRegion(actionType)
        guard let targetEntityRef, !targetEntityRef.isEmpty else {
            return Resolution(region: nil, allowsAction: !needsResolvedTarget)
        }
        let matches = entities.filter { $0.entityRef == targetEntityRef }
        guard matches.count == 1,
              let entity = matches.first,
              Self.matches(kind: entity.kind, target: targetEntityKind) else {
            return Resolution(region: nil, allowsAction: !needsResolvedTarget)
        }
        guard let region = entity.region, Self.isValidRegion(region) else {
            return Resolution(region: nil, allowsAction: !needsResolvedTarget)
        }

        // The existing planner derives direction, distance intent and framing
        // from its own target. A different cloud-selected region cannot inherit
        // that decision merely because its label matches. Replanning belongs to
        // the existing planner, never to the presentation lookup.
        if Self.requiresSamePlannedRegion(actionType), region != plannedSubjectRegion {
            return Resolution(region: nil, allowsAction: false)
        }
        return Resolution(region: region, allowsAction: true)
    }

    static func isValidRegion(_ region: NormalizedRect) -> Bool {
        region.x.isFinite && region.y.isFinite
            && region.width.isFinite && region.height.isFinite
            && region.x >= 0 && region.y >= 0
            && region.width > 0 && region.height > 0
            && region.x + region.width <= 1 && region.y + region.height <= 1
    }

    private static func matches(kind: VLMEntityKind, target: TargetEntityKind) -> Bool {
        switch (kind, target) {
        case (.person, .person), (.face, .face), (.object, .object), (.prop, .prop),
             (.backgroundArea, .backgroundArea), (.lightSource, .lightSource), (.frame, .frame):
            return true
        // The local detector does not infer whether an observed object is a prop.
        case (.object, .prop), (.prop, .object):
            return true
        default:
            return false
        }
    }

    private static func requiresSamePlannedRegion(_ action: SemanticActionType) -> Bool {
        switch action {
        case .shiftFrameLeft, .shiftFrameRight, .shiftFrameUp, .shiftFrameDown,
             .stepCloser, .stepBack,
             .moveSubjectLeft, .moveSubjectRight, .moveSubjectAwayFromBackground,
             .moveObjectLeft, .moveObjectRight, .moveObjectForward, .moveObjectBack,
             .repositionPropForBalance:
            return true
        default:
            return false
        }
    }
}
