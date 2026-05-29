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
        guard value.isFinite else { return 0.0 }
        return min(1.0, max(0.0, value))
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

enum TechnicalQualityIssueType: String, Codable, Sendable {
    case motionBlur = "motion_blur"
    case defocus
    case overexposure
    case underexposure
    case noise
    case occlusion
    case lensSmudge = "lens_smudge"
}

enum TechnicalQualityActionType: String, Codable, Sendable {
    case stabilizeCamera = "stabilize_camera"
    case refocusSubject = "refocus_subject"
    case reduceExposure = "reduce_exposure"
    case increaseExposure = "increase_exposure"
    case avoidOcclusion = "avoid_occlusion"
    case cleanLens = "clean_lens"
    case reduceIsoNoise = "reduce_iso_noise"
}

struct TechnicalQualityIssueSignal: Codable, Equatable, Sendable {
    let type: TechnicalQualityIssueType
    let actionType: TechnicalQualityActionType
    let confidence: Double
    let severity: Double
    let isDominant: Bool

    init(type: TechnicalQualityIssueType,
         actionType: TechnicalQualityActionType,
         confidence: Double,
         severity: Double,
         isDominant: Bool = false) {
        self.type = type
        self.actionType = actionType
        self.confidence = Self.clamp01(confidence)
        self.severity = Self.clamp01(severity)
        self.isDominant = isDominant
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct TechnicalQualitySignal: Codable, Equatable, Sendable {
    let issues: [TechnicalQualityIssueSignal]

    init(issues: [TechnicalQualityIssueSignal]) {
        self.issues = issues
    }

    var futureActionIds: [String] {
        uniqueActionIds(issues.map { $0.actionType.rawValue })
    }

    var dominantFutureActionIds: [String] {
        uniqueActionIds(issues.filter(\.isDominant).map { $0.actionType.rawValue })
    }

    static let empty = TechnicalQualitySignal(issues: [])

    private func uniqueActionIds(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where seen.insert(value).inserted {
            result.append(value)
        }
        return result
    }
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
    let id: String
    let shortVerdict: String
    let whyGood: String?
    let whyProblematic: String?

    init(id: String, shortVerdict: String, whyGood: String? = nil, whyProblematic: String? = nil) {
        self.id = id
        self.shortVerdict = shortVerdict
        self.whyGood = whyGood
        self.whyProblematic = whyProblematic
    }
}

enum EvidenceSource: String, Codable, Sendable {
    case snapshot
    case semantics
    case derivedRule = "derived_rule"
    case neuralEvidence = "neural_evidence"
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
    case leaveFrameAsIs = "leave_frame_as_is"
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
    let id: String
    let kind: OverlayKind
    let targetRegion: NormalizedRect?
    let direction: OverlayDirection?

    init(id: String, kind: OverlayKind, targetRegion: NormalizedRect? = nil, direction: OverlayDirection? = nil) {
        self.id = id
        self.kind = kind
        self.targetRegion = targetRegion
        self.direction = direction
    }
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

enum IssueTypeV1: String, Codable, CaseIterable, Sendable {
    case subjectTooCloseToEdge = "subject_too_close_to_edge"
    case subjectNotProminentEnough = "subject_not_prominent_enough"
    case backgroundCompetesWithSubject = "background_competes_with_subject"
    case insufficientLookSpace = "insufficient_look_space"
    case backlightHidesSubject = "backlight_hides_subject"
    case sceneHasNoClearFocus = "scene_has_no_clear_focus"
    case frameVisuallyOverloaded = "frame_visually_overloaded"
    case horizonDistracts = "horizon_distracts"
}

enum StrengthTypeV1: String, Codable, CaseIterable, Sendable {
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

        if summary.id.isEmpty {
            errors.append("summary.id must be non-empty")
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

enum ActionTypeV1: String, Codable, CaseIterable, Sendable {
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

        if allActions.contains(where: { $0.overlayHint?.id.isEmpty == true }) {
            errors.append("overlayHint.id must be non-empty when overlayHint is present")
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

// MARK: - Contract H06: Neural Evidence

enum EvidenceHeadStatus: String, Codable, CaseIterable, Sendable {
    case available
    case notApplicable = "not_applicable"
    case unavailable
}

enum EvidenceHeadId: String, Codable, CaseIterable, Sendable {
    case subjectProminence = "subject_prominence"
    case backgroundClutter = "background_clutter"
    case lightingQuality = "lighting_quality"
    case faceSaliency = "face_saliency"
    case balanceConfidence = "balance_confidence"
    case depthSeparation = "depth_separation"
    case cinematicExpressiveness = "cinematic_expressiveness"
    case shotTypeConfidence = "shot_type_confidence"
}

enum EvidenceCategoryId: String, Codable, CaseIterable, Sendable {
    case dialogueCloseupAffinity = "dialogue_closeup_affinity"
    case singleCharacterMediumAffinity = "single_character_medium_affinity"
    case twoCharacterFrameAffinity = "two_character_frame_affinity"
    case objectInsertAffinity = "object_insert_affinity"
    case establishingLikeFrameAffinity = "establishing_like_frame_affinity"
    case moodyBacklitSubjectAffinity = "moody_backlit_subject_affinity"
    case unknownAffinity = "unknown_affinity"
}

enum SupportingSignalTag: String, Codable, CaseIterable, Sendable {
    case subjectScale = "subject_scale"
    case subjectAttentionPull = "subject_attention_pull"
    case subjectReadability = "subject_readability"
    case objectDensity = "object_density"
    case textureNoise = "texture_noise"
    case attentionCompetition = "attention_competition"
    case subjectExposureReadability = "subject_exposure_readability"
    case facialLightSupport = "facial_light_support"
    case tonalStructure = "tonal_structure"
    case faceAttentionPull = "face_attention_pull"
    case eyeRegionVisibility = "eye_region_visibility"
    case facialAnchorStrength = "facial_anchor_strength"
    case frameBalance = "frame_balance"
    case subjectPlacementStability = "subject_placement_stability"
    case negativeSpaceFit = "negative_space_fit"
    case foregroundBackgroundSplit = "foreground_background_split"
    case subjectBackgroundContrast = "subject_background_contrast"
    case layeringClarity = "layering_clarity"
    case stylisticIntent = "stylistic_intent"
    case productionValueResidual = "production_value_residual"
    case visualHarmonyResidual = "visual_harmony_residual"
}

struct EvidenceCategoryScore: Codable, Equatable, Sendable {
    let categoryId: EvidenceCategoryId
    let score: Double

    init(categoryId: EvidenceCategoryId, score: Double) {
        self.categoryId = categoryId
        self.score = Self.clamp01(score)
    }

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(1.0, max(0.0, value))
    }
}

struct ScalarEvidenceHeadOutput: Codable, Equatable, Sendable {
    let headId: EvidenceHeadId
    let status: EvidenceHeadStatus
    let score: Double?
    let confidence: Double
    let mode: AnalysisMode
    let supportingSignals: [SupportingSignalTag]

    init(headId: EvidenceHeadId,
         status: EvidenceHeadStatus,
         score: Double?,
         confidence: Double,
         mode: AnalysisMode,
         supportingSignals: [SupportingSignalTag]) {
        self.headId = headId
        self.status = status
        self.score = score.map(Self.clamp01)
        self.confidence = Self.clamp01(confidence)
        self.mode = mode
        self.supportingSignals = supportingSignals
    }

    private enum CodingKeys: String, CodingKey {
        case headId
        case status
        case score
        case confidence
        case mode
        case supportingSignals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headId = try container.decode(EvidenceHeadId.self, forKey: .headId)
        status = try container.decode(EvidenceHeadStatus.self, forKey: .status)
        score = try container.decodeIfPresent(Double.self, forKey: .score).map(Self.clamp01)
        confidence = Self.clamp01(try container.decode(Double.self, forKey: .confidence))
        mode = try container.decode(AnalysisMode.self, forKey: .mode)
        supportingSignals = try container.decode([SupportingSignalTag].self, forKey: .supportingSignals)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(headId, forKey: .headId)
        try container.encode(status, forKey: .status)
        if let score {
            try container.encode(score, forKey: .score)
        } else {
            try container.encodeNil(forKey: .score)
        }
        try container.encode(confidence, forKey: .confidence)
        try container.encode(mode, forKey: .mode)
        try container.encode(Self.sortTags(supportingSignals), forKey: .supportingSignals)
    }

    fileprivate static func sortTags(_ tags: [SupportingSignalTag]) -> [SupportingSignalTag] {
        tags.sorted { lhs, rhs in
            SupportingSignalTag.canonicalIndex(of: lhs) < SupportingSignalTag.canonicalIndex(of: rhs)
        }
    }

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(1.0, max(0.0, value))
    }
}

struct CategoricalEvidenceHeadOutput: Codable, Equatable, Sendable {
    let headId: EvidenceHeadId
    let status: EvidenceHeadStatus
    let affinities: [EvidenceCategoryScore]
    let confidence: Double
    let mode: AnalysisMode
    let supportingSignals: [SupportingSignalTag]

    init(headId: EvidenceHeadId,
         status: EvidenceHeadStatus,
         affinities: [EvidenceCategoryScore],
         confidence: Double,
         mode: AnalysisMode,
         supportingSignals: [SupportingSignalTag]) {
        self.headId = headId
        self.status = status
        self.affinities = affinities
        self.confidence = Self.clamp01(confidence)
        self.mode = mode
        self.supportingSignals = supportingSignals
    }

    private enum CodingKeys: String, CodingKey {
        case headId
        case status
        case affinities
        case confidence
        case mode
        case supportingSignals
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        headId = try container.decode(EvidenceHeadId.self, forKey: .headId)
        status = try container.decode(EvidenceHeadStatus.self, forKey: .status)
        affinities = try container.decode([EvidenceCategoryScore].self, forKey: .affinities)
        confidence = Self.clamp01(try container.decode(Double.self, forKey: .confidence))
        mode = try container.decode(AnalysisMode.self, forKey: .mode)
        supportingSignals = try container.decode([SupportingSignalTag].self, forKey: .supportingSignals)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(headId, forKey: .headId)
        try container.encode(status, forKey: .status)
        try container.encode(Self.sortAffinities(affinities), forKey: .affinities)
        try container.encode(confidence, forKey: .confidence)
        try container.encode(mode, forKey: .mode)
        try container.encode(ScalarEvidenceHeadOutput.sortTags(supportingSignals), forKey: .supportingSignals)
    }

    fileprivate static func sortAffinities(_ affinities: [EvidenceCategoryScore]) -> [EvidenceCategoryScore] {
        affinities.sorted { lhs, rhs in
            EvidenceCategoryId.canonicalIndex(of: lhs.categoryId) < EvidenceCategoryId.canonicalIndex(of: rhs.categoryId)
        }
    }

    private static func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(1.0, max(0.0, value))
    }
}

enum NeuralEvidenceHeadPayload: Equatable, Sendable {
    case scalar(ScalarEvidenceHeadOutput)
    case categorical(CategoricalEvidenceHeadOutput)

    var headId: EvidenceHeadId {
        switch self {
        case let .scalar(payload):
            return payload.headId
        case let .categorical(payload):
            return payload.headId
        }
    }

    var mode: AnalysisMode {
        switch self {
        case let .scalar(payload):
            return payload.mode
        case let .categorical(payload):
            return payload.mode
        }
    }

    var status: EvidenceHeadStatus {
        switch self {
        case let .scalar(payload):
            return payload.status
        case let .categorical(payload):
            return payload.status
        }
    }
}

extension NeuralEvidenceHeadPayload: Codable {
    private enum CodingKeys: String, CodingKey {
        case headId
        case affinities
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let headId = try container.decode(EvidenceHeadId.self, forKey: .headId)
        if headId == .shotTypeConfidence || container.contains(.affinities) {
            self = .categorical(try CategoricalEvidenceHeadOutput(from: decoder))
        } else {
            self = .scalar(try ScalarEvidenceHeadOutput(from: decoder))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .scalar(payload):
            try payload.encode(to: encoder)
        case let .categorical(payload):
            try payload.encode(to: encoder)
        }
    }
}

struct NeuralEvidenceHeadEntry: Codable, Equatable, Sendable {
    let headId: EvidenceHeadId
    let payload: NeuralEvidenceHeadPayload

    init(headId: EvidenceHeadId, payload: NeuralEvidenceHeadPayload) {
        self.headId = headId
        self.payload = payload
    }
}

struct NeuralEvidenceSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = "h1"

    let schemaVersion: String
    let frameId: String
    let mode: AnalysisMode
    let capturedAt: Date
    let bundleVersion: String
    let headOutputs: [NeuralEvidenceHeadEntry]

    init(schemaVersion: String,
         frameId: String,
         mode: AnalysisMode,
         capturedAt: Date,
         bundleVersion: String,
         headOutputs: [NeuralEvidenceHeadEntry]) {
        self.schemaVersion = schemaVersion
        self.frameId = frameId
        self.mode = mode
        self.capturedAt = capturedAt
        self.bundleVersion = bundleVersion
        self.headOutputs = headOutputs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case frameId
        case mode
        case capturedAt
        case bundleVersion
        case headOutputs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        frameId = try container.decode(String.self, forKey: .frameId)
        mode = try container.decode(AnalysisMode.self, forKey: .mode)
        capturedAt = try container.decodeISO8601Date(forKey: .capturedAt)
        bundleVersion = try container.decode(String.self, forKey: .bundleVersion)
        headOutputs = try container.decode([NeuralEvidenceHeadEntry].self, forKey: .headOutputs)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(frameId, forKey: .frameId)
        try container.encode(mode, forKey: .mode)
        try container.encodeISO8601Date(capturedAt, forKey: .capturedAt)
        try container.encode(bundleVersion, forKey: .bundleVersion)
        try container.encode(Self.sortEntries(headOutputs), forKey: .headOutputs)
    }

    func validate(expectedFrameId: String? = nil,
                  semanticsReport: SceneSemanticsReport? = nil,
                  runtimeMetadata: NeuralEvidenceRuntimeMetadata? = nil) -> [String] {
        var errors: [String] = []

        if schemaVersion.isEmpty {
            errors.append("neuralEvidence.schemaVersion must be non-empty")
        } else if schemaVersion != Self.currentSchemaVersion {
            errors.append("neuralEvidence.schemaVersion must be \(Self.currentSchemaVersion)")
        }

        if frameId.isEmpty {
            errors.append("neuralEvidence.frameId must be non-empty")
        }

        if bundleVersion.isEmpty {
            errors.append("neuralEvidence.bundleVersion must be non-empty")
        }

        if let expectedFrameId, expectedFrameId != frameId {
            errors.append("neuralEvidence.frameId must match snapshot.frameId")
        }

        if let semanticsReport {
            if semanticsReport.frameId != frameId || semanticsReport.mode != mode {
                errors.append("neuralEvidence must match semantics.frameId+mode")
            }
        }

        if let runtimeMetadata {
            errors.append(contentsOf: runtimeMetadata.validate(against: self))
        }

        if headOutputs.count != EvidenceHeadId.allCases.count {
            errors.append("neuralEvidence.headOutputs must contain exactly \(EvidenceHeadId.allCases.count) entries")
        }

        let counts = Dictionary(grouping: headOutputs, by: \.headId).mapValues(\.count)
        let missing = EvidenceHeadId.allCases.filter { counts[$0] == nil }
        if !missing.isEmpty {
            errors.append("neuralEvidence is missing head IDs: \(missing.map(\.rawValue).joined(separator: ", "))")
        }

        let duplicates = counts.filter { $0.value > 1 }.keys.sorted { $0.rawValue < $1.rawValue }
        if !duplicates.isEmpty {
            errors.append("neuralEvidence contains duplicate head IDs: \(duplicates.map(\.rawValue).joined(separator: ", "))")
        }

        let actualOrder = headOutputs.map(\.headId)
        let canonicalOrder = EvidenceHeadId.allCases
        if actualOrder != canonicalOrder {
            errors.append("neuralEvidence.headOutputs must use canonical head ordering")
        }

        for entry in headOutputs {
            if entry.payload.headId != entry.headId {
                errors.append("payload.headId must match head entry id for \(entry.headId.rawValue)")
            }

            if entry.payload.mode != mode {
                errors.append("payload.mode must match snapshot.mode for \(entry.headId.rawValue)")
            }

            switch entry.payload {
            case let .scalar(payload):
                errors.append(contentsOf: validateScalarPayload(payload, semanticsReport: semanticsReport))
            case let .categorical(payload):
                errors.append(contentsOf: validateCategoricalPayload(payload))
            }
        }

        return errors
    }

    private func validateScalarPayload(_ payload: ScalarEvidenceHeadOutput,
                                       semanticsReport: SceneSemanticsReport?) -> [String] {
        var errors: [String] = []

        if payload.headId == .shotTypeConfidence {
            errors.append("shot_type_confidence must use categorical payload")
        }

        if payload.supportingSignals.count > 2 {
            errors.append("\(payload.headId.rawValue) supportingSignals must contain at most 2 tags")
        }

        if hasDuplicateTags(payload.supportingSignals) {
            errors.append("\(payload.headId.rawValue) supportingSignals must not contain duplicates")
        }

        if payload.supportingSignals != payload.supportingSignals.sorted(by: {
            SupportingSignalTag.canonicalIndex(of: $0) < SupportingSignalTag.canonicalIndex(of: $1)
        }) {
            errors.append("\(payload.headId.rawValue) supportingSignals must use canonical tag ordering")
        }

        let allowedTags = payload.headId.allowedSupportingSignals
        if payload.supportingSignals.contains(where: { !allowedTags.contains($0) }) {
            errors.append("\(payload.headId.rawValue) supportingSignals contain tags outside allowed vocabulary")
        }

        switch payload.status {
        case .available:
            if payload.score == nil {
                errors.append("\(payload.headId.rawValue) available scalar payload must include score")
            }
        case .notApplicable, .unavailable:
            if payload.score != nil {
                errors.append("\(payload.headId.rawValue) non-available scalar payload must not include score")
            }
            if payload.confidence != 0.0 {
                errors.append("\(payload.headId.rawValue) non-available scalar payload must use confidence=0")
            }
        }

        if let modeError = validateStatusPolicy(for: payload.headId, status: payload.status, semanticsReport: semanticsReport) {
            errors.append(modeError)
        }

        return errors
    }

    private func validateCategoricalPayload(_ payload: CategoricalEvidenceHeadOutput) -> [String] {
        var errors: [String] = []

        if payload.headId != .shotTypeConfidence {
            errors.append("\(payload.headId.rawValue) must use scalar payload")
        }

        if !payload.supportingSignals.isEmpty {
            errors.append("shot_type_confidence supportingSignals must be empty")
        }

        switch payload.status {
        case .available:
            let categories = payload.affinities.map(\.categoryId)
            if categories != EvidenceCategoryId.allCases {
                errors.append("shot_type_confidence affinities must use complete canonical category ordering")
            }
        case .notApplicable, .unavailable:
            if !payload.affinities.isEmpty {
                errors.append("shot_type_confidence non-available payload must use empty affinities")
            }
            if payload.confidence != 0.0 {
                errors.append("shot_type_confidence non-available payload must use confidence=0")
            }
        }

        if hasDuplicateCategories(payload.affinities) {
            errors.append("shot_type_confidence affinities must not contain duplicate categories")
        }

        if let modeError = validateStatusPolicy(for: payload.headId, status: payload.status, semanticsReport: nil) {
            errors.append(modeError)
        }

        return errors
    }

    private func validateStatusPolicy(for headId: EvidenceHeadId,
                                      status: EvidenceHeadStatus,
                                      semanticsReport: SceneSemanticsReport?) -> String? {
        switch headId {
        case .balanceConfidence, .depthSeparation, .cinematicExpressiveness, .shotTypeConfidence:
            if mode == .live && status != .notApplicable {
                return "\(headId.rawValue) must be not_applicable in live mode"
            }
        case .faceSaliency:
            guard let semanticsReport else {
                if status != .unavailable {
                    return "face_saliency must be unavailable when deterministic semantics are missing"
                }
                return nil
            }
            let personCentricKinds: Set<SubjectKind> = [.face, .person, .group]
            if personCentricKinds.contains(semanticsReport.primarySubject.kind) {
                if status == .notApplicable {
                    return "face_saliency must not be not_applicable for person-centric semantics"
                }
            } else if status != .notApplicable {
                return "face_saliency must be not_applicable when semantics primarySubject is object or unknown"
            }
        default:
            break
        }

        return nil
    }

    private static func sortEntries(_ entries: [NeuralEvidenceHeadEntry]) -> [NeuralEvidenceHeadEntry] {
        entries.sorted { lhs, rhs in
            EvidenceHeadId.canonicalIndex(of: lhs.headId) < EvidenceHeadId.canonicalIndex(of: rhs.headId)
        }
    }

    private func hasDuplicateTags(_ tags: [SupportingSignalTag]) -> Bool {
        Set(tags).count != tags.count
    }

    private func hasDuplicateCategories(_ affinities: [EvidenceCategoryScore]) -> Bool {
        let categories = affinities.map(\.categoryId)
        return Set(categories).count != categories.count
    }
}

enum NeuralEvidenceProviderKind: String, Codable, Sendable {
    case coremlLocal = "coreml_local"
    case mock
    case remoteTeacher = "remote_teacher"
}

enum InferenceTargetKind: String, Codable, Sendable {
    case onDevice = "on_device"
    case offloaded
}

enum NeuralEvidenceROIStrategy: String, Codable, Sendable {
    case fullFrameOnly = "full_frame_only"
    case fullFramePlusSubjectCrop = "full_frame_plus_subject_crop"
    case subjectCropOnly = "subject_crop_only"
}

enum NeuralEvidenceFailureReason: String, Codable, Sendable {
    case modelNotLoaded = "model_not_loaded"
    case preprocessingFailed = "preprocessing_failed"
    case inferenceFailed = "inference_failed"
    case postprocessingFailed = "postprocessing_failed"
    case policySkipped = "policy_skipped"
    case runtimeTimeout = "runtime_timeout"
    case unknown
}

struct NeuralEvidenceRuntimeMetadata: Codable, Equatable, Sendable {
    let metadataSchemaVersion: String
    let frameId: String
    let mode: AnalysisMode
    let providerKind: NeuralEvidenceProviderKind
    let inferenceTarget: InferenceTargetKind
    let modelFamily: String
    let modelVersion: String
    let preprocessingVersion: String
    let thresholdProfile: String
    let producedAt: Date
    let latencyMs: Int?
    let roiStrategy: NeuralEvidenceROIStrategy?
    let failureReason: NeuralEvidenceFailureReason?

    init(metadataSchemaVersion: String,
         frameId: String,
         mode: AnalysisMode,
         providerKind: NeuralEvidenceProviderKind,
         inferenceTarget: InferenceTargetKind,
         modelFamily: String,
         modelVersion: String,
         preprocessingVersion: String,
         thresholdProfile: String,
         producedAt: Date,
         latencyMs: Int?,
         roiStrategy: NeuralEvidenceROIStrategy?,
         failureReason: NeuralEvidenceFailureReason?) {
        self.metadataSchemaVersion = metadataSchemaVersion
        self.frameId = frameId
        self.mode = mode
        self.providerKind = providerKind
        self.inferenceTarget = inferenceTarget
        self.modelFamily = modelFamily
        self.modelVersion = modelVersion
        self.preprocessingVersion = preprocessingVersion
        self.thresholdProfile = thresholdProfile
        self.producedAt = producedAt
        self.latencyMs = latencyMs.map { max(0, $0) }
        self.roiStrategy = roiStrategy
        self.failureReason = failureReason
    }

    private enum CodingKeys: String, CodingKey {
        case metadataSchemaVersion
        case frameId
        case mode
        case providerKind
        case inferenceTarget
        case modelFamily
        case modelVersion
        case preprocessingVersion
        case thresholdProfile
        case producedAt
        case latencyMs
        case roiStrategy
        case failureReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metadataSchemaVersion = try container.decode(String.self, forKey: .metadataSchemaVersion)
        frameId = try container.decode(String.self, forKey: .frameId)
        mode = try container.decode(AnalysisMode.self, forKey: .mode)
        providerKind = try container.decode(NeuralEvidenceProviderKind.self, forKey: .providerKind)
        inferenceTarget = try container.decode(InferenceTargetKind.self, forKey: .inferenceTarget)
        modelFamily = try container.decode(String.self, forKey: .modelFamily)
        modelVersion = try container.decode(String.self, forKey: .modelVersion)
        preprocessingVersion = try container.decode(String.self, forKey: .preprocessingVersion)
        thresholdProfile = try container.decode(String.self, forKey: .thresholdProfile)
        producedAt = try container.decodeISO8601Date(forKey: .producedAt)
        latencyMs = try container.decodeIfPresent(Int.self, forKey: .latencyMs)
        roiStrategy = try container.decodeIfPresent(NeuralEvidenceROIStrategy.self, forKey: .roiStrategy)
        failureReason = try container.decodeIfPresent(NeuralEvidenceFailureReason.self, forKey: .failureReason)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(metadataSchemaVersion, forKey: .metadataSchemaVersion)
        try container.encode(frameId, forKey: .frameId)
        try container.encode(mode, forKey: .mode)
        try container.encode(providerKind, forKey: .providerKind)
        try container.encode(inferenceTarget, forKey: .inferenceTarget)
        try container.encode(modelFamily, forKey: .modelFamily)
        try container.encode(modelVersion, forKey: .modelVersion)
        try container.encode(preprocessingVersion, forKey: .preprocessingVersion)
        try container.encode(thresholdProfile, forKey: .thresholdProfile)
        try container.encodeISO8601Date(producedAt, forKey: .producedAt)
        if let latencyMs {
            try container.encode(latencyMs, forKey: .latencyMs)
        } else {
            try container.encodeNil(forKey: .latencyMs)
        }
        if let roiStrategy {
            try container.encode(roiStrategy, forKey: .roiStrategy)
        } else {
            try container.encodeNil(forKey: .roiStrategy)
        }
        if let failureReason {
            try container.encode(failureReason, forKey: .failureReason)
        } else {
            try container.encodeNil(forKey: .failureReason)
        }
    }

    func validate(against snapshot: NeuralEvidenceSnapshot) -> [String] {
        var errors: [String] = []

        if metadataSchemaVersion.isEmpty {
            errors.append("neuralEvidenceRuntimeMetadata.metadataSchemaVersion must be non-empty")
        } else if metadataSchemaVersion != NeuralEvidenceSnapshot.currentSchemaVersion {
            errors.append("neuralEvidenceRuntimeMetadata.metadataSchemaVersion must be \(NeuralEvidenceSnapshot.currentSchemaVersion)")
        }
        if modelFamily.isEmpty {
            errors.append("neuralEvidenceRuntimeMetadata.modelFamily must be non-empty")
        }
        if modelVersion.isEmpty {
            errors.append("neuralEvidenceRuntimeMetadata.modelVersion must be non-empty")
        }
        if preprocessingVersion.isEmpty {
            errors.append("neuralEvidenceRuntimeMetadata.preprocessingVersion must be non-empty")
        }
        if thresholdProfile.isEmpty {
            errors.append("neuralEvidenceRuntimeMetadata.thresholdProfile must be non-empty")
        }
        if frameId != snapshot.frameId || mode != snapshot.mode {
            errors.append("neuralEvidenceRuntimeMetadata must match snapshot frameId+mode")
        }
        if metadataSchemaVersion != snapshot.schemaVersion {
            errors.append("neuralEvidenceRuntimeMetadata.metadataSchemaVersion must match snapshot.schemaVersion")
        }
        if producedAt < snapshot.capturedAt {
            errors.append("neuralEvidenceRuntimeMetadata.producedAt must be >= snapshot.capturedAt")
        }
        if failureReason == .policySkipped && !snapshot.isPolicyDegraded {
            errors.append("policy_skipped requires a fully policy-degraded neural evidence snapshot")
        }

        return errors
    }
}

private extension NeuralEvidenceSnapshot {
    var isPolicyDegraded: Bool {
        switch mode {
        case .live:
            return headOutputs.allSatisfy { entry in
                switch entry.headId {
                case .balanceConfidence, .depthSeparation, .cinematicExpressiveness, .shotTypeConfidence:
                    return entry.payload.status == .notApplicable
                case .faceSaliency:
                    return entry.payload.status == .unavailable || entry.payload.status == .notApplicable
                default:
                    return entry.payload.status == .unavailable
                }
            }
        case .pause:
            return false
        }
    }
}

private extension EvidenceHeadId {
    var allowedSupportingSignals: Set<SupportingSignalTag> {
        switch self {
        case .subjectProminence:
            return [.subjectScale, .subjectAttentionPull, .subjectReadability]
        case .backgroundClutter:
            return [.objectDensity, .textureNoise, .attentionCompetition]
        case .lightingQuality:
            return [.subjectExposureReadability, .facialLightSupport, .tonalStructure]
        case .faceSaliency:
            return [.faceAttentionPull, .eyeRegionVisibility, .facialAnchorStrength, .facialLightSupport]
        case .balanceConfidence:
            return [.frameBalance, .subjectPlacementStability, .negativeSpaceFit]
        case .depthSeparation:
            return [.foregroundBackgroundSplit, .subjectBackgroundContrast, .layeringClarity]
        case .cinematicExpressiveness:
            return [.stylisticIntent, .productionValueResidual, .visualHarmonyResidual]
        case .shotTypeConfidence:
            return []
        }
    }

    static func canonicalIndex(of headId: EvidenceHeadId) -> Int {
        allCases.firstIndex(of: headId) ?? .max
    }
}

private extension EvidenceCategoryId {
    static func canonicalIndex(of categoryId: EvidenceCategoryId) -> Int {
        allCases.firstIndex(of: categoryId) ?? .max
    }
}

private extension SupportingSignalTag {
    static func canonicalIndex(of tag: SupportingSignalTag) -> Int {
        allCases.firstIndex(of: tag) ?? .max
    }
}

extension NeuralEvidenceHeadEntry {
    var explainabilityKeys: [String] {
        let prefix = "neural.\(headId.rawValue)"
        switch payload {
        case .scalar:
            return [
                "\(prefix).status",
                "\(prefix).score",
                "\(prefix).confidence",
                "\(prefix).supportingSignals"
            ]
        case let .categorical(categorical):
            return [
                "\(prefix).status",
                "\(prefix).confidence"
            ] + CategoricalEvidenceHeadOutput.sortAffinities(categorical.affinities).map {
                "\(prefix).affinities.\($0.categoryId.rawValue)"
            }
        }
    }
}

private extension ISO8601DateFormatter {
    static let neuralEvidenceFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()
}

private extension KeyedEncodingContainer {
    mutating func encodeISO8601Date(_ value: Date, forKey key: Key) throws {
        try encode(ISO8601DateFormatter.neuralEvidenceFormatter.string(from: value), forKey: key)
    }
}

private extension KeyedDecodingContainer {
    func decodeISO8601Date(forKey key: Key) throws -> Date {
        let rawValue = try decode(String.self, forKey: key)
        guard let date = ISO8601DateFormatter.neuralEvidenceFormatter.date(from: rawValue) else {
            throw DecodingError.dataCorruptedError(forKey: key,
                                                   in: self,
                                                   debugDescription: "Expected ISO-8601 date with fractional seconds")
        }
        return date
    }
}

// MARK: - Contract 5: ExplainabilityTrace

enum TraceStage: String, Codable, Sendable {
    case observation
    case interpretation
    case recommendation
}

enum TraceSourceKind: String, Codable, Sendable {
    case snapshotSignal = "snapshot_signal"
    case semanticsSignal = "semantics_signal"
    case neuralEvidence = "neural_evidence"
    case deterministicRule = "deterministic_rule"
    case plannerPolicy = "planner_policy"
    case optionalReasoning = "optional_reasoning"
}

enum TraceCertainty: String, Codable, Sendable {
    case deterministic
    case probabilistic
    case speculative
}

enum TraceAudience: String, Codable, Sendable {
    case core
    case debug
    case eval
    case ui
}

enum TraceLinkKind: String, Codable, Sendable {
    case issue
    case strength
    case action
    case overlay
    case summary
}

struct TraceLink: Codable, Equatable, Sendable {
    let kind: TraceLinkKind
    let refId: String
}

struct ExplainabilityTraceItem: Codable, Equatable, Sendable {
    let id: String
    let frameId: String
    let mode: AnalysisMode
    let stage: TraceStage
    let sourceKind: TraceSourceKind
    let certainty: TraceCertainty
    let confidence: Double
    let timestampMs: Int
    let statement: String
    let evidenceKeys: [String]
    let dependsOn: [String]
    let links: [TraceLink]
    let audiences: [TraceAudience]
    let metadata: [String: String]

    init(id: String,
         frameId: String,
         mode: AnalysisMode,
         stage: TraceStage,
         sourceKind: TraceSourceKind,
         certainty: TraceCertainty,
         confidence: Double,
         timestampMs: Int,
         statement: String,
         evidenceKeys: [String],
         dependsOn: [String],
         links: [TraceLink],
         audiences: [TraceAudience],
         metadata: [String: String] = [:]) {
        self.id = id
        self.frameId = frameId
        self.mode = mode
        self.stage = stage
        self.sourceKind = sourceKind
        self.certainty = certainty
        self.confidence = Self.clamp01(confidence)
        self.timestampMs = timestampMs
        self.statement = statement
        self.evidenceKeys = evidenceKeys
        self.dependsOn = dependsOn
        self.links = links
        self.audiences = audiences
        self.metadata = metadata
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
    }
}

struct ExplainabilityTraceBundle: Codable, Equatable, Sendable {
    let frameId: String
    let mode: AnalysisMode
    let items: [ExplainabilityTraceItem]
    let rootSummaryIds: [String]

    func validate(critiqueReport: CritiqueReport? = nil, recommendationPlan: RecommendationPlan? = nil) -> [String] {
        var errors: [String] = []

        if frameId.isEmpty {
            errors.append("traceBundle.frameId must be non-empty")
        }

        if let critiqueReport {
            if critiqueReport.frameId != frameId || critiqueReport.mode != mode {
                errors.append("traceBundle must match critiqueReport.frameId+mode")
            }
        }

        if let recommendationPlan {
            if recommendationPlan.frameId != frameId || recommendationPlan.mode != mode {
                errors.append("traceBundle must match recommendationPlan.frameId+mode")
            }
        }

        let grouped = Dictionary(grouping: items, by: \.id)
        let duplicateIds = grouped.filter { $0.key.isEmpty || $0.value.count > 1 }.keys.sorted()
        if !duplicateIds.isEmpty {
            errors.append("trace item IDs must be non-empty and unique: \(duplicateIds)")
        }

        var itemById: [String: ExplainabilityTraceItem] = [:]
        for item in items where !item.id.isEmpty {
            if itemById[item.id] == nil {
                itemById[item.id] = item
            }
        }

        for item in items {
            if item.frameId != frameId || item.mode != mode {
                errors.append("trace item \(item.id) must match bundle frameId+mode")
            }

            if !isAllowed(stage: item.stage, sourceKind: item.sourceKind) {
                errors.append("trace item \(item.id) has invalid stage/sourceKind pair")
            }

            if item.certainty == .speculative && item.sourceKind == .deterministicRule {
                errors.append("trace item \(item.id) cannot use speculative certainty with deterministic_rule")
            }

            if item.sourceKind == .optionalReasoning && item.links.contains(where: { $0.kind == .action }) {
                errors.append("optional_reasoning item \(item.id) cannot link actions")
            }

            if !item.audiences.contains(.core) {
                errors.append("trace item \(item.id) must include core audience")
            }

            if item.dependsOn.contains(item.id) {
                errors.append("trace item \(item.id) cannot depend on itself")
            }

            for depId in item.dependsOn {
                guard let dep = itemById[depId] else {
                    errors.append("trace item \(item.id) depends on unknown item \(depId)")
                    continue
                }

                if dep.timestampMs >= item.timestampMs {
                    errors.append("trace dependency \(dep.id) must have timestamp < \(item.id)")
                }
            }

            switch item.stage {
            case .observation:
                if item.dependsOn.contains(where: { itemById[$0]?.stage != .observation }) {
                    errors.append("observation item \(item.id) can only depend on observation items")
                }
            case .interpretation:
                if item.dependsOn.isEmpty {
                    errors.append("interpretation item \(item.id) must depend on at least one observation item")
                }
                if item.dependsOn.contains(where: { itemById[$0]?.stage != .observation }) {
                    errors.append("interpretation item \(item.id) can only depend on observation items")
                }
            case .recommendation:
                if item.dependsOn.isEmpty {
                    errors.append("recommendation item \(item.id) must depend on deterministic interpretation items")
                }
                for depId in item.dependsOn {
                    guard let dep = itemById[depId] else { continue }
                    if dep.stage != .interpretation || dep.sourceKind != .deterministicRule {
                        errors.append("recommendation item \(item.id) must depend on deterministic interpretation items")
                        break
                    }
                }
            }

            if !item.dependsOn.isEmpty {
                let maxDependencyConfidence = item.dependsOn
                    .compactMap { itemById[$0]?.confidence }
                    .max()
                if let maxDependencyConfidence, item.confidence > maxDependencyConfidence + 0.1 {
                    errors.append("trace item \(item.id) confidence must not exceed max dependency confidence + 0.1")
                }
            }
        }

        if hasCycle(in: itemById) {
            errors.append("trace dependency graph must be acyclic")
        }

        if mode == .live && items.count > 12 {
            errors.append("live mode trace bundle should not exceed 12 items")
        }

        for rootId in rootSummaryIds {
            guard let root = itemById[rootId] else {
                errors.append("rootSummaryId \(rootId) must reference an existing trace item")
                continue
            }
            if root.stage != .interpretation && root.stage != .recommendation {
                errors.append("rootSummaryId \(rootId) must reference interpretation or recommendation item")
            }
            if !root.links.contains(where: { $0.kind == .summary }) {
                errors.append("rootSummaryId \(rootId) must include a summary link")
            }
            if let critiqueReport,
               !root.links.contains(where: { $0.kind == .summary && $0.refId == critiqueReport.summary.id }) {
                errors.append("rootSummaryId \(rootId) must link critique summary id \(critiqueReport.summary.id)")
            }
        }

        if let critiqueReport {
            errors.append(contentsOf: validateIssueAndStrengthCoverage(critiqueReport: critiqueReport))
        }

        if let recommendationPlan {
            errors.append(contentsOf: validateActionCoverage(recommendationPlan: recommendationPlan))
        }

        if let critiqueReport, let recommendationPlan {
            let hasCorrectiveAction = recommendationPlan.allActions.contains(where: { $0.actionType != .leaveFrameAsIs })
            if critiqueReport.verdict == .good && !hasCorrectiveAction {
                let hasSummaryLink = items.contains {
                    $0.links.contains(where: { $0.kind == .summary && $0.refId == critiqueReport.summary.id })
                }
                if !hasSummaryLink {
                    errors.append("good verdict without corrective actions must include summary trace link")
                }
            }
        }

        errors.append(contentsOf: validateTraceLinkResolution(critiqueReport: critiqueReport, recommendationPlan: recommendationPlan))

        return errors
    }

    private func validateIssueAndStrengthCoverage(critiqueReport: CritiqueReport) -> [String] {
        var errors: [String] = []

        for issueId in critiqueReport.issues.map(\.id) {
            let covered = items.contains { item in
                item.stage == .interpretation
                    && item.links.contains(where: { $0.kind == .issue && $0.refId == issueId })
            }
            if !covered {
                errors.append("issue \(issueId) must be linked from interpretation trace item")
            }
        }

        for strengthId in critiqueReport.strengths.map(\.id) {
            let covered = items.contains { item in
                item.stage == .interpretation
                    && item.links.contains(where: { $0.kind == .strength && $0.refId == strengthId })
            }
            if !covered {
                errors.append("strength \(strengthId) must be linked from interpretation trace item")
            }
        }

        return errors
    }

    private func validateActionCoverage(recommendationPlan: RecommendationPlan) -> [String] {
        var errors: [String] = []

        for actionId in recommendationPlan.allActions.map(\.id) {
            let covered = items.contains { item in
                item.stage == .recommendation
                    && item.links.contains(where: { $0.kind == .action && $0.refId == actionId })
            }
            if !covered {
                errors.append("action \(actionId) must be linked from recommendation trace item")
            }
        }

        return errors
    }

    private func validateTraceLinkResolution(critiqueReport: CritiqueReport?, recommendationPlan: RecommendationPlan?) -> [String] {
        var errors: [String] = []
        let issueIds = critiqueReport.map { Set($0.issues.map(\.id)) }
        let strengthIds = critiqueReport.map { Set($0.strengths.map(\.id)) }
        let actionIds = recommendationPlan.map { Set($0.allActions.map(\.id)) }
        let overlayIds = recommendationPlan.map { Set($0.allActions.compactMap(\.overlayHint?.id)) }
        let summaryId = critiqueReport?.summary.id

        for item in items {
            for link in item.links {
                switch link.kind {
                case .issue:
                    if let issueIds, !issueIds.contains(link.refId) {
                        errors.append("trace item \(item.id) links unknown issue id \(link.refId)")
                    }
                case .strength:
                    if let strengthIds, !strengthIds.contains(link.refId) {
                        errors.append("trace item \(item.id) links unknown strength id \(link.refId)")
                    }
                case .action:
                    if let actionIds, !actionIds.contains(link.refId) {
                        errors.append("trace item \(item.id) links unknown action id \(link.refId)")
                    }
                case .overlay:
                    if let overlayIds, !overlayIds.contains(link.refId) {
                        errors.append("trace item \(item.id) links unknown overlay id \(link.refId)")
                    }
                case .summary:
                    if let summaryId, link.refId != summaryId {
                        errors.append("trace item \(item.id) links unknown summary id \(link.refId)")
                    }
                default:
                    break
                }
            }
        }

        return errors
    }

    private func hasCycle(in itemById: [String: ExplainabilityTraceItem]) -> Bool {
        enum VisitState {
            case visiting
            case visited
        }

        var state: [String: VisitState] = [:]

        func dfs(_ id: String) -> Bool {
            if let current = state[id] {
                return current == .visiting
            }

            state[id] = .visiting
            for depId in itemById[id]?.dependsOn ?? [] {
                if itemById[depId] != nil && dfs(depId) {
                    return true
                }
            }
            state[id] = .visited
            return false
        }

        for id in itemById.keys where state[id] == nil {
            if dfs(id) {
                return true
            }
        }

        return false
    }

    private func isAllowed(stage: TraceStage, sourceKind: TraceSourceKind) -> Bool {
        switch (stage, sourceKind) {
        case (.observation, .snapshotSignal),
            (.observation, .semanticsSignal),
            (.observation, .neuralEvidence),
            (.interpretation, .deterministicRule),
            (.interpretation, .optionalReasoning),
            (.recommendation, .plannerPolicy):
            return true
        default:
            return false
        }
    }
}

private extension RecommendationPlan {
    var allActions: [RecommendationAction] {
        [primaryAction].compactMap { $0 } + secondaryActions + deferredActions
    }
}

// MARK: - PR-S01: Entity-Aware Semantic Tip Contract

enum TargetEntityKind: String, Codable, CaseIterable, Sendable {
    case person
    case face
    case object
    case prop
    case backgroundArea = "background_area"
    case lightSource = "light_source"
    case frame
    case unknown
}

enum TargetEntityRole: String, Codable, CaseIterable, Sendable {
    case primarySubject = "primary_subject"
    case secondarySubject = "secondary_subject"
    case foregroundObject = "foreground_object"
    case backgroundObject = "background_object"
    case distractingObject = "distracting_object"
    case prop
    case faceContourOccluder = "face_contour_occluder"
    case lightTarget = "light_target"
    case backgroundZone = "background_zone"
    case wholeFrame = "whole_frame"
}

enum SemanticActionFrame: String, Codable, CaseIterable, Sendable {
    case moveCamera = "move_camera"
    case moveSubject = "move_subject"
    case moveObject = "move_object"
    case adjustLight = "adjust_light"
    case wait
}

enum SemanticDirection: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case up
    case down
    case forward
    case back
    case none
}

enum VisualProblemType: String, Codable, CaseIterable, Sendable {
    case subjectEdgePressure = "subject_edge_pressure"
    case objectEdgePressure = "object_edge_pressure"
    case tightFraming = "tight_framing"
    case insufficientLookSpace = "insufficient_look_space"
    case weakSubjectProminence = "weak_subject_prominence"
    case weakObjectProminence = "weak_object_prominence"
    case backgroundCompetition = "background_competition"
    case backgroundClutter = "background_clutter"
    case frontLightDeficit = "front_light_deficit"
    case subjectBlendsIntoDarkBackground = "subject_blends_into_dark_background"
    case brightBackgroundPull = "bright_background_pull"
    case flatDepth = "flat_depth"
    case weakSubjectBackgroundSeparation = "weak_subject_background_separation"
    case cameraHeightMismatch = "camera_height_mismatch"
    case perspectiveMismatch = "perspective_mismatch"
    case unclearFocusHierarchy = "unclear_focus_hierarchy"
    case propBreaksBalance = "prop_breaks_balance"
    case objectConflictsWithSubject = "object_conflicts_with_subject"
    case faceContourOcclusion = "face_contour_occlusion"
    case tiltedHorizon = "tilted_horizon"
    case timingBlockerInFrame = "timing_blocker_in_frame"
}

enum VisualStrengthType: String, Codable, CaseIterable, Sendable {
    case cleanSubjectSeparation = "clean_subject_separation"
    case flatteringLightDirection = "flattering_light_direction"
    case clearFocusHierarchy = "clear_focus_hierarchy"
    case balancedSceneComposition = "balanced_scene_composition"
    case stableHorizon = "stable_horizon"
    case readableDepthLayers = "readable_depth_layers"
    case objectBalanceHolds = "object_balance_holds"
    case frameReady = "frame_ready"
}

enum SemanticActionType: String, Codable, CaseIterable, Sendable {
    case shiftFrameLeft = "shift_frame_left"
    case shiftFrameRight = "shift_frame_right"
    case shiftFrameUp = "shift_frame_up"
    case shiftFrameDown = "shift_frame_down"
    case stepBack = "step_back"
    case stepCloser = "step_closer"
    case lowerCamera = "lower_camera"
    case raiseCamera = "raise_camera"
    case changeCameraAngle = "change_camera_angle"
    case levelHorizon = "level_horizon"
    case rotateSubjectTowardLight = "rotate_subject_toward_light"
    case moveSubjectLeft = "move_subject_left"
    case moveSubjectRight = "move_subject_right"
    case moveSubjectAwayFromBackground = "move_subject_away_from_background"
    case moveObjectLeft = "move_object_left"
    case moveObjectRight = "move_object_right"
    case moveObjectForward = "move_object_forward"
    case moveObjectBack = "move_object_back"
    case removeDistractingObject = "remove_distracting_object"
    case repositionPropForBalance = "reposition_prop_for_balance"
    case addFrontFillLight = "add_front_fill_light"
    case addBackgroundLight = "add_background_light"
    case removeBackgroundHotspot = "remove_background_hotspot"
    case simplifyBackground = "simplify_background"
    case waitForBackgroundClearance = "wait_for_background_clearance"
    case keepCurrentSetup = "keep_current_setup"
}

enum SemanticTipType: String, Codable, CaseIterable, Sendable {
    case createLookSpaceLeft = "create_look_space_left"
    case createLookSpaceRight = "create_look_space_right"
    case moveSubjectOffLeftEdge = "move_subject_off_left_edge"
    case moveSubjectOffRightEdge = "move_subject_off_right_edge"
    case moveObjectOffLeftEdge = "move_object_off_left_edge"
    case moveObjectOffRightEdge = "move_object_off_right_edge"
    case addHeadroom = "add_headroom"
    case showMoreLowerFrame = "show_more_lower_frame"
    case stepBackForBreathingRoom = "step_back_for_breathing_room"
    case stepCloserForSubjectProminence = "step_closer_for_subject_prominence"
    case stepCloserForObjectProminence = "step_closer_for_object_prominence"
    case lowerCameraForSubject = "lower_camera_for_subject"
    case raiseCameraForSubject = "raise_camera_for_subject"
    case changeAngleForCleanerBackground = "change_angle_for_cleaner_background"
    case addDepthByMovingSubjectFromBackground = "add_depth_by_moving_subject_from_background"
    case addDepthByMovingObjectForward = "add_depth_by_moving_object_forward"
    case moveObjectBackForBalance = "move_object_back_for_balance"
    case moveSubjectLeftForBalance = "move_subject_left_for_balance"
    case moveSubjectRightForBalance = "move_subject_right_for_balance"
    case moveObjectLeftForBalance = "move_object_left_for_balance"
    case moveObjectRightForBalance = "move_object_right_for_balance"
    case removeObjectFromFaceContour = "remove_object_from_face_contour"
    case removeDistractingProp = "remove_distracting_prop"
    case rebalancePropLayout = "rebalance_prop_layout"
    case turnSubjectTowardLight = "turn_subject_toward_light"
    case addFrontFillOnSubject = "add_front_fill_on_subject"
    case addBackgroundLightForSeparation = "add_background_light_for_separation"
    case removeBrightSpotBehindSubject = "remove_bright_spot_behind_subject"
    case clarifyMainSubjectFocus = "clarify_main_subject_focus"
    case simplifyBusyBackground = "simplify_busy_background"
    case waitForBackgroundClearance = "wait_for_background_clearance"
    case levelHorizonForStability = "level_horizon_for_stability"
    case keepSubjectSeparation = "keep_subject_separation"
    case keepLightDirection = "keep_light_direction"
    case keepFocusHierarchy = "keep_focus_hierarchy"
    case keepHorizonStability = "keep_horizon_stability"
    case keepDepthReadability = "keep_depth_readability"
    case keepObjectBalance = "keep_object_balance"
    case keepFrameAsIs = "keep_frame_as_is"
}

enum SemanticTipPriorityBand: String, Codable, CaseIterable, Sendable {
    case primaryCorrective = "primary_corrective"
    case secondaryCorrective = "secondary_corrective"
    case contextualCorrective = "contextual_corrective"
    case timingCorrective = "timing_corrective"
    case positiveConfirmation = "positive_confirmation"
}

enum SemanticTipFallback: String, Codable, CaseIterable, Sendable {
    case suppress
    case degradeToGenericLabel = "degrade_to_generic_label"
    case degradeToGenericActionCopy = "degrade_to_generic_action_copy"
    case replaceWithKeepFrameAsIs = "replace_with_keep_frame_as_is"
    case useLegacySuggestion = "use_legacy_suggestion"
}

struct SemanticTipDefinition: Codable, Equatable, Sendable {
    let tipType: SemanticTipType
    let actionType: SemanticActionType
    let actionFrame: SemanticActionFrame
    let direction: SemanticDirection
    let targetEntityKind: TargetEntityKind
    let targetEntityRole: TargetEntityRole
    let problemTypes: [VisualProblemType]
    let strengthTypes: [VisualStrengthType]
    let supportedModes: [AnalysisMode]
    let priorityBand: SemanticTipPriorityBand
    let fallbackBehavior: SemanticTipFallback

    var isCorrective: Bool {
        !problemTypes.isEmpty
    }

    var isPositive: Bool {
        priorityBand == .positiveConfirmation
    }

    func validate() -> [String] {
        var errors: [String] = []

        if supportedModes.isEmpty {
            errors.append("semantic tip definition must support at least one mode")
        }

        if isPositive {
            if strengthTypes.isEmpty {
                errors.append("positive semantic tip definition requires strengthTypes")
            }
            if !problemTypes.isEmpty {
                errors.append("positive semantic tip definition must not include problemTypes")
            }
        } else if problemTypes.isEmpty {
            errors.append("corrective semantic tip definition requires problemTypes")
        }

        if actionFrame == .wait && actionType != .waitForBackgroundClearance {
            errors.append("wait actionFrame requires wait_for_background_clearance action")
        }

        if actionType == .waitForBackgroundClearance && actionFrame != .wait {
            errors.append("wait_for_background_clearance requires wait actionFrame")
        }

        if actionType == .keepCurrentSetup && priorityBand != .positiveConfirmation {
            errors.append("keep_current_setup is reserved for positive confirmation tips")
        }

        return errors
    }
}

struct SemanticTipCandidate: Codable, Equatable, Sendable {
    let tipType: SemanticTipType
    let actionType: SemanticActionType
    let actionFrame: SemanticActionFrame
    let direction: SemanticDirection?
    let problemType: VisualProblemType?
    let strengthType: VisualStrengthType?
    let targetEntityKind: TargetEntityKind
    let targetEntityRole: TargetEntityRole
    let targetEntityRef: String?
    let targetEntityGroundingConfidence: Double?
    let targetEntityDisplayLabel: String
    let secondaryEntityRef: String?
    let secondaryEntityGroundingConfidence: Double?
    let secondaryEntityDisplayLabel: String?
    let primaryActionId: String?
    let linkedActionIds: [String]
    let linkedIssueIds: [String]
    let linkedStrengthIds: [String]
    let linkedTraceIds: [String]
    let summaryId: String?
    let supportedModes: [AnalysisMode]
    let priorityBand: SemanticTipPriorityBand
    let liveText: String
    let pauseText: String
    let fallbackBehavior: SemanticTipFallback

    func validate() -> [String] {
        var errors: [String] = []

        if supportedModes.isEmpty {
            errors.append("semantic tip must support at least one mode")
        }

        if liveText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pauseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("semantic tip copy must be non-empty")
        }

        if liveText.count > 90 {
            errors.append("liveText must be <= 90 characters")
        }

        if !SemanticDisplayLabelPolicy.isAllowedDisplayLabel(targetEntityDisplayLabel, for: targetEntityKind) {
            errors.append("targetEntityDisplayLabel must follow safe label policy")
        }

        if let secondaryEntityDisplayLabel,
           !SemanticDisplayLabelPolicy.isAllowedDisplayLabel(secondaryEntityDisplayLabel) {
            errors.append("secondaryEntityDisplayLabel must follow safe label policy")
        }

        if SemanticDisplayLabelPolicy.isGroundedObjectDisplayLabel(targetEntityDisplayLabel),
           targetEntityRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            errors.append("grounded targetEntityDisplayLabel requires targetEntityRef")
        }

        if let targetEntityGroundingConfidence,
           !SemanticDisplayLabelPolicy.isValidConfidence(targetEntityGroundingConfidence) {
            errors.append("targetEntityGroundingConfidence must be between 0 and 1")
        }

        if SemanticDisplayLabelPolicy.isGroundedObjectDisplayLabel(targetEntityDisplayLabel),
           targetEntityGroundingConfidence.map(SemanticDisplayLabelPolicy.isHighConfidenceGrounding) != true {
            errors.append("grounded targetEntityDisplayLabel requires high-confidence grounding")
        }

        if let secondaryEntityDisplayLabel,
           SemanticDisplayLabelPolicy.isGroundedObjectDisplayLabel(secondaryEntityDisplayLabel),
           secondaryEntityRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            errors.append("grounded secondaryEntityDisplayLabel requires secondaryEntityRef")
        }

