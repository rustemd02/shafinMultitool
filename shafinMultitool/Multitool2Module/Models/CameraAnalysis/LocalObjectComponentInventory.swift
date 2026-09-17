import Foundation
import CryptoKit

/// A retained connected component of the bundled hard-label semantic map.
/// Different components may be fragments of one physical object; one component
/// may merge touching objects. Its reference is scoped to one frame, never to a
/// tracked physical instance. Segmentation support is pixel area × 20, not a
/// calibrated class probability or evidence that an object may be moved.
struct LocalObjectComponentEvidence: Codable, Equatable, Sendable {
    let entityRef: String
    let detectorLabel: String
    let region: NormalizedRect
    let segmentationSupport: Double
}

struct LocalObjectComponentInventory: Codable, Equatable, Sendable {
    enum GeometrySource: String, Codable, Sendable {
        case semanticComponent = "semantic_component"
        case trackedSemanticComponent = "vision_tracked_semantic_component"
    }

    // Leaves room for primary/frame/background/light aliases in the 32-entity
    // pause wire contract. Omitted candidates remain explicit counterevidence.
    static let maximumRetainedComponents = 24

    let frameID: String
    let detectorSourceFrameID: String
    let captureGeneration: UInt64
    let coordinateSpace: CameraCoordinateSpaceV2
    let geometrySource: GeometrySource
    let detectorMeasuredAt: Date
    let geometryMeasuredAt: Date
    let componentCandidateCount: Int
    let components: [LocalObjectComponentEvidence]

    var omittedComponentCount: Int {
        max(0, componentCandidateCount - components.count)
    }

    var isValid: Bool {
        !frameID.isEmpty && !detectorSourceFrameID.isEmpty && captureGeneration != 0
            && coordinateSpace == .vision
            && detectorMeasuredAt.timeIntervalSinceReferenceDate.isFinite
            && geometryMeasuredAt.timeIntervalSinceReferenceDate.isFinite
            && componentCandidateCount >= components.count
            && components.count <= Self.maximumRetainedComponents
            && components.enumerated().allSatisfy { index, component in
                component.entityRef == Self.entityRef(frameID: frameID, captureGeneration: captureGeneration, ordinal: index)
                    && !component.detectorLabel.isEmpty
                    && component.segmentationSupport.isFinite
                    && (0...1).contains(component.segmentationSupport)
                    && PauseSemanticEntityGrounding.isValidRegion(component.region)
            }
    }

    static func entityRef(frameID: String, captureGeneration: UInt64, ordinal: Int) -> String {
        let key = "\(captureGeneration):\(frameID)"
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return "detr-component-\(digest.prefix(24))-\(ordinal)"
    }

    /// Preserve a primary-subject alias only when it exactly names one retained
    /// component. Equal labels, nearest centres and overlapping boxes do not
    /// select a component or create a temporal identity.
    func groundedEntities(aliasing primary: VLMGroundedEntity?) -> [VLMGroundedEntity] {
        guard isValid else { return [] }
        let primaryMatches = components.filter { component in
            guard let primary, primary.kind == .object || primary.kind == .prop else { return false }
            return component.region == primary.region && component.detectorLabel == primary.detectorLabel
        }
        let primaryComponentRef = primaryMatches.count == 1 ? primaryMatches.first?.entityRef : nil
        return components.map { component in
            let primaryAlias = component.entityRef == primaryComponentRef ? primary?.entityRef : nil
            let usesPrimaryAlias = primaryAlias != nil
            return VLMGroundedEntity(
                entityRef: primaryAlias ?? component.entityRef,
                kind: .object,
                role: usesPrimaryAlias ? .primarySubject : .foregroundObject,
                region: component.region,
                detectorLabel: component.detectorLabel,
                detectorConfidence: nil,
                displayLabelCandidate: SemanticDisplayLabelPolicy.displayLabel(
                    entityKind: .object, role: usesPrimaryAlias ? .primarySubject : .foregroundObject,
                    groundedLabel: nil, confidence: 0
                ),
                displayLabelConfidence: 0
            )
        }
    }
}
