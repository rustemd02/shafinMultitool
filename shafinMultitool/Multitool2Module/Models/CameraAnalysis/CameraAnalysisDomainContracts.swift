import Foundation

// MARK: - Shared Types

enum AnalysisMode: String, Codable, Sendable {
    case live
    case pause
}

enum CameraAnalysisMotionState: String, Codable, Sendable {
    case still
    case moving
    case panning
}

enum FrameVerdict: String, Codable, Sendable {
    case good
    case mixed
    case needsFix = "needs_fix"
}

struct NormalizedRect: Codable, Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = Self.clamp01(x)
        self.y = Self.clamp01(y)
        self.width = Self.clamp01(width)
        self.height = Self.clamp01(height)
    }

    var isDegenerate: Bool {
        width <= 0 || height <= 0
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct SourceState: Codable, Equatable, Sendable {
    let available: Bool
    let freshnessMs: Int?
    let confidence: Double?

    init(available: Bool, freshnessMs: Int? = nil, confidence: Double? = nil) {
        self.available = available
        self.freshnessMs = freshnessMs
        self.confidence = confidence.map(Self.clamp01)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct FeatureSourceStatus: Codable, Equatable, Sendable {
    let vision: SourceState
    let horizon: SourceState
    let lighting: SourceState
    let detr: SourceState
    let aesthetic: SourceState
}

enum TechnicalFlag: String, Codable, Sendable {
    case lowLight = "low_light"
    case highMotion = "high_motion"
    case lowSubjectConfidence = "low_subject_confidence"
    case lowSceneConfidence = "low_scene_confidence"
}

enum SubjectKind: String, Codable, Sendable {
    case face
    case person
    case object
    case group
    case unknown
}

struct SubjectCandidate: Codable, Equatable, Sendable {
    let id: String
    let kind: SubjectKind
    let label: String?
    let region: NormalizedRect?
    let confidence: Double

    init(id: String, kind: SubjectKind, label: String? = nil, region: NormalizedRect? = nil, confidence: Double) {
        self.id = id
        self.kind = kind
        self.label = label
        self.region = region
        self.confidence = Self.clamp01(confidence)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

enum AmbiguityType: String, Codable, Sendable {
    case multipleSubjectsSimilarConfidence = "multiple_subjects_similar_confidence"
    case sceneTypeTie = "scene_type_tie"
    case weakSignal = "weak_signal"
}

struct SemanticsAmbiguity: Codable, Equatable, Sendable {
    let type: AmbiguityType
    let note: String
    let candidateIds: [String]
}

struct SemanticsAssumption: Codable, Equatable, Sendable {
    let id: String
    let text: String
    let confidence: Double

    init(id: String, text: String, confidence: Double) {
        self.id = id
        self.text = text
        self.confidence = Self.clamp01(confidence)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct CritiqueSummary: Codable, Equatable, Sendable {
    let shortVerdict: String
    let whyGood: String?
    let whyProblematic: String?
}

enum EvidenceSource: String, Codable, Sendable {
    case snapshot
    case semantics
    case derivedRule = "derived_rule"
}

struct EvidenceRef: Codable, Equatable, Sendable {
    let source: EvidenceSource
    let key: String
    let value: String
    let confidence: Double?

    init(source: EvidenceSource, key: String, value: String, confidence: Double? = nil) {
        self.source = source
        self.key = key
        self.value = value
        self.confidence = confidence.map(Self.clamp01)
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

enum FixTypeV1: String, Codable, Sendable {
    case reframing
    case lightingAdjustment = "lighting_adjustment"
    case angleAdjustment = "angle_adjustment"
    case horizonCorrection = "horizon_correction"
    case keepAsIs = "keep_as_is"
}

struct ActionGuardrail: Codable, Equatable, Sendable {
    let requiresStillCamera: Bool
    let minConfidence: Double
    let suppressWhenMoving: Bool

    init(requiresStillCamera: Bool, minConfidence: Double, suppressWhenMoving: Bool) {
        self.requiresStillCamera = requiresStillCamera
        self.minConfidence = Self.clamp01(minConfidence)
        self.suppressWhenMoving = suppressWhenMoving
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

enum OverlayKind: String, Codable, Sendable {
    case arrow
    case regionHighlight = "region_highlight"
    case horizonLine = "horizon_line"
}

enum OverlayDirection: String, Codable, Sendable {
    case left
    case right
    case up
    case down
}

struct OverlayHint: Codable, Equatable, Sendable {
    let kind: OverlayKind
    let targetRegion: NormalizedRect?
    let direction: OverlayDirection?
}

// MARK: - Contract 1: FrameFeatureSnapshot

struct FrameFeatureSnapshot: Codable, Equatable, Sendable {
    struct CompositionFeatures: Codable, Equatable, Sendable {
        let horizontalOffset: Double
        let verticalOffset: Double
        let subjectAreaRatio: Double
        let saliencyLeftRightBalance: Double
        let saliencyTopBottomBalance: Double

        init(horizontalOffset: Double,
             verticalOffset: Double,
             subjectAreaRatio: Double,
             saliencyLeftRightBalance: Double,
             saliencyTopBottomBalance: Double) {
            self.horizontalOffset = Self.clamp11(horizontalOffset)
            self.verticalOffset = Self.clamp11(verticalOffset)
            self.subjectAreaRatio = Self.clamp01(subjectAreaRatio)
            self.saliencyLeftRightBalance = Self.clamp11(saliencyLeftRightBalance)
            self.saliencyTopBottomBalance = Self.clamp11(saliencyTopBottomBalance)
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }

        private static func clamp11(_ value: Double) -> Double {
            min(1.0, max(-1.0, value))
        }
    }

    struct SubjectSignals: Codable, Equatable, Sendable {
        let faceDetected: Bool
        let personDetected: Bool
        let personCount: Int
        let topObjectLabel: String?
        let topObjectConfidence: Double?
        let primaryCandidateRegion: NormalizedRect?
        let primaryCandidateConfidence: Double?

        init(faceDetected: Bool,
             personDetected: Bool,
             personCount: Int,
             topObjectLabel: String? = nil,
             topObjectConfidence: Double? = nil,
             primaryCandidateRegion: NormalizedRect? = nil,
             primaryCandidateConfidence: Double? = nil) {
            self.faceDetected = faceDetected
            self.personDetected = personDetected
            self.personCount = max(0, personCount)
            self.topObjectLabel = topObjectLabel
            self.topObjectConfidence = topObjectConfidence.map(Self.clamp01)
            self.primaryCandidateRegion = primaryCandidateRegion
            self.primaryCandidateConfidence = primaryCandidateConfidence.map(Self.clamp01)
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }
    }

    struct HorizonFeatures: Codable, Equatable, Sendable {
        let angleDegrees: Double
        let confidence: Double

        init(angleDegrees: Double, confidence: Double) {
            self.angleDegrees = angleDegrees
            self.confidence = Self.clamp01(confidence)
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }
    }

    struct LightingFeatures: Codable, Equatable, Sendable {
        let exposureBiasHint: Double
        let backlightIndex: Double
        let keyToFillRatio: Double?

        init(exposureBiasHint: Double, backlightIndex: Double, keyToFillRatio: Double?) {
            self.exposureBiasHint = exposureBiasHint
            self.backlightIndex = Self.clamp01(backlightIndex)
            self.keyToFillRatio = keyToFillRatio
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }
    }

    struct MotionFeatures: Codable, Equatable, Sendable {
        let state: CameraAnalysisMotionState
        let shakeLevel: Double

        init(state: CameraAnalysisMotionState, shakeLevel: Double) {
            self.state = state
            self.shakeLevel = Self.clamp01(shakeLevel)
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }
    }

    struct AestheticFeatures: Codable, Equatable, Sendable {
        let score: Double?
        let scoreConfidence: Double?

        init(score: Double? = nil, scoreConfidence: Double? = nil) {
            self.score = score.map(Self.clamp01)
            self.scoreConfidence = scoreConfidence.map(Self.clamp01)
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }
    }

    struct ObjectDetectionsSummary: Codable, Equatable, Sendable {
        let totalCount: Int
        let topKLabels: [String]

        init(totalCount: Int, topKLabels: [String]) {
            self.totalCount = max(0, totalCount)
            self.topKLabels = topKLabels
        }
    }

    let frameId: String
    let mode: AnalysisMode
    let capturedAt: Date
    let sources: FeatureSourceStatus
    let composition: CompositionFeatures
    let subjectSignals: SubjectSignals
    let horizon: HorizonFeatures
    let lighting: LightingFeatures
    let motion: MotionFeatures
    let aesthetics: AestheticFeatures
    let objects: ObjectDetectionsSummary
    let technicalFlags: [TechnicalFlag]

    func validate() -> [String] {
        var errors: [String] = []

        if frameId.isEmpty {
            errors.append("frameId must be non-empty")
        }

        if subjectSignals.faceDetected && !subjectSignals.personDetected {
            errors.append("faceDetected implies personDetected")
        }

        return errors
    }
}

// MARK: - Contract 2: SceneSemanticsReport

enum SceneTypeV1: String, Codable, Sendable {
    case dialogueCloseup = "dialogue_closeup"
    case singleCharacterMedium = "single_character_medium"
    case twoCharacterFrame = "two_character_frame"
    case objectInsert = "object_insert"
    case establishingLikeFrame = "establishing_like_frame"
    case moodyBacklitSubject = "moody_backlit_subject"
    case unknown
}

struct SceneSemanticsReport: Codable, Equatable, Sendable {
    struct PrimarySubject: Codable, Equatable, Sendable {
        let kind: SubjectKind
        let label: String?
        let region: NormalizedRect?
        let confidence: Double
        let competingCandidates: [SubjectCandidate]

        init(kind: SubjectKind,
             label: String? = nil,
             region: NormalizedRect? = nil,
             confidence: Double,
             competingCandidates: [SubjectCandidate] = []) {
            self.kind = kind
            self.label = label
            self.region = region
            self.confidence = Self.clamp01(confidence)
            self.competingCandidates = competingCandidates
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }
    }

    struct VisualDominanceState: Codable, Equatable, Sendable {
        let hasClearFocus: Bool
        let focusCompetitionScore: Double
        let backgroundClutterScore: Double

        init(hasClearFocus: Bool, focusCompetitionScore: Double, backgroundClutterScore: Double) {
            self.hasClearFocus = hasClearFocus
            self.focusCompetitionScore = Self.clamp01(focusCompetitionScore)
            self.backgroundClutterScore = Self.clamp01(backgroundClutterScore)
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }
    }

    struct SemanticReadabilityState: Codable, Equatable, Sendable {
        let subjectReadable: Bool
        let lookSpaceAdequate: Bool?
        let edgePressureScore: Double
        let separationScore: Double

        init(subjectReadable: Bool, lookSpaceAdequate: Bool?, edgePressureScore: Double, separationScore: Double) {
            self.subjectReadable = subjectReadable
            self.lookSpaceAdequate = lookSpaceAdequate
            self.edgePressureScore = Self.clamp01(edgePressureScore)
            self.separationScore = Self.clamp01(separationScore)
        }

        private static func clamp01(_ value: Double) -> Double {
            min(1.0, max(0.0, value))
        }
    }

    let frameId: String
    let mode: AnalysisMode
    let sceneType: SceneTypeV1
    let sceneTypeConfidence: Double
    let primarySubject: PrimarySubject
    let dominance: VisualDominanceState
    let readability: SemanticReadabilityState
    let ambiguities: [SemanticsAmbiguity]
    let assumptions: [SemanticsAssumption]

    init(frameId: String,
         mode: AnalysisMode,
         sceneType: SceneTypeV1,
         sceneTypeConfidence: Double,
         primarySubject: PrimarySubject,
         dominance: VisualDominanceState,
         readability: SemanticReadabilityState,
         ambiguities: [SemanticsAmbiguity],
         assumptions: [SemanticsAssumption]) {
        self.frameId = frameId
        self.mode = mode
        self.sceneType = sceneType
        self.sceneTypeConfidence = Self.clamp01(sceneTypeConfidence)
        self.primarySubject = primarySubject
        self.dominance = dominance
        self.readability = readability
        self.ambiguities = ambiguities
        self.assumptions = assumptions
    }

    func validate(expectedFrameId: String? = nil) -> [String] {
        var errors: [String] = []

        if let expectedFrameId, expectedFrameId != frameId {
            errors.append("sceneSemantics.frameId must match snapshot.frameId")
        }

        if primarySubject.confidence < 0.2 && primarySubject.kind != .unknown {
            errors.append("low-confidence subject must use kind=unknown")
        }

        if dominance.hasClearFocus && dominance.focusCompetitionScore > 0.8 {
            errors.append("hasClearFocus conflicts with focusCompetitionScore > 0.8")
        }

        return errors
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

// MARK: - Contract 3: CritiqueReport

enum IssueTypeV1: String, Codable, Sendable {
    case subjectTooCloseToEdge = "subject_too_close_to_edge"
    case subjectNotProminentEnough = "subject_not_prominent_enough"
    case backgroundCompetesWithSubject = "background_competes_with_subject"
    case insufficientLookSpace = "insufficient_look_space"
    case backlightHidesSubject = "backlight_hides_subject"
    case sceneHasNoClearFocus = "scene_has_no_clear_focus"
    case frameVisuallyOverloaded = "frame_visually_overloaded"
    case horizonDistracts = "horizon_distracts"
}

enum StrengthTypeV1: String, Codable, Sendable {
    case goodSubjectIsolation = "good_subject_isolation"
    case goodLightEmphasis = "good_light_emphasis"
    case clearFocusHierarchy = "clear_focus_hierarchy"
    case stableHorizonSupportsScene = "stable_horizon_supports_scene"
    case balancedCompositionForScene = "balanced_composition_for_scene"
}

struct FrameIssue: Codable, Equatable, Sendable {
    let id: String
    let type: IssueTypeV1
    let severity: Double
    let confidence: Double
    let rationale: String
    let evidence: [EvidenceRef]
    let affectedRegion: NormalizedRect?
    let suggestedFixTypes: [FixTypeV1]

    init(id: String,
         type: IssueTypeV1,
         severity: Double,
         confidence: Double,
         rationale: String,
         evidence: [EvidenceRef],
         affectedRegion: NormalizedRect? = nil,
         suggestedFixTypes: [FixTypeV1] = []) {
        self.id = id
        self.type = type
        self.severity = Self.clamp01(severity)
        self.confidence = Self.clamp01(confidence)
        self.rationale = rationale
        self.evidence = evidence
        self.affectedRegion = affectedRegion
        self.suggestedFixTypes = suggestedFixTypes
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct FrameStrength: Codable, Equatable, Sendable {
    let id: String
    let type: StrengthTypeV1
    let confidence: Double
    let rationale: String
    let evidence: [EvidenceRef]
    let supportingRegion: NormalizedRect?

    init(id: String,
         type: StrengthTypeV1,
         confidence: Double,
         rationale: String,
         evidence: [EvidenceRef],
         supportingRegion: NormalizedRect? = nil) {
        self.id = id
        self.type = type
        self.confidence = Self.clamp01(confidence)
        self.rationale = rationale
        self.evidence = evidence
        self.supportingRegion = supportingRegion
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct CritiqueReport: Codable, Equatable, Sendable {
    static let criticalIssueThreshold = 0.65

    let frameId: String
    let mode: AnalysisMode
    let verdict: FrameVerdict
    let verdictConfidence: Double
    let strengths: [FrameStrength]
    let issues: [FrameIssue]
    let summary: CritiqueSummary
    let traceRefs: [String]
    let fallbackUsed: Bool

    init(frameId: String,
         mode: AnalysisMode,
         verdict: FrameVerdict,
         verdictConfidence: Double,
         strengths: [FrameStrength],
         issues: [FrameIssue],
         summary: CritiqueSummary,
         traceRefs: [String],
         fallbackUsed: Bool) {
        self.frameId = frameId
        self.mode = mode
        self.verdict = verdict
        self.verdictConfidence = Self.clamp01(verdictConfidence)
        self.strengths = strengths
        self.issues = issues
        self.summary = summary
        self.traceRefs = traceRefs
        self.fallbackUsed = fallbackUsed
    }

    func validate(expectedFrameId: String? = nil) -> [String] {
        var errors: [String] = []

        if let expectedFrameId, expectedFrameId != frameId {
            errors.append("critique.frameId must match snapshot.frameId")
        }

        let hasCriticalIssue = issues.contains(where: { $0.severity >= Self.criticalIssueThreshold })
        if verdict == .good && hasCriticalIssue {
            errors.append("good verdict cannot have critical issues")
        }

        if issues.contains(where: { $0.evidence.isEmpty }) {
            errors.append("every issue must contain at least one evidence item")
        }

        return errors
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

// MARK: - Contract 4: RecommendationPlan

enum ActionTypeV1: String, Codable, Sendable {
    case moveFrameLeft = "move_frame_left"
    case moveFrameRight = "move_frame_right"
    case moveFrameUp = "move_frame_up"
    case moveFrameDown = "move_frame_down"
    case increaseSubjectSize = "increase_subject_size"
    case reduceBackgroundDistractions = "reduce_background_distractions"
    case changeAngle = "change_angle"
    case improveFrontLight = "improve_front_light"
    case levelHorizon = "level_horizon"
    case leaveFrameAsIs = "leave_frame_as_is"
}

struct RecommendationAction: Codable, Equatable, Sendable {
    let id: String
    let actionType: ActionTypeV1
    let priority: Int
    let targetRegion: NormalizedRect?
    let linkedIssueIds: [String]
    let expectedOutcome: String
    let guardrail: ActionGuardrail
    let overlayHint: OverlayHint?
}

struct RecommendationPlan: Codable, Equatable, Sendable {
    let frameId: String
    let mode: AnalysisMode
    let inputVerdict: FrameVerdict
    let primaryAction: RecommendationAction?
    let secondaryActions: [RecommendationAction]
    let deferredActions: [RecommendationAction]
    let noChangeRationale: String?
    let planConfidence: Double

    init(frameId: String,
         mode: AnalysisMode,
         inputVerdict: FrameVerdict,
         primaryAction: RecommendationAction?,
         secondaryActions: [RecommendationAction],
         deferredActions: [RecommendationAction],
         noChangeRationale: String?,
         planConfidence: Double) {
        self.frameId = frameId
        self.mode = mode
        self.inputVerdict = inputVerdict
        self.primaryAction = primaryAction
        self.secondaryActions = secondaryActions
        self.deferredActions = deferredActions
        self.noChangeRationale = noChangeRationale
        self.planConfidence = Self.clamp01(planConfidence)
    }

    func validate(expectedFrameId: String? = nil, availableIssueIds: Set<String> = []) -> [String] {
        var errors: [String] = []

        if let expectedFrameId, expectedFrameId != frameId {
            errors.append("plan.frameId must match snapshot.frameId")
        }

        if mode == .live && secondaryActions.count > 0 {
            errors.append("live mode allows primary action only")
        }

        if inputVerdict == .good {
            let isLeaveAsIs = primaryAction?.actionType == .leaveFrameAsIs
            if primaryAction != nil && !isLeaveAsIs {
                errors.append("good verdict should use leave_frame_as_is or nil primary action")
            }
        }

        let primaryAndSecondary = [primaryAction].compactMap { $0 } + secondaryActions
        let allActions = primaryAndSecondary + deferredActions
        let priorities = primaryAndSecondary.map(\.priority)
        if Set(priorities).count != priorities.count {
            errors.append("action priorities must be unique for primary+secondary")
        }

        if hasConflictingActions(allActions) {
            errors.append("plan contains conflicting directional actions")
        }

        for action in allActions where action.actionType != .leaveFrameAsIs {
            if action.linkedIssueIds.isEmpty {
                errors.append("non-leave actions must link at least one issue")
            }
        }

        if !availableIssueIds.isEmpty {
            let unknownLinks = allActions
                .flatMap(\.linkedIssueIds)
                .filter { !availableIssueIds.contains($0) }
            if !unknownLinks.isEmpty {
                errors.append("plan links unknown issue IDs: \(Array(Set(unknownLinks)).sorted())")
            }
        }

        return errors
    }

    private func hasConflictingActions(_ actions: [RecommendationAction]) -> Bool {
        let types = Set(actions.map(\.actionType))
        return (types.contains(.moveFrameLeft) && types.contains(.moveFrameRight))
            || (types.contains(.moveFrameUp) && types.contains(.moveFrameDown))
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}