        if let secondaryEntityGroundingConfidence,
           !SemanticDisplayLabelPolicy.isValidConfidence(secondaryEntityGroundingConfidence) {
            errors.append("secondaryEntityGroundingConfidence must be between 0 and 1")
        }

        if let secondaryEntityDisplayLabel,
           SemanticDisplayLabelPolicy.isGroundedObjectDisplayLabel(secondaryEntityDisplayLabel),
           secondaryEntityGroundingConfidence.map(SemanticDisplayLabelPolicy.isHighConfidenceGrounding) != true {
            errors.append("grounded secondaryEntityDisplayLabel requires high-confidence grounding")
        }

        if let definition = SemanticTipCatalog.definition(for: tipType) {
            if actionType != definition.actionType {
                errors.append("semantic tip actionType must match catalog definition")
            }

            if actionFrame != definition.actionFrame {
                errors.append("semantic tip actionFrame must match catalog definition")
            }

            if let direction, direction != definition.direction {
                errors.append("semantic tip direction must match catalog definition")
            }

            if targetEntityKind != definition.targetEntityKind {
                errors.append("semantic tip targetEntityKind must match catalog definition")
            }

            if targetEntityRole != definition.targetEntityRole {
                errors.append("semantic tip targetEntityRole must match catalog definition")
            }

            if !Set(supportedModes).isSubset(of: Set(definition.supportedModes)) {
                errors.append("semantic tip supportedModes must be subset of catalog definition")
            }

            if priorityBand != definition.priorityBand {
                errors.append("semantic tip priorityBand must match catalog definition")
            }

            if fallbackBehavior != definition.fallbackBehavior {
                errors.append("semantic tip fallbackBehavior must match catalog definition")
            }

            if let problemType, !definition.problemTypes.contains(problemType) {
                errors.append("semantic tip problemType must match catalog definition")
            }

            if let strengthType, !definition.strengthTypes.contains(strengthType) {
                errors.append("semantic tip strengthType must match catalog definition")
            }
        }

