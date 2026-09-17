import Foundation

/// Explicit preference for one accepted image, in oriented Vision lower-left
/// coordinates. A region is not a physical instance or a temporal track.
struct CaptureImagePlacementGoal: Equatable, Sendable {
    enum Source: String, Sendable { case observedRegion, userRegion }
    let snapshotID: String
    let frameID: String
    let entityRef: String
    let observedRegion: NormalizedRect
    let source: Source

    /// Same image-space extent centred in the image; no physical distance,
    /// scale change, camera translation direction or free scene volume.
    var destinationRegion: NormalizedRect {
        .init(x: (1 - observedRegion.width) / 2, y: (1 - observedRegion.height) / 2,
              width: observedRegion.width, height: observedRegion.height)
    }

    var displacementX: Double { 0.5 - observedRegion.x - observedRegion.width / 2 }
    var displacementY: Double { 0.5 - observedRegion.y - observedRegion.height / 2 }

    /// Double roundoff only, not a perceptual, pixel-size or success threshold.
    /// Decimal coordinates such as x=0.4, width=0.2 need not subtract to exact 0.
    var isNumericallyCentered: Bool {
        abs(displacementX) <= 1e-12 && abs(displacementY) <= 1e-12
    }

    var isValid: Bool {
        !snapshotID.isEmpty && !frameID.isEmpty && !entityRef.isEmpty
            && entityRef.count <= 128
            && !entityRef.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            && PauseSemanticEntityGrounding.isValidRegion(observedRegion)
    }
}

/// Local review proposal. Intentionally cannot be passed to the correction
/// episode or ActionVerifier: the selected ROI has no temporal identity.
struct PauseImagePlacementProposal: Equatable, Sendable {
    let goal: CaptureImagePlacementGoal
    let intentRevision: UInt64
    /// Existing technical/quality advice keeps priority. Otherwise the UI may
    /// describe this explicit preference for the next capture.
    let isActiveReviewSuggestion: Bool
}

struct PauseImagePlacementCandidate: Equatable, Identifiable, Sendable {
    let id: String
    let region: NormalizedRect

    static func admitted(from entities: [VLMGroundedEntity]) -> [Self] {
        entities.compactMap { entity in
            guard entities.filter({ $0.entityRef == entity.entityRef }).count == 1,
                  entity.kind == .object || entity.kind == .prop || entity.kind == .person || entity.kind == .face,
                  let region = entity.region,
                  PauseSemanticEntityGrounding.isValidRegion(region) else { return nil }
            return Self(id: entity.entityRef, region: region)
        }
    }

    /// Multiple overlapping regions need an explicit numbered choice. Equal
    /// class names or nearest centres never disambiguate the user's selection.
    static func uniqueHit(x: Double, y: Double, in candidates: [Self]) -> Self? {
        guard x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y) else { return nil }
        let hits = candidates.filter {
            x >= $0.region.x && x <= $0.region.x + $0.region.width
                && y >= $0.region.y && y <= $0.region.y + $0.region.height
        }
        return hits.count == 1 ? hits.first : nil
    }
}
