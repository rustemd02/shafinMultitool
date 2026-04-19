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

// MARK: - Contract 5: ExplainabilityTrace

enum TraceStage: String, Codable, Sendable {
    case observation
    case interpretation
    case recommendation
}

enum TraceSourceKind: String, Codable, Sendable {
    case snapshotSignal = "snapshot_signal"
    case semanticsSignal = "semantics_signal"
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