        if priorityBand == .positiveConfirmation {
            if strengthType == nil && summaryId == nil {
                errors.append("positive tip requires strengthType or summaryId")
            }
            if summaryId == nil {
                errors.append("positive tip requires summaryId")
            }
            if problemType != nil || !linkedIssueIds.isEmpty {
                errors.append("positive tip must not link corrective issue anchors")
            }
        } else {
            if problemType == nil {
                errors.append("corrective tip requires problemType")
            }
            if linkedIssueIds.isEmpty {
                errors.append("corrective tip requires linkedIssueIds")
            }
            if primaryActionId == nil && linkedActionIds.isEmpty {
                errors.append("corrective tip requires primaryActionId or linkedActionIds")
            }
        }

        if linkedTraceIds.isEmpty {
            errors.append("semantic tip requires linkedTraceIds")
        }

        if actionType == .keepCurrentSetup && priorityBand != .positiveConfirmation {
            errors.append("keep_current_setup is reserved for positive confirmation tips")
        }

        if actionFrame == .wait && actionType != .waitForBackgroundClearance {
            errors.append("wait actionFrame requires wait_for_background_clearance action")
        }

        if actionType == .waitForBackgroundClearance && actionFrame != .wait {
            errors.append("wait_for_background_clearance requires wait actionFrame")
        }

