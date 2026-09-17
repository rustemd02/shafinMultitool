import Foundation

/// Explicit user knowledge about control of the accepted still's scene.
/// A rectangle, model response, image-transfer consent or absence of a
/// restriction does not create this fact. It grants no tracking, resource,
/// geometric, safety, action-completion or verifier authority.
struct PauseSceneControlFacts: Equatable, Sendable {
    enum State: String, Codable, CaseIterable, Sendable {
        case unknown
        case allowed
        case forbidden
    }

    enum Category: String, CaseIterable, Sendable {
        case objects
        case participants
        case lighting
    }

    let frameID: String
    let objects: State
    let participants: State
    let lighting: State

    init(frameID: String, objects: State = .unknown,
         participants: State = .unknown, lighting: State = .unknown) {
        self.frameID = frameID
        self.objects = objects
        self.participants = participants
        self.lighting = lighting
    }

    static let unknown = PauseSceneControlFacts(frameID: "")

    func state(for category: Category) -> State {
        switch category {
        case .objects: return objects
        case .participants: return participants
        case .lighting: return lighting
        }
    }

    func replacing(_ category: Category, with state: State) -> Self {
        Self(frameID: frameID,
             objects: category == .objects ? state : objects,
             participants: category == .participants ? state : participants,
             lighting: category == .lighting ? state : lighting)
    }

    func permits(_ action: SemanticActionType, forFrameID expectedFrameID: String) -> Bool {
        let requiredState: State
        switch action {
        case .moveObjectLeft, .moveObjectRight, .moveObjectForward, .moveObjectBack,
             .removeDistractingObject, .repositionPropForBalance:
            requiredState = objects
        case .rotateSubjectTowardLight, .moveSubjectLeft, .moveSubjectRight,
             .moveSubjectAwayFromBackground:
            requiredState = participants
        case .addFrontFillLight, .addBackgroundLight:
            requiredState = lighting
        case .shiftFrameLeft, .shiftFrameRight, .shiftFrameUp, .shiftFrameDown,
             .stepBack, .stepCloser, .lowerCamera, .raiseCamera, .changeCameraAngle,
             .levelHorizon, .removeBackgroundHotspot, .simplifyBackground,
             .waitForBackgroundClearance, .keepCurrentSetup:
            // The existing goal expansion maps simplify/hotspot to a camera
            // angle change, without changing scene objects or light sources.
            return true
        }
        return !expectedFrameID.isEmpty && frameID == expectedFrameID && requiredState == .allowed
    }
}