        if tipType == .removeObjectFromFaceContour {
            if secondaryEntityRef?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                errors.append("remove_object_from_face_contour requires secondaryEntityRef")
            }
            if secondaryEntityDisplayLabel == nil {
                errors.append("remove_object_from_face_contour requires secondaryEntityDisplayLabel")
            }
        }

        return errors
    }
}

enum GroundedObjectDisplayLabelV1: String, CaseIterable, Sendable {
    case flower = "цветок"
    case vase = "ваза"
    case book = "книга"
    case cup = "чашка"
    case bottle = "бутылка"
    case lamp = "лампа"
    case chair = "стул"
    case phone = "телефон"
}

enum SemanticDisplayLabelPolicy {
    static let minimumGroundedObjectConfidence = 0.75
    static let personLabels: Set<String> = ["герой", "человек", "лицо", "персонаж"]
    static let genericObjectLabels: Set<String> = ["предмет", "объект", "объект справа", "яркий объект на фоне", "предмет у лица"]
    static let relationLabels: Set<String> = ["у лица", "на фоне", "фон", "свет", "за героем", "у края кадра"]
    static let groundedObjectLabels = Set(GroundedObjectDisplayLabelV1.allCases.map(\.rawValue))

    static func displayLabel(entityKind: TargetEntityKind,
                             role: TargetEntityRole,
                             groundedLabel: String?,
                             confidence: Double,
                             direction: SemanticDirection? = nil) -> String {
        switch entityKind {
        case .face:
            return "лицо"
        case .person:
            return role == .primarySubject ? "герой" : "человек"
        case .object, .prop:
            let normalizedGroundedLabel = groundedLabel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if isHighConfidenceGrounding(confidence),
               let normalizedGroundedLabel,
               groundedObjectLabels.contains(normalizedGroundedLabel) {
                return normalizedGroundedLabel
            }
            if role == .faceContourOccluder {
                return "предмет у лица"
            }
            if role == .backgroundObject {
                return "яркий объект на фоне"
            }
            if direction == .right {
                return "объект справа"
            }
            return "предмет"
        case .backgroundArea:
            return "фон"
        case .lightSource:
            return "свет"
        case .frame:
            return "кадр"
        case .unknown:
            return "предмет"
        }
    }

    static func isAllowedDisplayLabel(_ label: String) -> Bool {
        personLabels.contains(label)
            || genericObjectLabels.contains(label)
            || relationLabels.contains(label)
            || groundedObjectLabels.contains(label)
            || label == "кадр"
    }

    static func isAllowedDisplayLabel(_ label: String, for entityKind: TargetEntityKind) -> Bool {
        switch entityKind {
        case .face:
            return label == "лицо"
        case .person:
            return personLabels.contains(label)
        case .object, .prop, .unknown:
            return genericObjectLabels.contains(label) || groundedObjectLabels.contains(label)
        case .backgroundArea:
            return label == "фон" || relationLabels.contains(label) || genericObjectLabels.contains(label)
        case .lightSource:
            return label == "свет"
        case .frame:
            return label == "кадр"
        }
    }

    static func isGroundedObjectDisplayLabel(_ label: String) -> Bool {
        groundedObjectLabels.contains(label)
    }

    static func isValidConfidence(_ confidence: Double) -> Bool {
        (0...1).contains(confidence)
    }

    static func isHighConfidenceGrounding(_ confidence: Double) -> Bool {
        isValidConfidence(confidence) && confidence >= minimumGroundedObjectConfidence
    }
}

enum SemanticTipCatalog {
    static let v1Actions: Set<SemanticActionType> = Set(SemanticActionType.allCases)

    static let deferredActions: Set<String> = [
        "add_rim_light",
        "add_side_light",
        "turn_subject_for_cleaner_profile"
    ]

    static let definitions: [SemanticTipDefinition] = [
        .init(tipType: .createLookSpaceLeft, actionType: .shiftFrameLeft, actionFrame: .moveCamera, direction: .left, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [.insufficientLookSpace], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .createLookSpaceRight, actionType: .shiftFrameRight, actionFrame: .moveCamera, direction: .right, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [.insufficientLookSpace], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .moveSubjectOffLeftEdge, actionType: .shiftFrameRight, actionFrame: .moveCamera, direction: .right, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.subjectEdgePressure], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .moveSubjectOffRightEdge, actionType: .shiftFrameLeft, actionFrame: .moveCamera, direction: .left, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.subjectEdgePressure], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .moveObjectOffLeftEdge, actionType: .moveObjectRight, actionFrame: .moveObject, direction: .right, targetEntityKind: .object, targetEntityRole: .foregroundObject, problemTypes: [.objectEdgePressure], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .moveObjectOffRightEdge, actionType: .moveObjectLeft, actionFrame: .moveObject, direction: .left, targetEntityKind: .object, targetEntityRole: .foregroundObject, problemTypes: [.objectEdgePressure], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .addHeadroom, actionType: .shiftFrameUp, actionFrame: .moveCamera, direction: .up, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.tightFraming], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .showMoreLowerFrame, actionType: .shiftFrameDown, actionFrame: .moveCamera, direction: .down, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.tightFraming], strengthTypes: [], supportedModes: [.pause], priorityBand: .contextualCorrective, fallbackBehavior: .suppress),
        .init(tipType: .stepBackForBreathingRoom, actionType: .stepBack, actionFrame: .moveCamera, direction: .back, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [.tightFraming], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .stepCloserForSubjectProminence, actionType: .stepCloser, actionFrame: .moveCamera, direction: .forward, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.weakSubjectProminence], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .stepCloserForObjectProminence, actionType: .stepCloser, actionFrame: .moveCamera, direction: .forward, targetEntityKind: .object, targetEntityRole: .foregroundObject, problemTypes: [.weakObjectProminence], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .lowerCameraForSubject, actionType: .lowerCamera, actionFrame: .moveCamera, direction: .down, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.cameraHeightMismatch, .perspectiveMismatch], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .raiseCameraForSubject, actionType: .raiseCamera, actionFrame: .moveCamera, direction: .up, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.cameraHeightMismatch, .perspectiveMismatch], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .changeAngleForCleanerBackground, actionType: .changeCameraAngle, actionFrame: .moveCamera, direction: .none, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [.backgroundCompetition, .perspectiveMismatch], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .secondaryCorrective, fallbackBehavior: .useLegacySuggestion),
        .init(tipType: .addDepthByMovingSubjectFromBackground, actionType: .moveSubjectAwayFromBackground, actionFrame: .moveSubject, direction: .back, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.weakSubjectBackgroundSeparation, .flatDepth], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .addDepthByMovingObjectForward, actionType: .moveObjectForward, actionFrame: .moveObject, direction: .forward, targetEntityKind: .object, targetEntityRole: .foregroundObject, problemTypes: [.weakObjectProminence, .flatDepth], strengthTypes: [], supportedModes: [.pause], priorityBand: .contextualCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .moveObjectBackForBalance, actionType: .moveObjectBack, actionFrame: .moveObject, direction: .back, targetEntityKind: .object, targetEntityRole: .foregroundObject, problemTypes: [.objectConflictsWithSubject, .propBreaksBalance], strengthTypes: [], supportedModes: [.pause], priorityBand: .contextualCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .moveSubjectLeftForBalance, actionType: .moveSubjectLeft, actionFrame: .moveSubject, direction: .left, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.backgroundCompetition, .unclearFocusHierarchy], strengthTypes: [], supportedModes: [.pause], priorityBand: .contextualCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .moveSubjectRightForBalance, actionType: .moveSubjectRight, actionFrame: .moveSubject, direction: .right, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.backgroundCompetition, .unclearFocusHierarchy], strengthTypes: [], supportedModes: [.pause], priorityBand: .contextualCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .moveObjectLeftForBalance, actionType: .moveObjectLeft, actionFrame: .moveObject, direction: .left, targetEntityKind: .object, targetEntityRole: .foregroundObject, problemTypes: [.propBreaksBalance, .objectConflictsWithSubject], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .moveObjectRightForBalance, actionType: .moveObjectRight, actionFrame: .moveObject, direction: .right, targetEntityKind: .object, targetEntityRole: .foregroundObject, problemTypes: [.propBreaksBalance, .objectConflictsWithSubject], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .removeObjectFromFaceContour, actionType: .removeDistractingObject, actionFrame: .moveObject, direction: .none, targetEntityKind: .prop, targetEntityRole: .faceContourOccluder, problemTypes: [.faceContourOcclusion, .objectConflictsWithSubject], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .removeDistractingProp, actionType: .removeDistractingObject, actionFrame: .moveObject, direction: .none, targetEntityKind: .prop, targetEntityRole: .distractingObject, problemTypes: [.objectConflictsWithSubject, .backgroundCompetition], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .rebalancePropLayout, actionType: .repositionPropForBalance, actionFrame: .moveObject, direction: .none, targetEntityKind: .prop, targetEntityRole: .prop, problemTypes: [.propBreaksBalance, .weakObjectProminence], strengthTypes: [], supportedModes: [.pause], priorityBand: .contextualCorrective, fallbackBehavior: .degradeToGenericLabel),
        .init(tipType: .turnSubjectTowardLight, actionType: .rotateSubjectTowardLight, actionFrame: .moveSubject, direction: .none, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.frontLightDeficit], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .addFrontFillOnSubject, actionType: .addFrontFillLight, actionFrame: .adjustLight, direction: .none, targetEntityKind: .lightSource, targetEntityRole: .lightTarget, problemTypes: [.frontLightDeficit], strengthTypes: [], supportedModes: [.pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .addBackgroundLightForSeparation, actionType: .addBackgroundLight, actionFrame: .adjustLight, direction: .none, targetEntityKind: .backgroundArea, targetEntityRole: .backgroundZone, problemTypes: [.subjectBlendsIntoDarkBackground, .weakSubjectBackgroundSeparation], strengthTypes: [], supportedModes: [.pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .removeBrightSpotBehindSubject, actionType: .removeBackgroundHotspot, actionFrame: .adjustLight, direction: .none, targetEntityKind: .backgroundArea, targetEntityRole: .backgroundZone, problemTypes: [.brightBackgroundPull], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .clarifyMainSubjectFocus, actionType: .stepCloser, actionFrame: .moveCamera, direction: .forward, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [.unclearFocusHierarchy], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .simplifyBusyBackground, actionType: .simplifyBackground, actionFrame: .moveObject, direction: .none, targetEntityKind: .backgroundArea, targetEntityRole: .backgroundZone, problemTypes: [.backgroundClutter], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .primaryCorrective, fallbackBehavior: .useLegacySuggestion),
        .init(tipType: .waitForBackgroundClearance, actionType: .waitForBackgroundClearance, actionFrame: .wait, direction: .none, targetEntityKind: .object, targetEntityRole: .backgroundObject, problemTypes: [.timingBlockerInFrame], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .timingCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .levelHorizonForStability, actionType: .levelHorizon, actionFrame: .moveCamera, direction: .none, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [.tiltedHorizon], strengthTypes: [], supportedModes: [.live, .pause], priorityBand: .secondaryCorrective, fallbackBehavior: .degradeToGenericActionCopy),
        .init(tipType: .keepSubjectSeparation, actionType: .keepCurrentSetup, actionFrame: .moveCamera, direction: .none, targetEntityKind: .person, targetEntityRole: .primarySubject, problemTypes: [], strengthTypes: [.cleanSubjectSeparation], supportedModes: [.live, .pause], priorityBand: .positiveConfirmation, fallbackBehavior: .replaceWithKeepFrameAsIs),
        .init(tipType: .keepLightDirection, actionType: .keepCurrentSetup, actionFrame: .adjustLight, direction: .none, targetEntityKind: .lightSource, targetEntityRole: .lightTarget, problemTypes: [], strengthTypes: [.flatteringLightDirection], supportedModes: [.live, .pause], priorityBand: .positiveConfirmation, fallbackBehavior: .replaceWithKeepFrameAsIs),
        .init(tipType: .keepFocusHierarchy, actionType: .keepCurrentSetup, actionFrame: .moveCamera, direction: .none, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [], strengthTypes: [.clearFocusHierarchy], supportedModes: [.live, .pause], priorityBand: .positiveConfirmation, fallbackBehavior: .replaceWithKeepFrameAsIs),
        .init(tipType: .keepHorizonStability, actionType: .keepCurrentSetup, actionFrame: .moveCamera, direction: .none, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [], strengthTypes: [.stableHorizon], supportedModes: [.live, .pause], priorityBand: .positiveConfirmation, fallbackBehavior: .replaceWithKeepFrameAsIs),
        .init(tipType: .keepDepthReadability, actionType: .keepCurrentSetup, actionFrame: .moveCamera, direction: .none, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [], strengthTypes: [.readableDepthLayers], supportedModes: [.live, .pause], priorityBand: .positiveConfirmation, fallbackBehavior: .replaceWithKeepFrameAsIs),
        .init(tipType: .keepObjectBalance, actionType: .keepCurrentSetup, actionFrame: .moveObject, direction: .none, targetEntityKind: .object, targetEntityRole: .foregroundObject, problemTypes: [], strengthTypes: [.objectBalanceHolds], supportedModes: [.live, .pause], priorityBand: .positiveConfirmation, fallbackBehavior: .replaceWithKeepFrameAsIs),
        .init(tipType: .keepFrameAsIs, actionType: .keepCurrentSetup, actionFrame: .moveCamera, direction: .none, targetEntityKind: .frame, targetEntityRole: .wholeFrame, problemTypes: [], strengthTypes: [.balancedSceneComposition, .frameReady], supportedModes: [.live, .pause], priorityBand: .positiveConfirmation, fallbackBehavior: .useLegacySuggestion)
    ]

    static let issueTipCoverage: [IssueTypeV1: Set<SemanticTipType>] = [
        .subjectTooCloseToEdge: [.moveSubjectOffLeftEdge, .moveSubjectOffRightEdge, .moveObjectOffLeftEdge, .moveObjectOffRightEdge, .addHeadroom, .showMoreLowerFrame, .stepBackForBreathingRoom, .lowerCameraForSubject, .raiseCameraForSubject],
        .subjectNotProminentEnough: [.stepCloserForSubjectProminence, .stepCloserForObjectProminence, .addDepthByMovingSubjectFromBackground, .addDepthByMovingObjectForward, .addBackgroundLightForSeparation],
        .backgroundCompetesWithSubject: [.changeAngleForCleanerBackground, .moveSubjectLeftForBalance, .moveSubjectRightForBalance, .moveObjectLeftForBalance, .moveObjectRightForBalance, .moveObjectBackForBalance, .removeObjectFromFaceContour, .removeDistractingProp, .rebalancePropLayout, .removeBrightSpotBehindSubject],
        .insufficientLookSpace: [.createLookSpaceLeft, .createLookSpaceRight],
        .backlightHidesSubject: [.turnSubjectTowardLight, .addFrontFillOnSubject, .addBackgroundLightForSeparation, .removeBrightSpotBehindSubject],
        .sceneHasNoClearFocus: [.clarifyMainSubjectFocus, .simplifyBusyBackground, .moveSubjectLeftForBalance, .moveSubjectRightForBalance],
        .frameVisuallyOverloaded: [.simplifyBusyBackground, .waitForBackgroundClearance, .removeDistractingProp],
        .horizonDistracts: [.levelHorizonForStability]
    ]

    static let strengthTipCoverage: [StrengthTypeV1: Set<SemanticTipType>] = [
        .goodSubjectIsolation: [.keepSubjectSeparation, .keepDepthReadability],
        .goodLightEmphasis: [.keepLightDirection],
        .clearFocusHierarchy: [.keepFocusHierarchy, .keepDepthReadability],
        .stableHorizonSupportsScene: [.keepHorizonStability],
        .balancedCompositionForScene: [.keepObjectBalance, .keepFrameAsIs]
    ]

    static func definition(for tipType: SemanticTipType) -> SemanticTipDefinition? {
        definitions.first { $0.tipType == tipType }
    }
}

// MARK: - PR-S02: VLM Visual Semantic Evidence Contract

enum VLMEvidenceSchemaVersion: String, Codable, CaseIterable, Sendable {
    case s1
}

enum VLMVisualEvidenceDimension: String, Codable, CaseIterable, Sendable {
    case subjectReadability = "subject_readability"
    case backgroundSeparation = "background_separation"
    case lightingRelation = "lighting_relation"
    case clutter
    case depth
    case faceVisibility = "face_visibility"
    case frameIntent = "frame_intent"
    case moodPreservation = "mood_preservation"
}

enum VLMEntityKind: String, Codable, CaseIterable, Sendable {
    case person
    case face
    case object
    case prop
    case backgroundArea = "background_area"
    case lightSource = "light_source"
    case frame
    case unknown
}

enum VLMEntityRelationType: String, Codable, CaseIterable, Sendable {
    case competesWith = "competes_with"
    case mergesWith = "merges_with"
    case blocks
    case pullsAttentionFrom = "pulls_attention_from"
}

enum VLMEvidencePolarity: String, Codable, CaseIterable, Sendable {
    case supportsProblem = "supports_problem"
    case supportsStrength = "supports_strength"
    case neutralContext = "neutral_context"
}

enum VLMUncertaintyReason: String, Codable, CaseIterable, Sendable {
    case lowVisualConfidence = "low_visual_confidence"
    case occludedEntity = "occluded_entity"
    case ambiguousSubject = "ambiguous_subject"
    case ambiguousObjectLabel = "ambiguous_object_label"
    case weakGrounding = "weak_grounding"
    case privacyRedaction = "privacy_redaction"
    case insufficientResolution = "insufficient_resolution"
    case conflictingLocalContext = "conflicting_local_context"
    case moodIntentAmbiguous = "mood_intent_ambiguous"
}

enum VLMResponseStatus: String, Codable, CaseIterable, Sendable {
    case completed
    case refused
    case unavailable
}

enum VLMTrigger: String, Codable, CaseIterable, Sendable {
    case explicitUserRequest = "explicit_user_request"
    case ambiguousLocalCase = "ambiguous_local_case"
    case fusionDisagreementProbe = "fusion_disagreement_probe"
    case partialLocalFailure = "partial_local_failure"
    case evalSampling = "eval_sampling"
}

enum VLMPrivacyTier: String, Codable, CaseIterable, Sendable {
    case structuredOnly = "structured_only"
    case redactedVisual = "redacted_visual"
}

enum VLMVisualInputAttachmentKind: String, Codable, CaseIterable, Sendable {
    case redactedStill = "redacted_still"
    case redactedSubjectCrop = "redacted_subject_crop"
}

enum VLMEvidenceViolation: String, Codable, CaseIterable, Sendable {
    case modeNotPause = "mode_not_pause"
    case requestMismatch = "request_mismatch"
    case unknownEntityRef = "unknown_entity_ref"
    case unknownIssueId = "unknown_issue_id"
    case unknownStrengthId = "unknown_strength_id"
    case unknownActionId = "unknown_action_id"
    case unknownProblemType = "unknown_problem_type"
    case unknownStrengthType = "unknown_strength_type"
    case unknownDimension = "unknown_dimension"
    case unsafeSpecificLabel = "unsafe_specific_label"
    case labelWithoutGrounding = "label_without_grounding"
    case contradictoryKeepAndCorrect = "contradictory_keep_and_correct"
    case attemptsToChangeVerdict = "attempts_to_change_verdict"
    case attemptsToChangeTaxonomy = "attempts_to_change_taxonomy"
    case outputTooLong = "output_too_long"
    case privacyTierMismatch = "privacy_tier_mismatch"
    case malformedJSON = "malformed_json"
}

struct VLMVisualInput: Codable, Equatable, Sendable {
    let attachmentKind: VLMVisualInputAttachmentKind
    let mediaRef: String
    let longEdgePx: Int
    let exifStripped: Bool
    let redactionApplied: Bool
    let redactionNotes: [String]

    func validate() -> [VLMEvidenceViolation] {
        var violations: [VLMEvidenceViolation] = []

        if mediaRef.isEmpty || longEdgePx <= 0 || longEdgePx > 1024 || !exifStripped || !redactionApplied {
            violations.append(.privacyTierMismatch)
        }

        return violations
    }
}

struct VLMGroundedEntity: Codable, Equatable, Sendable {
    let entityRef: String
    let kind: VLMEntityKind
    let role: TargetEntityRole
    let region: NormalizedRect?
    let detectorLabel: String?
    let detectorConfidence: Double?
    let displayLabelCandidate: String
    let displayLabelConfidence: Double
}

struct SemanticTipDraftContext: Codable, Equatable, Sendable {
    let draftId: String
    let tipType: SemanticTipType?
    let actionType: SemanticActionType
    let actionFrame: SemanticActionFrame
    let targetEntityRef: String?
    let targetEntityKind: VLMEntityKind
    let targetEntityDisplayLabel: String
    let linkedIssueIds: [String]
    let linkedStrengthIds: [String]
    let linkedActionIds: [String]
    let priorityBand: SemanticTipPriorityBand?
}

struct NeuralEvidenceScoreSummary: Codable, Equatable, Sendable {
    let headId: EvidenceHeadId
    let score: Double?
    let confidence: Double
    let status: EvidenceHeadStatus
}

struct NeuralEvidenceSummary: Codable, Equatable, Sendable {
    let schemaVersion: String
    let availableHeadIds: [EvidenceHeadId]
    let unavailableHeadIds: [EvidenceHeadId]
    let notableScores: [NeuralEvidenceScoreSummary]
}

struct VLMVisualEvidenceLocalContext: Codable, Equatable, Sendable {
    let frameFeatureSnapshotExcerpt: [String: String]
    let sceneSemantics: SceneSemanticsReport
    let critique: CritiqueReport
    let recommendationPlan: RecommendationPlan
    let semanticTipDrafts: [SemanticTipDraftContext]
    let groundedEntities: [VLMGroundedEntity]
    let localNeuralEvidenceSummary: NeuralEvidenceSummary?
}

struct VLMAllowedSemanticCatalog: Codable, Equatable, Sendable {
    let catalogVersion: String
    let allowedEvidenceDimensions: [VLMVisualEvidenceDimension]
    let allowedVisualProblemTypes: [VisualProblemType]
    let allowedVisualStrengthTypes: [VisualStrengthType]
    let allowedSemanticActionTypes: [SemanticActionType]
    let allowedGroundedObjectDisplayLabels: [String]
    let allowedGenericDisplayLabels: [String]

    static let prS01 = VLMAllowedSemanticCatalog(
        catalogVersion: "PR-S01-2026-05-04",
        allowedEvidenceDimensions: VLMVisualEvidenceDimension.allCases,
        allowedVisualProblemTypes: VisualProblemType.allCases,
        allowedVisualStrengthTypes: VisualStrengthType.allCases,
        allowedSemanticActionTypes: SemanticActionType.allCases,
        allowedGroundedObjectDisplayLabels: Array(SemanticDisplayLabelPolicy.groundedObjectLabels).sorted(),
        allowedGenericDisplayLabels: Array(
            SemanticDisplayLabelPolicy.personLabels
                .union(SemanticDisplayLabelPolicy.genericObjectLabels)
                .union(SemanticDisplayLabelPolicy.relationLabels)
                .union(["кадр", "свет"])
        ).sorted()
    )
}

struct VLMVisualEvidenceConstraints: Codable, Equatable, Sendable {
    let maxObservations: Int
    let maxRelations: Int
    let maxSuggestedActionIds: Int
    let maxExplanationChars: Int
    let allowMoodPreservation: Bool
    let requireEntityGroundingForSpecificLabels: Bool
    let failClosedOnUnknownIds: Bool

    static let `default` = VLMVisualEvidenceConstraints(
        maxObservations: 8,
        maxRelations: 6,
        maxSuggestedActionIds: 4,
        maxExplanationChars: 600,
        allowMoodPreservation: true,
        requireEntityGroundingForSpecificLabels: true,
        failClosedOnUnknownIds: true
    )
}

struct VLMVisualEvidenceCorrelation: Codable, Equatable, Sendable {
    let localCritiqueSummaryId: String
    let localPlanSummaryId: String?
    let semanticCatalogVersion: String
    let offloadingSchemaVersion: String?
    let providerConfigVersion: String
    let sessionEphemeralId: String?
}

struct VLMVisualEvidenceRequest: Codable, Equatable, Sendable {
    let schemaVersion: VLMEvidenceSchemaVersion
    let requestId: String
    let frameId: String
    let mode: AnalysisMode
    let locale: String
    let privacyTier: VLMPrivacyTier
    let trigger: VLMTrigger?
    let visualInput: VLMVisualInput?
    let localContext: VLMVisualEvidenceLocalContext
    let allowedCatalog: VLMAllowedSemanticCatalog
    let constraints: VLMVisualEvidenceConstraints
    let correlation: VLMVisualEvidenceCorrelation

    func validate() -> [VLMEvidenceViolation] {
        var violations: [VLMEvidenceViolation] = []

        if requestId.isEmpty || frameId.isEmpty || localContext.critique.frameId != frameId || localContext.recommendationPlan.frameId != frameId {
            violations.append(.requestMismatch)
        }

        if mode != .pause || localContext.sceneSemantics.mode != .pause || localContext.critique.mode != .pause || localContext.recommendationPlan.mode != .pause {
            violations.append(.modeNotPause)
        }

        if constraints.maxObservations < 0 || constraints.maxRelations < 0 || constraints.maxSuggestedActionIds < 0 || constraints.maxExplanationChars < 0 {
            violations.append(.requestMismatch)
        }

        switch privacyTier {
        case .structuredOnly:
            if visualInput != nil {
                violations.append(.privacyTierMismatch)
            }
        case .redactedVisual:
            guard let visualInput else {
                violations.append(.privacyTierMismatch)
                break
            }
            violations.append(contentsOf: visualInput.validate())
        }

        return Array(Set(violations)).sortedByRawValue()
    }
}

struct VLMVisualEvidenceObservation: Codable, Equatable, Sendable {
    let observationId: String
    let dimension: VLMVisualEvidenceDimension
    let polarity: VLMEvidencePolarity
    let score: Double
    let confidence: Double
    let uncertaintyReasons: [VLMUncertaintyReason]
    let primaryEntityRef: String?
    let secondaryEntityRef: String?
    let visualProblemType: VisualProblemType?
    let visualStrengthType: VisualStrengthType?
    let supportedIssueIds: [String]
    let supportedStrengthIds: [String]
    let suggestedActionIds: [SemanticActionType]
    let evidenceNote: String?
}

struct VLMEntityRelation: Codable, Equatable, Sendable {
    let relationId: String
    let sourceEntityRef: String
    let targetEntityRef: String?
    let relationType: VLMEntityRelationType
    let dimension: VLMVisualEvidenceDimension
    let score: Double
    let confidence: Double
    let uncertaintyReasons: [VLMUncertaintyReason]
    let supportedObservationIds: [String]
}

struct VLMSecondaryExplanation: Codable, Equatable, Sendable {
    let language: String
    let summary: String
    let caveats: [String]
}

struct VLMEvidenceSafetyReport: Codable, Equatable, Sendable {
    let passed: Bool
    let violations: [VLMEvidenceViolation]
}

struct VLMEvidenceDiagnostics: Codable, Equatable, Sendable {
    let latencyMs: Int?
    let providerModelFamily: String?
    let providerModelVersion: String?
    let promptVersion: String
    let privacyTier: VLMPrivacyTier
    let fallbackReason: String?
}

struct VLMVisualEvidenceResponse: Codable, Equatable, Sendable {
    let schemaVersion: VLMEvidenceSchemaVersion
    let requestId: String
    let frameId: String
    let mode: AnalysisMode
    let providerId: String
    let status: VLMResponseStatus
    let primaryEntityRef: String?
    let primaryEntityKind: VLMEntityKind
    let primaryEntityDisplayLabelCandidate: String
    let primaryEntityLabelConfidence: Double
    let secondaryEntityRef: String?
    let secondaryEntityKind: VLMEntityKind?
    let secondaryEntityDisplayLabelCandidate: String?
    let secondaryEntityLabelConfidence: Double?
    let observations: [VLMVisualEvidenceObservation]
    let relations: [VLMEntityRelation]
    let suggestedActionIds: [SemanticActionType]
    let explanation: VLMSecondaryExplanation?
    let safety: VLMEvidenceSafetyReport
    let diagnostics: VLMEvidenceDiagnostics

    func validate(against request: VLMVisualEvidenceRequest) -> VLMEvidenceValidationResult {
        VLMVisualEvidenceValidator(request: request, response: self).validate()
    }
}

enum VLMEvidenceFallback: String, Codable, CaseIterable, Sendable {
    case useValidatedEvidence = "use_validated_evidence"
    case deterministicOnly = "deterministic_only"
    case deterministicWithGenericLabels = "deterministic_with_generic_labels"
}

struct VLMEvidenceValidationResult: Codable, Equatable, Sendable {
    let requestId: String
    let frameId: String
    let accepted: Bool
    let acceptedPrimaryEntityRef: String?
    let acceptedPrimaryEntityKind: VLMEntityKind?
    let acceptedSecondaryEntityRef: String?
    let acceptedSecondaryEntityKind: VLMEntityKind?
    let acceptedObservations: [VLMVisualEvidenceObservation]
    let acceptedRelations: [VLMEntityRelation]
    let acceptedSuggestedActionIds: [SemanticActionType]
    let acceptedPrimaryLabel: String
    let acceptedSecondaryLabel: String?
    let violations: [VLMEvidenceViolation]
    let fallback: VLMEvidenceFallback
}

private struct VLMVisualEvidenceValidator {
    let request: VLMVisualEvidenceRequest
    let response: VLMVisualEvidenceResponse

    func validate() -> VLMEvidenceValidationResult {
        var violations = request.validate()
        var hardReject = !violations.isEmpty

        if response.requestId != request.requestId || response.frameId != request.frameId || response.schemaVersion != request.schemaVersion {
            violations.append(.requestMismatch)
            hardReject = true
        }

        if response.mode != .pause || response.mode != request.mode {
            violations.append(.modeNotPause)
            hardReject = true
        }

        if response.diagnostics.privacyTier != request.privacyTier {
            violations.append(.privacyTierMismatch)
            hardReject = true
        }

        if response.status != .completed {
            hardReject = true
        }

        if !response.safety.passed {
            violations.append(contentsOf: response.safety.violations)
            hardReject = true
        }

        if response.explanation?.summary.count ?? 0 > request.constraints.maxExplanationChars {
            violations.append(.outputTooLong)
        }

        let allowedActions = Set(request.allowedCatalog.allowedSemanticActionTypes)
        let responseActionSet = Set(response.suggestedActionIds)
        if !responseActionSet.isSubset(of: allowedActions) {
            violations.append(.unknownActionId)
            hardReject = true
        }

        if response.suggestedActionIds.count > request.constraints.maxSuggestedActionIds {
            violations.append(.outputTooLong)
            hardReject = true
        }

        if responseActionSet.contains(.keepCurrentSetup) && responseActionSet.contains(where: { $0 != .keepCurrentSetup }) {
            violations.append(.contradictoryKeepAndCorrect)
            hardReject = true
        }

        let groundedEntityRefs = Set(request.localContext.groundedEntities.map(\.entityRef))
        if let primaryEntityRef = response.primaryEntityRef, !groundedEntityRefs.contains(primaryEntityRef) {
            violations.append(.unknownEntityRef)
            hardReject = true
        }
        if let secondaryEntityRef = response.secondaryEntityRef, !groundedEntityRefs.contains(secondaryEntityRef) {
            violations.append(.unknownEntityRef)
            hardReject = true
        }

        let labelResult = validateLabels(knownEntityRefs: groundedEntityRefs)
        violations.append(contentsOf: labelResult.violations)

        if response.observations.count > request.constraints.maxObservations || response.relations.count > request.constraints.maxRelations {
            violations.append(.outputTooLong)
        }

        if hardReject {
            return result(
                accepted: false,
                primaryEntityRef: nil,
                primaryEntityKind: nil,
                secondaryEntityRef: nil,
                secondaryEntityKind: nil,
                observations: [],
                relations: [],
                suggestedActionIds: [],
                primaryLabel: labelResult.primaryLabel,
                secondaryLabel: labelResult.secondaryLabel,
                violations: violations,
                fallback: .deterministicOnly
            )
        }

        let acceptedObservations = validateObservations(violations: &violations, allowedActions: allowedActions, groundedEntityRefs: groundedEntityRefs)
        let acceptedObservationIds = Set(acceptedObservations.map(\.observationId))
        let acceptedRelations = validateRelations(violations: &violations,
                                                  groundedEntityRefs: groundedEntityRefs,
                                                  acceptedObservationIds: acceptedObservationIds)

        if acceptedObservations.isEmpty {
            return result(
                accepted: false,
                primaryEntityRef: nil,
                primaryEntityKind: nil,
                secondaryEntityRef: nil,
                secondaryEntityKind: nil,
                observations: [],
                relations: [],
                suggestedActionIds: [],
                primaryLabel: labelResult.primaryLabel,
                secondaryLabel: labelResult.secondaryLabel,
                violations: violations,
                fallback: .deterministicOnly
            )
        }

        let fallback: VLMEvidenceFallback = labelResult.requiresGenericFallback ? .deterministicWithGenericLabels : .useValidatedEvidence
        return result(
            accepted: true,
            primaryEntityRef: response.primaryEntityRef,
            primaryEntityKind: response.primaryEntityKind,
            secondaryEntityRef: response.secondaryEntityRef,
            secondaryEntityKind: response.secondaryEntityKind,
            observations: acceptedObservations,
            relations: acceptedRelations,
            suggestedActionIds: response.suggestedActionIds,
            primaryLabel: labelResult.primaryLabel,
            secondaryLabel: labelResult.secondaryLabel,
            violations: violations,
            fallback: fallback
        )
    }

    private func validateLabels(knownEntityRefs: Set<String>) -> (primaryLabel: String, secondaryLabel: String?, requiresGenericFallback: Bool, violations: [VLMEvidenceViolation]) {
        var violations: [VLMEvidenceViolation] = []
        var requiresGenericFallback = false

        let primary = acceptedLabel(
            candidate: response.primaryEntityDisplayLabelCandidate,
            confidence: response.primaryEntityLabelConfidence,
            entityRef: response.primaryEntityRef,
            kind: response.primaryEntityKind,
            role: .primarySubject,
            knownEntityRefs: knownEntityRefs,
            violations: &violations,
            requiresGenericFallback: &requiresGenericFallback
        )

        let secondary: String?
        if let secondaryCandidate = response.secondaryEntityDisplayLabelCandidate,
           let secondaryKind = response.secondaryEntityKind {
            secondary = acceptedLabel(
                candidate: secondaryCandidate,
                confidence: response.secondaryEntityLabelConfidence ?? 0.0,
                entityRef: response.secondaryEntityRef,
                kind: secondaryKind,
                role: .distractingObject,
                knownEntityRefs: knownEntityRefs,
                violations: &violations,
                requiresGenericFallback: &requiresGenericFallback
            )
        } else {
            secondary = nil
        }

        return (primary, secondary, requiresGenericFallback, violations)
    }

    private func acceptedLabel(candidate: String,
                               confidence: Double,
                               entityRef: String?,
                               kind: VLMEntityKind,
                               role: TargetEntityRole,
                               knownEntityRefs: Set<String>,
                               violations: inout [VLMEvidenceViolation],
                               requiresGenericFallback: inout Bool) -> String {
        let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let targetKind = kind.targetEntityKind
        let generic = SemanticDisplayLabelPolicy.displayLabel(
            entityKind: targetKind,
            role: role,
            groundedLabel: nil,
            confidence: 0.0
        )

        guard isAllowedDisplayLabelByContract(normalized) else {
            violations.append(.unsafeSpecificLabel)
            requiresGenericFallback = true
            return generic
        }

        if request.allowedCatalog.allowedGroundedObjectDisplayLabels.contains(normalized) {
            let isGrounded = entityRef.map { knownEntityRefs.contains($0) } ?? false
            let matchesStructuredOnlySource = request.privacyTier == .redactedVisual || request.localContext.groundedEntities.contains {
                $0.entityRef == entityRef && normalizeDisplayLabel($0.displayLabelCandidate) == normalized
            }

            if confidence < 0.75 || !isGrounded || !matchesStructuredOnlySource {
                violations.append(isGrounded ? .unsafeSpecificLabel : .labelWithoutGrounding)
                requiresGenericFallback = true
                return generic
            }
        }

        return normalized
    }

    private func isAllowedDisplayLabelByContract(_ label: String) -> Bool {
        SemanticDisplayLabelPolicy.isAllowedDisplayLabel(label)
            && (
                request.allowedCatalog.allowedGenericDisplayLabels.contains(label)
                || request.allowedCatalog.allowedGroundedObjectDisplayLabels.contains(label)
            )
    }

    private func normalizeDisplayLabel(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func validateObservations(violations: inout [VLMEvidenceViolation],
                                      allowedActions: Set<SemanticActionType>,
                                      groundedEntityRefs: Set<String>) -> [VLMVisualEvidenceObservation] {
        let issueIds = Set(request.localContext.critique.issues.map(\.id))
        let strengthIds = Set(request.localContext.critique.strengths.map(\.id))
        var seenObservationIds: Set<String> = []

        return response.observations.prefix(request.constraints.maxObservations).compactMap { observation in
            var isValid = true

            if observation.observationId.isEmpty || seenObservationIds.contains(observation.observationId) {
                isValid = false
            }
            seenObservationIds.insert(observation.observationId)

            if !request.allowedCatalog.allowedEvidenceDimensions.contains(observation.dimension) {
                violations.append(.unknownDimension)
                isValid = false
            }

            if !isUnitRange(observation.score) || !isUnitRange(observation.confidence) {
                violations.append(.outputTooLong)
                isValid = false
            }

            if observation.confidence < 0.45 && observation.uncertaintyReasons.isEmpty {
                isValid = false
            }

            if let primaryEntityRef = observation.primaryEntityRef, !groundedEntityRefs.contains(primaryEntityRef) {
                violations.append(.unknownEntityRef)
                isValid = false
            }

            if let secondaryEntityRef = observation.secondaryEntityRef, !groundedEntityRefs.contains(secondaryEntityRef) {
                violations.append(.unknownEntityRef)
                isValid = false
            }

            switch observation.polarity {
            case .supportsProblem:
                if observation.visualProblemType == nil || !observation.supportedStrengthIds.isEmpty {
                    violations.append(.unknownProblemType)
                    isValid = false
                }
            case .supportsStrength:
                if observation.visualStrengthType == nil || !observation.supportedIssueIds.isEmpty {
                    violations.append(.unknownStrengthType)
                    isValid = false
                }
            case .neutralContext:
                break
            }

            if let visualProblemType = observation.visualProblemType,
               !request.allowedCatalog.allowedVisualProblemTypes.contains(visualProblemType) {
                violations.append(.unknownProblemType)
                isValid = false
            }

            if let visualStrengthType = observation.visualStrengthType,
               !request.allowedCatalog.allowedVisualStrengthTypes.contains(visualStrengthType) {
                violations.append(.unknownStrengthType)
                isValid = false
            }

            if observation.supportedIssueIds.contains(where: { !issueIds.contains($0) }) {
                violations.append(.unknownIssueId)
                isValid = false
            }

            if observation.supportedStrengthIds.contains(where: { !strengthIds.contains($0) }) {
                violations.append(.unknownStrengthId)
                isValid = false
            }

            if !Set(observation.suggestedActionIds).isSubset(of: allowedActions)
                || !Set(observation.suggestedActionIds).isSubset(of: Set(response.suggestedActionIds)) {
                violations.append(.unknownActionId)
                isValid = false
            }

            return isValid ? observation : nil
        }
    }

    private func validateRelations(violations: inout [VLMEvidenceViolation],
                                   groundedEntityRefs: Set<String>,
                                   acceptedObservationIds: Set<String>) -> [VLMEntityRelation] {
        var seenRelationIds: Set<String> = []

        return response.relations.prefix(request.constraints.maxRelations).compactMap { relation in
            var isValid = true

            if relation.relationId.isEmpty || seenRelationIds.contains(relation.relationId) {
                isValid = false
            }
            seenRelationIds.insert(relation.relationId)

            if !groundedEntityRefs.contains(relation.sourceEntityRef) {
                violations.append(.unknownEntityRef)
                isValid = false
            }

            if let targetEntityRef = relation.targetEntityRef, !groundedEntityRefs.contains(targetEntityRef) {
                violations.append(.unknownEntityRef)
                isValid = false
            }

            if !request.allowedCatalog.allowedEvidenceDimensions.contains(relation.dimension) {
                violations.append(.unknownDimension)
                isValid = false
            }

            if !isUnitRange(relation.score) || !isUnitRange(relation.confidence) {
                violations.append(.outputTooLong)
                isValid = false
            }

            if relation.supportedObservationIds.isEmpty || relation.supportedObservationIds.contains(where: { !acceptedObservationIds.contains($0) }) {
                isValid = false
            }

            return isValid ? relation : nil
        }
    }

    private func result(accepted: Bool,
                        primaryEntityRef: String?,
                        primaryEntityKind: VLMEntityKind?,
                        secondaryEntityRef: String?,
                        secondaryEntityKind: VLMEntityKind?,
                        observations: [VLMVisualEvidenceObservation],
                        relations: [VLMEntityRelation],
                        suggestedActionIds: [SemanticActionType],
                        primaryLabel: String,
                        secondaryLabel: String?,
                        violations: [VLMEvidenceViolation],
                        fallback: VLMEvidenceFallback) -> VLMEvidenceValidationResult {
        VLMEvidenceValidationResult(
            requestId: request.requestId,
            frameId: request.frameId,
            accepted: accepted,
            acceptedPrimaryEntityRef: primaryEntityRef,
            acceptedPrimaryEntityKind: primaryEntityKind,
            acceptedSecondaryEntityRef: secondaryEntityRef,
            acceptedSecondaryEntityKind: secondaryEntityKind,
            acceptedObservations: observations,
            acceptedRelations: relations,
            acceptedSuggestedActionIds: suggestedActionIds,
            acceptedPrimaryLabel: primaryLabel,
            acceptedSecondaryLabel: secondaryLabel,
            violations: Array(Set(violations)).sortedByRawValue(),
            fallback: fallback
        )
    }

    private func isUnitRange(_ value: Double) -> Bool {
        value.isFinite && value >= 0.0 && value <= 1.0
    }
}

private extension VLMEntityKind {
    var targetEntityKind: TargetEntityKind {
        switch self {
        case .person:
            return .person
        case .face:
            return .face
        case .object:
            return .object
        case .prop:
            return .prop
        case .backgroundArea:
            return .backgroundArea
        case .lightSource:
            return .lightSource
        case .frame:
            return .frame
        case .unknown:
            return .unknown
        }
    }
}

private extension Array where Element == VLMEvidenceViolation {
    func sortedByRawValue() -> [VLMEvidenceViolation] {
        sorted { $0.rawValue < $1.rawValue }
    }
}
