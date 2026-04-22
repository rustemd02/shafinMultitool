import Foundation

protocol DeepCriticProvider: Sendable {
    var providerId: String { get }
    var capabilities: DeepCriticCapabilities { get }

    func review(request: DeepCriticTransportEnvelope) async throws -> DeepCriticResponse
}

struct DeepCriticCapabilities: Equatable, Sendable {
    let supportsStructuredOnly: Bool
    let supportsRedactedVisual: Bool
    let supportsRussian: Bool
    let maxRequestBytes: Int
    let maxResponseBytes: Int
    let allowsTeacherEvidence: Bool
}

struct DeepCriticConstraints: Equatable, Sendable, Codable {
    let maxLatencyMs: Int
    let allowTextRefinement: Bool
    let allowTeacherEvidence: Bool
    let allowActionReorderingAdvice: Bool

    static let automaticDefault = DeepCriticConstraints(
        maxLatencyMs: 2_500,
        allowTextRefinement: false,
        allowTeacherEvidence: false,
        allowActionReorderingAdvice: false
    )

    init(maxLatencyMs: Int,
         allowTextRefinement: Bool,
         allowTeacherEvidence: Bool,
         allowActionReorderingAdvice: Bool) {
        self.maxLatencyMs = min(6_000, max(250, maxLatencyMs))
        self.allowTextRefinement = allowTextRefinement
        self.allowTeacherEvidence = allowTeacherEvidence
        self.allowActionReorderingAdvice = allowActionReorderingAdvice
    }
}

struct DeepCriticCorrelation: Equatable, Sendable, Codable {
    let localCritiqueSummaryId: String
    let localPlanSummaryId: String?
    let localNeuralBundleVersion: String?
    let sessionEphemeralId: String
}

enum DeepCriticTrigger: String, Codable, Equatable, Sendable {
    case explicitUserRequest = "explicit_user_request"
    case ambiguousLocalCase = "ambiguous_local_case"
    case fusionDisagreementProbe = "fusion_disagreement_probe"
    case partialLocalFailure = "partial_local_failure"
    case evalSampling = "eval_sampling"
}

enum DeepCriticPrivacyTier: String, Codable, Equatable, Sendable {
    case structuredOnly = "structured_only"
    case redactedVisual = "redacted_visual"
}

struct DeepCriticTraceFact: Codable, Equatable, Sendable {
    let refId: String
    let kind: String
    let message: String
}

struct DeepCriticTraceExcerpt: Codable, Equatable, Sendable {
    let observations: [DeepCriticTraceFact]
    let interpretations: [DeepCriticTraceFact]
    let recommendations: [DeepCriticTraceFact]

    var allFacts: [DeepCriticTraceFact] {
        observations + interpretations + recommendations
    }
}

enum DeepCriticVisualAttachmentCandidateKind: String, Codable, Equatable, Sendable {
    case frame
    case subjectCrop = "subject_crop"
}

struct DeepCriticVisualAttachmentCandidate: Codable, Equatable, Sendable {
    let kind: DeepCriticVisualAttachmentCandidateKind
    let pixelWidth: Int
    let pixelHeight: Int
    let hasExif: Bool
    let bytes: Data
}

struct DeepCriticLocalBundle: Equatable, Sendable {
    let semantics: SceneSemanticsReport
    let critique: CritiqueReport
    let plan: RecommendationPlan
    let fusedNeuralEvidence: NeuralEvidenceSnapshot?
    let neuralMetadata: NeuralEvidenceRuntimeMetadata?
    let traceExcerpt: DeepCriticTraceExcerpt?
    let visualAttachmentCandidate: DeepCriticVisualAttachmentCandidate?
}

struct DeepCriticOffloadRequest: Equatable, Sendable {
    let requestId: String
    let frameId: String
    let mode: AnalysisMode
    let locale: String
    let trigger: DeepCriticTrigger
    let preferredPrivacyTier: DeepCriticPrivacyTier
    let localBundle: DeepCriticLocalBundle
    let constraints: DeepCriticConstraints
    let correlation: DeepCriticCorrelation
}

struct DeepCriticPolicyContext: Equatable, Sendable {
    let featureEnabled: Bool
    let networkAvailable: Bool
    let backgroundRemoteWorkAllowed: Bool
    let visualConsentGranted: Bool
    let positiveTriggerSatisfied: Bool
    let currentPauseFrameId: String?
    let reasoningProviderActive: Bool

    static let `default` = DeepCriticPolicyContext(
        featureEnabled: true,
        networkAvailable: true,
        backgroundRemoteWorkAllowed: true,
        visualConsentGranted: false,
        positiveTriggerSatisfied: true,
        currentPauseFrameId: nil,
        reasoningProviderActive: false
    )
}

struct DeepCriticSceneContext: Codable, Equatable, Sendable {
    let sceneTypeId: String
    let primarySubjectKind: String
    let primarySubjectConfidence: Double
}

struct DeepCriticCritiqueSummary: Codable, Equatable, Sendable {
    let verdict: String
    let shortVerdict: String
    let whyGood: [String]
    let whyProblematic: [String]
    let fallbackUsed: Bool
}

struct DeepCriticIssuePayload: Codable, Equatable, Sendable {
    let issueId: String
    let issueType: String
    let severity: String
    let confidence: Double
    let affectedRegionKind: String?
}

struct DeepCriticStrengthPayload: Codable, Equatable, Sendable {
    let strengthId: String
    let strengthType: String
    let confidence: Double
}

struct DeepCriticActionPayload: Codable, Equatable, Sendable {
    let actionId: String
    let actionType: String
    let priority: Int
    let targetRegionKind: String?
}

enum DeepCriticVisualAttachmentKind: String, Codable, Equatable, Sendable {
    case redactedFrame = "redacted_frame"
    case redactedSubjectCrop = "redacted_subject_crop"
}

struct DeepCriticVisualAttachment: Codable, Equatable, Sendable {
    let attachmentKind: DeepCriticVisualAttachmentKind
    let mimeType: String
    let width: Int
    let height: Int
    let redactionProfile: String
    let payloadData: Data?
    let transportHandle: String?

    var hasUsablePayload: Bool {
        (payloadData?.isEmpty == false) || !(transportHandle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
    }
}

struct DeepCriticStructuredPayload: Codable, Equatable, Sendable {
    let sceneContext: DeepCriticSceneContext
    let critiqueSummary: DeepCriticCritiqueSummary
    let issues: [DeepCriticIssuePayload]
    let strengths: [DeepCriticStrengthPayload]
    let actions: [DeepCriticActionPayload]
    let neuralEvidence: NeuralEvidenceSnapshot?
    let traceExcerpt: DeepCriticTraceExcerpt?
}

struct DeepCriticTransportEnvelope: Codable, Equatable, Sendable {
    let schemaVersion: String
    let requestId: String
    let frameId: String
    let locale: String
    let trigger: DeepCriticTrigger
    let privacyTier: DeepCriticPrivacyTier
    let payload: DeepCriticStructuredPayload
    let visualAttachment: DeepCriticVisualAttachment?
    let constraints: DeepCriticConstraints

    static let currentSchemaVersion = "h12.v1"
}

enum DeepCriticResponseStatus: String, Codable, Equatable, Sendable {
    case completed
    case refused
    case unavailable
}

enum DeepCriticFailureReason: String, Codable, Equatable, Sendable {
    case policyRefused = "policy_refused"
    case capabilityMismatch = "capability_mismatch"
    case timeout
    case transportError = "transport_error"
    case validationFailed = "validation_failed"
    case unknown
}

enum DeepCriticDisposition: String, Codable, Equatable, Sendable {
    case noChange = "no_change"
    case advisoryRefinement = "advisory_refinement"
    case advisoryDisagreement = "advisory_disagreement"
    case hardCaseFlag = "hard_case_flag"
}

enum DeepCriticTargetKind: String, Codable, Equatable, Sendable {
    case issue
    case strength
}

enum DeepCriticFindingVerdict: String, Codable, Equatable, Sendable {
    case reinforce
    case soften
    case unclear
}

struct DeepCriticFindingReview: Codable, Equatable, Sendable {
    let targetId: String
    let targetKind: DeepCriticTargetKind
    let verdict: DeepCriticFindingVerdict
    let suggestedDelta: Double?
    let rationale: String
    let evidenceRefs: [String]
}

enum DeepCriticActionVerdict: String, Codable, Equatable, Sendable {
    case reinforce
    case deprioritize
    case unclear
}

struct DeepCriticActionReview: Codable, Equatable, Sendable {
    let actionId: String
    let verdict: DeepCriticActionVerdict
    let rationale: String
    let evidenceRefs: [String]
}

struct DeepCriticExplanationPatchEntry: Codable, Equatable, Sendable {
    let targetId: String
    let text: String
    let evidenceRefs: [String]
}

struct DeepCriticExplanationPatch: Codable, Equatable, Sendable {
    let shortVerdictOverride: String?
    let shortVerdictEvidenceRefs: [String]
    let whyGoodByStrengthId: [DeepCriticExplanationPatchEntry]
    let whyProblematicByIssueId: [DeepCriticExplanationPatchEntry]
    let actionRationaleByActionId: [DeepCriticExplanationPatchEntry]

    static let empty = DeepCriticExplanationPatch(
        shortVerdictOverride: nil,
        shortVerdictEvidenceRefs: [],
        whyGoodByStrengthId: [],
        whyProblematicByIssueId: [],
        actionRationaleByActionId: []
    )

    var isEmpty: Bool {
        let shortVerdictEmpty = shortVerdictOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return shortVerdictEmpty
            && shortVerdictEvidenceRefs.isEmpty
            && whyGoodByStrengthId.isEmpty
            && whyProblematicByIssueId.isEmpty
            && actionRationaleByActionId.isEmpty
    }
}

struct DeepCriticAdvisory: Codable, Equatable, Sendable {
    let disposition: DeepCriticDisposition
    let issueReviews: [DeepCriticFindingReview]
    let strengthReviews: [DeepCriticFindingReview]
    let actionReviews: [DeepCriticActionReview]
    let explanationPatch: DeepCriticExplanationPatch?
    let teacherEvidence: NeuralEvidenceSnapshot?
    let teacherEvidenceMetadata: NeuralEvidenceRuntimeMetadata?
    let hardCaseTags: [String]
    let confidence: Double

    var hasUsableContent: Bool {
        !issueReviews.isEmpty
            || !strengthReviews.isEmpty
            || !actionReviews.isEmpty
            || !(explanationPatch?.isEmpty ?? true)
            || teacherEvidence != nil
            || !hardCaseTags.isEmpty
    }
}

struct DeepCriticResponse: Codable, Equatable, Sendable {
    let schemaVersion: String
    let responseId: String
    let requestId: String
    let frameId: String
    let status: DeepCriticResponseStatus
    let advisory: DeepCriticAdvisory?
    let failureReason: DeepCriticFailureReason?
    let producedAt: Date
}

enum DeepCriticOffloadOutcomeKind: String, Equatable, Sendable {
    case disabled
    case notTriggered = "not_triggered"
    case blocked
    case completed
    case failed
}

struct DeepCriticFailure: Equatable, Sendable {
    let reason: DeepCriticFailureReason
}

enum DeepCriticOffloadOutcome: Sendable {
    case disabled
    case notTriggered
    case blocked
    case completed(response: DeepCriticResponse)
    case failed(DeepCriticFailure)

    var kind: DeepCriticOffloadOutcomeKind {
        switch self {
        case .disabled:
            return .disabled
        case .notTriggered:
            return .notTriggered
        case .blocked:
            return .blocked
        case .completed:
            return .completed
        case .failed:
            return .failed
        }
    }
}

struct DeepCriticRecordedOutcome: Equatable, Sendable {
    let kind: DeepCriticOffloadOutcomeKind
    let response: DeepCriticResponse?
    let failure: DeepCriticFailure?

    init(_ outcome: DeepCriticOffloadOutcome) {
        kind = outcome.kind
        switch outcome {
        case let .completed(response):
            self.response = response
            failure = nil
        case let .failed(failure):
            response = nil
            self.failure = failure
        case .disabled, .notTriggered, .blocked:
            response = nil
            failure = nil
        }
    }
}

private enum DeepCriticProviderCallResult {
    case success(DeepCriticResponse)
    case failed(Error)
    case timedOut
    case cancelled
}

private struct DeepCriticValidationResult {
    let sanitizedResponse: DeepCriticResponse?
    let failureReason: DeepCriticFailureReason?
}

actor DeepCriticOffloadingCoordinator {
    typealias PauseStateProvider = @Sendable () async -> String?
    private static let maxRedactedVisualLongEdgePx = 1_024

    private let provider: DeepCriticProvider?
    private let currentPauseFrameProvider: PauseStateProvider?

    init(provider: DeepCriticProvider?,
         currentPauseFrameProvider: PauseStateProvider? = nil) {
        self.provider = provider
        self.currentPauseFrameProvider = currentPauseFrameProvider
    }

    func offload(request originalRequest: DeepCriticOffloadRequest,
                 context: DeepCriticPolicyContext) async -> DeepCriticOffloadOutcome {
        guard context.featureEnabled, let provider else {
            return .disabled
        }

        let request = normalizedRequest(originalRequest, context: context)

        guard request.mode == .pause else {
            return .notTriggered
        }

        guard isLocalBundleReady(request) else {
            return .notTriggered
        }

        guard !request.frameId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let currentPauseFrameId = context.currentPauseFrameId,
              currentPauseFrameId == request.frameId,
              context.positiveTriggerSatisfied else {
            return .notTriggered
        }

        guard let envelope = makeTransportEnvelope(request: request,
                                                   context: context,
                                                   provider: provider) else {
            return .blocked
        }

        let result = await callProviderWithTimeout(provider: provider, request: envelope)
        switch result {
        case .cancelled:
            return .failed(DeepCriticFailure(reason: .unknown))
        case .timedOut:
            return .failed(DeepCriticFailure(reason: .timeout))
        case .failed:
            return .failed(DeepCriticFailure(reason: .transportError))
        case let .success(response):
            guard !responseExceedsMaxBytes(response, capabilities: provider.capabilities),
                  await isPauseStateCurrent(requestFrameId: request.frameId, fallbackContext: context) else {
                return .failed(DeepCriticFailure(reason: .validationFailed))
            }
            guard validateResponseEnvelope(response, request: request) else {
                return .failed(DeepCriticFailure(reason: .validationFailed))
            }
            switch response.status {
            case .refused:
                return .failed(DeepCriticFailure(reason: .policyRefused))
            case .unavailable:
                return .failed(DeepCriticFailure(reason: response.failureReason ?? .capabilityMismatch))
            case .completed:
                let validation = validateAndSanitize(response: response, request: request)
                if let sanitizedResponse = validation.sanitizedResponse {
                    return .completed(response: sanitizedResponse)
                }
                return .failed(DeepCriticFailure(reason: validation.failureReason ?? .validationFailed))
            }
        }
    }

    private func normalizedRequest(_ request: DeepCriticOffloadRequest,
                                   context: DeepCriticPolicyContext) -> DeepCriticOffloadRequest {
        guard context.reasoningProviderActive, request.constraints.allowTextRefinement else {
            return request
        }

        let normalizedConstraints = DeepCriticConstraints(
            maxLatencyMs: request.constraints.maxLatencyMs,
            allowTextRefinement: false,
            allowTeacherEvidence: request.constraints.allowTeacherEvidence,
            allowActionReorderingAdvice: request.constraints.allowActionReorderingAdvice
        )

        return DeepCriticOffloadRequest(
            requestId: request.requestId,
            frameId: request.frameId,
            mode: request.mode,
            locale: request.locale,
            trigger: request.trigger,
            preferredPrivacyTier: request.preferredPrivacyTier,
            localBundle: request.localBundle,
            constraints: normalizedConstraints,
            correlation: request.correlation
        )
    }

    private func isLocalBundleReady(_ request: DeepCriticOffloadRequest) -> Bool {
        let semantics = request.localBundle.semantics
        let critique = request.localBundle.critique
        let plan = request.localBundle.plan

        guard semantics.frameId == request.frameId,
              semantics.mode == request.mode,
              critique.frameId == request.frameId,
              critique.mode == request.mode,
              plan.frameId == request.frameId,
              plan.mode == request.mode else {
            return false
        }

        if !semantics.validate(expectedFrameId: request.frameId).isEmpty {
            return false
        }

        if !critique.validate(expectedFrameId: request.frameId).isEmpty {
            return false
        }

        let availableIssueIds = Set(critique.issues.map(\.id))
        if !plan.validate(expectedFrameId: request.frameId, availableIssueIds: availableIssueIds).isEmpty {
            return false
        }

        if let neural = request.localBundle.fusedNeuralEvidence,
           let metadata = request.localBundle.neuralMetadata,
           !neural.validate(expectedFrameId: request.frameId,
                            semanticsReport: semantics,
                            runtimeMetadata: metadata).isEmpty {
            return false
        }

        return true
    }

    private func makeTransportEnvelope(request: DeepCriticOffloadRequest,
                                       context: DeepCriticPolicyContext,
                                       provider: DeepCriticProvider) -> DeepCriticTransportEnvelope? {
        guard context.networkAvailable, context.backgroundRemoteWorkAllowed else {
            return nil
        }

        switch request.preferredPrivacyTier {
        case .structuredOnly:
            guard provider.capabilities.supportsStructuredOnly else { return nil }
        case .redactedVisual:
            guard request.trigger == .explicitUserRequest,
                  context.visualConsentGranted,
                  provider.capabilities.supportsRedactedVisual,
                  let candidate = request.localBundle.visualAttachmentCandidate,
                  candidate.pixelWidth > 0,
                  candidate.pixelHeight > 0,
                  max(candidate.pixelWidth, candidate.pixelHeight) <= Self.maxRedactedVisualLongEdgePx,
                  !candidate.hasExif,
                  !candidate.bytes.isEmpty else {
                return nil
            }
        }

        if request.constraints.allowTeacherEvidence && !provider.capabilities.allowsTeacherEvidence {
            return nil
        }

        if request.locale.lowercased().hasPrefix("ru"), !provider.capabilities.supportsRussian {
            return nil
        }

        let sceneContext = DeepCriticSceneContext(
            sceneTypeId: request.localBundle.semantics.sceneType.rawValue,
            primarySubjectKind: request.localBundle.semantics.primarySubject.kind.rawValue,
            primarySubjectConfidence: request.localBundle.semantics.primarySubject.confidence
        )

        let critiqueSummary = DeepCriticCritiqueSummary(
            verdict: request.localBundle.critique.verdict.rawValue,
            shortVerdict: request.localBundle.critique.summary.shortVerdict,
            whyGood: nonEmptyArray(from: request.localBundle.critique.summary.whyGood),
            whyProblematic: nonEmptyArray(from: request.localBundle.critique.summary.whyProblematic),
            fallbackUsed: request.localBundle.critique.fallbackUsed
        )

        let issues = request.localBundle.critique.issues.map { issue in
            DeepCriticIssuePayload(
                issueId: issue.id,
                issueType: issue.type.rawValue,
                severity: issue.severity >= CritiqueReport.criticalIssueThreshold ? "high" : (issue.severity >= 0.4 ? "medium" : "low"),
                confidence: issue.confidence,
                affectedRegionKind: issue.affectedRegion == nil ? nil : "normalized_rect"
            )
        }

        let strengths = request.localBundle.critique.strengths.map { strength in
            DeepCriticStrengthPayload(
                strengthId: strength.id,
                strengthType: strength.type.rawValue,
                confidence: strength.confidence
            )
        }

        let allActions = [request.localBundle.plan.primaryAction].compactMap { $0 }
            + request.localBundle.plan.secondaryActions
            + request.localBundle.plan.deferredActions
        let actions = allActions.map { action in
            DeepCriticActionPayload(
                actionId: action.id,
                actionType: action.actionType.rawValue,
                priority: action.priority,
                targetRegionKind: action.targetRegion == nil ? nil : "normalized_rect"
            )
        }

        let payload = DeepCriticStructuredPayload(
            sceneContext: sceneContext,
            critiqueSummary: critiqueSummary,
            issues: issues,
            strengths: strengths,
            actions: actions,
            neuralEvidence: request.localBundle.fusedNeuralEvidence,
            traceExcerpt: request.localBundle.traceExcerpt
        )

        let visualAttachment: DeepCriticVisualAttachment?
        switch request.preferredPrivacyTier {
        case .structuredOnly:
            visualAttachment = nil
        case .redactedVisual:
            guard let candidate = request.localBundle.visualAttachmentCandidate else {
                return nil
            }
            visualAttachment = DeepCriticVisualAttachment(
                attachmentKind: candidate.kind == .frame ? .redactedFrame : .redactedSubjectCrop,
                mimeType: "image/jpeg",
                width: candidate.pixelWidth,
                height: candidate.pixelHeight,
                redactionProfile: "subject_focus_v1",
                payloadData: candidate.bytes,
                transportHandle: nil
            )
        }

        let envelope = DeepCriticTransportEnvelope(
            schemaVersion: DeepCriticTransportEnvelope.currentSchemaVersion,
            requestId: request.requestId,
            frameId: request.frameId,
            locale: request.locale,
            trigger: request.trigger,
            privacyTier: request.preferredPrivacyTier,
            payload: payload,
            visualAttachment: visualAttachment,
            constraints: request.constraints
        )

        if let data = try? JSONEncoder().encode(envelope),
           data.count > provider.capabilities.maxRequestBytes {
            return nil
        }

        return envelope
    }

    private func callProviderWithTimeout(provider: DeepCriticProvider,
                                         request: DeepCriticTransportEnvelope) async -> DeepCriticProviderCallResult {
        let timeoutNs = UInt64(max(250, request.constraints.maxLatencyMs)) * 1_000_000
        return await withTaskGroup(of: DeepCriticProviderCallResult.self) { group in
            group.addTask {
                if Task.isCancelled { return .cancelled }
                do {
                    return .success(try await provider.review(request: request))
                } catch {
                    return .failed(error)
                }
            }

            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNs)
                } catch {
                    if Task.isCancelled { return .cancelled }
                }
                return Task.isCancelled ? .cancelled : .timedOut
            }

            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    private func responseExceedsMaxBytes(_ response: DeepCriticResponse,
                                         capabilities: DeepCriticCapabilities) -> Bool {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(response) else {
            return true
        }
        return data.count > capabilities.maxResponseBytes
    }

    private func isPauseStateCurrent(requestFrameId: String,
                                     fallbackContext: DeepCriticPolicyContext) async -> Bool {
        let currentPauseFrameId: String?
        if let currentPauseFrameProvider {
            currentPauseFrameId = await currentPauseFrameProvider()
        } else {
            currentPauseFrameId = fallbackContext.currentPauseFrameId
        }

        guard let currentPauseFrameId else {
            return false
        }
        return currentPauseFrameId == requestFrameId
    }

    private func validateResponseEnvelope(_ response: DeepCriticResponse,
                                          request: DeepCriticOffloadRequest) -> Bool {
        guard response.schemaVersion == DeepCriticTransportEnvelope.currentSchemaVersion,
              response.requestId == request.requestId,
              response.frameId == request.frameId else {
            return false
        }

        switch response.status {
        case .completed:
            return response.advisory != nil
        case .refused, .unavailable:
            return response.advisory == nil
        }
    }

    private func validateAndSanitize(response: DeepCriticResponse,
                                     request: DeepCriticOffloadRequest) -> DeepCriticValidationResult {
        guard response.schemaVersion == DeepCriticTransportEnvelope.currentSchemaVersion,
              response.requestId == request.requestId,
              response.frameId == request.frameId,
              response.status == .completed,
              var advisory = response.advisory else {
            return DeepCriticValidationResult(sanitizedResponse: nil, failureReason: .validationFailed)
        }

        let knownIssueIds = Set(request.localBundle.critique.issues.map(\.id))
        let knownStrengthIds = Set(request.localBundle.critique.strengths.map(\.id))
        let allActions = [request.localBundle.plan.primaryAction].compactMap { $0 }
            + request.localBundle.plan.secondaryActions
            + request.localBundle.plan.deferredActions
        let knownActionIds = Set(allActions.map(\.id))
        let allowedEvidenceRefs = makeAllowedEvidenceRefs(for: request)

        if !validateFindingReviews(advisory.issueReviews,
                                   expectedKind: .issue,
                                   allowedIds: knownIssueIds,
                                   allowedEvidenceRefs: allowedEvidenceRefs) {
            return DeepCriticValidationResult(sanitizedResponse: nil, failureReason: .validationFailed)
        }

        if !validateFindingReviews(advisory.strengthReviews,
                                   expectedKind: .strength,
                                   allowedIds: knownStrengthIds,
                                   allowedEvidenceRefs: allowedEvidenceRefs) {
            return DeepCriticValidationResult(sanitizedResponse: nil, failureReason: .validationFailed)
        }

        if request.constraints.allowActionReorderingAdvice {
            if !validateActionReviews(advisory.actionReviews,
                                      allowedIds: knownActionIds,
                                      allowedEvidenceRefs: allowedEvidenceRefs) {
                return DeepCriticValidationResult(sanitizedResponse: nil, failureReason: .validationFailed)
            }
        } else {
            advisory = DeepCriticAdvisory(
                disposition: advisory.disposition,
                issueReviews: advisory.issueReviews,
                strengthReviews: advisory.strengthReviews,
                actionReviews: [],
                explanationPatch: advisory.explanationPatch,
                teacherEvidence: advisory.teacherEvidence,
                teacherEvidenceMetadata: advisory.teacherEvidenceMetadata,
                hardCaseTags: advisory.hardCaseTags,
                confidence: advisory.confidence
            )
        }

        if request.constraints.allowTeacherEvidence {
            if let teacherEvidence = advisory.teacherEvidence {
                guard let metadata = advisory.teacherEvidenceMetadata,
                      metadata.providerKind == .remoteTeacher,
                      metadata.inferenceTarget == .offloaded,
                      metadata.frameId == request.frameId,
                      metadata.mode == request.mode,
                      teacherEvidence.validate(expectedFrameId: request.frameId,
                                              semanticsReport: request.localBundle.semantics,
                                              runtimeMetadata: metadata).isEmpty else {
                    return DeepCriticValidationResult(sanitizedResponse: nil, failureReason: .validationFailed)
                }
            } else if advisory.teacherEvidenceMetadata != nil {
                return DeepCriticValidationResult(sanitizedResponse: nil, failureReason: .validationFailed)
            }
        } else {
            advisory = DeepCriticAdvisory(
                disposition: advisory.disposition,
                issueReviews: advisory.issueReviews,
                strengthReviews: advisory.strengthReviews,
                actionReviews: advisory.actionReviews,
                explanationPatch: advisory.explanationPatch,
                teacherEvidence: nil,
                teacherEvidenceMetadata: nil,
                hardCaseTags: advisory.hardCaseTags,
                confidence: advisory.confidence
            )
        }

        let explanationPatchResult: ExplanationPatchValidationResult
        if request.constraints.allowTextRefinement {
            explanationPatchResult = validateExplanationPatch(
                advisory.explanationPatch,
                request: request,
                allowedEvidenceRefs: allowedEvidenceRefs
            )
            if explanationPatchResult.fullReject {
                return DeepCriticValidationResult(sanitizedResponse: nil, failureReason: .validationFailed)
            }
        } else {
            explanationPatchResult = .dropped
        }

        let sanitizedPatch: DeepCriticExplanationPatch?
        switch explanationPatchResult {
        case let .kept(patch):
            sanitizedPatch = patch.isEmpty ? nil : patch
        case .dropped:
            sanitizedPatch = nil
        case .rejected:
            sanitizedPatch = nil
        }

        let sanitizedAdvisory = DeepCriticAdvisory(
            disposition: advisory.disposition,
            issueReviews: advisory.issueReviews,
            strengthReviews: advisory.strengthReviews,
            actionReviews: advisory.actionReviews,
            explanationPatch: sanitizedPatch,
            teacherEvidence: advisory.teacherEvidence,
            teacherEvidenceMetadata: advisory.teacherEvidenceMetadata,
            hardCaseTags: advisory.hardCaseTags,
            confidence: advisory.confidence
        )

        guard sanitizedAdvisory.hasUsableContent else {
            return DeepCriticValidationResult(sanitizedResponse: nil, failureReason: .validationFailed)
        }

        let sanitizedResponse = DeepCriticResponse(
            schemaVersion: response.schemaVersion,
            responseId: response.responseId,
            requestId: response.requestId,
            frameId: response.frameId,
            status: .completed,
            advisory: sanitizedAdvisory,
            failureReason: nil,
            producedAt: response.producedAt
        )

        return DeepCriticValidationResult(sanitizedResponse: sanitizedResponse, failureReason: nil)
    }

    private func makeAllowedEvidenceRefs(for request: DeepCriticOffloadRequest) -> Set<String> {
        var refs = Set<String>()
        if let trace = request.localBundle.traceExcerpt {
            refs.formUnion(trace.allFacts.map(\.refId))
        }
        refs.formUnion(request.localBundle.critique.issues.map(\.id))
        refs.formUnion(request.localBundle.critique.strengths.map(\.id))
        let actions = [request.localBundle.plan.primaryAction].compactMap { $0 }
            + request.localBundle.plan.secondaryActions
            + request.localBundle.plan.deferredActions
        refs.formUnion(actions.map(\.id))

        if let neuralEvidence = request.localBundle.fusedNeuralEvidence {
            for entry in neuralEvidence.headOutputs {
                if entry.payload.status == .available {
                    refs.insert("neural.\(entry.headId.rawValue)")
                }
            }
        }

        return refs
    }

    private func validateFindingReviews(_ reviews: [DeepCriticFindingReview],
                                        expectedKind: DeepCriticTargetKind,
                                        allowedIds: Set<String>,
                                        allowedEvidenceRefs: Set<String>) -> Bool {
        for review in reviews {
            guard review.targetKind == expectedKind,
                  allowedIds.contains(review.targetId),
                  review.suggestedDelta.map({ (-0.15...0.15).contains($0) }) ?? true,
                  evidenceRefsAreValid(review.evidenceRefs, allowedEvidenceRefs: allowedEvidenceRefs),
                  !review.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }
        return true
    }

    private func validateActionReviews(_ reviews: [DeepCriticActionReview],
                                       allowedIds: Set<String>,
                                       allowedEvidenceRefs: Set<String>) -> Bool {
        for review in reviews {
            guard allowedIds.contains(review.actionId),
                  evidenceRefsAreValid(review.evidenceRefs, allowedEvidenceRefs: allowedEvidenceRefs),
                  !review.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
        }
        return true
    }

    private func evidenceRefsAreValid(_ refs: [String], allowedEvidenceRefs: Set<String>) -> Bool {
        refs.allSatisfy { allowedEvidenceRefs.contains($0) }
    }

    private enum ExplanationPatchValidationResult {
        case kept(DeepCriticExplanationPatch)
        case dropped
        case rejected

        var fullReject: Bool {
            if case .rejected = self { return true }
            return false
        }
    }

    private func validateExplanationPatch(_ patch: DeepCriticExplanationPatch?,
                                          request: DeepCriticOffloadRequest,
                                          allowedEvidenceRefs: Set<String>) -> ExplanationPatchValidationResult {
        guard let patch, !patch.isEmpty else {
            return .dropped
        }

        if attemptToChangeVerdict(patch.shortVerdictOverride, verdict: request.localBundle.critique.verdict) {
            return .rejected
        }

        if let shortVerdictOverride = patch.shortVerdictOverride {
            let trimmed = shortVerdictOverride.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.count > 180 {
                return .dropped
            }
            guard evidenceRefsAreValid(patch.shortVerdictEvidenceRefs, allowedEvidenceRefs: allowedEvidenceRefs),
                  !patch.shortVerdictEvidenceRefs.isEmpty else {
                return .rejected
            }
        } else if !patch.shortVerdictEvidenceRefs.isEmpty {
            return .rejected
        }

        let knownStrengthIds = Set(request.localBundle.critique.strengths.map(\.id))
        let knownIssueIds = Set(request.localBundle.critique.issues.map(\.id))
        let actions = [request.localBundle.plan.primaryAction].compactMap { $0 }
            + request.localBundle.plan.secondaryActions
            + request.localBundle.plan.deferredActions
        let knownActionIds = Set(actions.map(\.id))

        if !patchEntriesAreValid(patch.whyGoodByStrengthId,
                                 allowedIds: knownStrengthIds,
                                 allowedEvidenceRefs: allowedEvidenceRefs)
            || !patchEntriesAreValid(patch.whyProblematicByIssueId,
                                     allowedIds: knownIssueIds,
                                     allowedEvidenceRefs: allowedEvidenceRefs)
            || !patchEntriesAreValid(patch.actionRationaleByActionId,
                                     allowedIds: knownActionIds,
                                     allowedEvidenceRefs: allowedEvidenceRefs) {
            return .rejected
        }

        let allTexts = [patch.shortVerdictOverride].compactMap { $0 }
            + patch.whyGoodByStrengthId.map(\.text)
            + patch.whyProblematicByIssueId.map(\.text)
            + patch.actionRationaleByActionId.map(\.text)

        let hasStructuralViolation = allTexts.contains(where: { text in
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty || trimmed.count > 180
        })

        if hasStructuralViolation {
            return .dropped
        }

        if detectLowFaithfulness(patch: patch, request: request) {
            return .rejected
        }

        return .kept(patch)
    }

    private func patchEntriesAreValid(_ entries: [DeepCriticExplanationPatchEntry],
                                      allowedIds: Set<String>,
                                      allowedEvidenceRefs: Set<String>) -> Bool {
        entries.allSatisfy { entry in
            allowedIds.contains(entry.targetId)
                && !entry.evidenceRefs.isEmpty
                && evidenceRefsAreValid(entry.evidenceRefs, allowedEvidenceRefs: allowedEvidenceRefs)
        }
    }

    private func detectLowFaithfulness(patch: DeepCriticExplanationPatch,
                                       request: DeepCriticOffloadRequest) -> Bool {
        let certaintySensitiveWords = ["точно", "однозначно", "гарантированно", "безошибочно", "идеально"]
        let strengthSources = Dictionary(uniqueKeysWithValues: request.localBundle.critique.strengths.map { ($0.id, $0.rationale) })
        let issueSources = Dictionary(uniqueKeysWithValues: request.localBundle.critique.issues.map { ($0.id, $0.rationale) })
        let actions = [request.localBundle.plan.primaryAction].compactMap { $0 }
            + request.localBundle.plan.secondaryActions
            + request.localBundle.plan.deferredActions
        let actionSources = Dictionary(uniqueKeysWithValues: actions.map { ($0.id, $0.expectedOutcome) })

        if let candidate = patch.shortVerdictOverride,
           hasLowOverlap(source: request.localBundle.critique.summary.shortVerdict, candidate: candidate) {
            return true
        }

        for entry in patch.whyGoodByStrengthId {
            guard let source = strengthSources[entry.targetId] else { continue }
            if hasLowOverlap(source: source, candidate: entry.text) {
                return true
            }
        }

        for entry in patch.whyProblematicByIssueId {
            guard let source = issueSources[entry.targetId] else { continue }
            if hasLowOverlap(source: source, candidate: entry.text) {
                return true
            }
        }

        for entry in patch.actionRationaleByActionId {
            guard let source = actionSources[entry.targetId] else { continue }
            if hasLowOverlap(source: source, candidate: entry.text) {
                return true
            }
        }

        if request.localBundle.critique.verdictConfidence < 0.55 {
            let normalized = ([patch.shortVerdictOverride].compactMap { $0 }
                + patch.whyGoodByStrengthId.map(\.text)
                + patch.whyProblematicByIssueId.map(\.text)
                + patch.actionRationaleByActionId.map(\.text))
                .joined(separator: " ")
                .lowercased()
            if certaintySensitiveWords.contains(where: { normalized.contains($0) }) {
                return true
            }
        }

        return false
    }

    private func hasLowOverlap(source: String, candidate: String) -> Bool {
        let sourceTokens = Set(tokenize(source))
        let candidateTokens = Set(tokenize(candidate))
        guard !sourceTokens.isEmpty, !candidateTokens.isEmpty else {
            return false
        }
        let overlap = Double(sourceTokens.intersection(candidateTokens).count) / Double(max(sourceTokens.count, 1))
        return overlap < 0.10 && candidateTokens.count >= 4
    }

    private func tokenize(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private func attemptToChangeVerdict(_ shortVerdictOverride: String?, verdict: FrameVerdict) -> Bool {
        guard let text = shortVerdictOverride?.lowercased() else {
            return false
        }

        let negativeMarkers = ["плох", "критич", "исправ", "неудач"]
        let positiveMarkers = ["хорош", "удач", "оставьте", "не менять"]

        switch verdict {
        case .good:
            return negativeMarkers.contains(where: { text.contains($0) })
        case .needsFix:
            return positiveMarkers.contains(where: { text.contains($0) })
        case .mixed:
            let hasNegative = negativeMarkers.contains(where: { text.contains($0) })
            let hasPositive = positiveMarkers.contains(where: { text.contains($0) })
            return hasNegative != hasPositive
        }
    }

    private func nonEmptyArray(from value: String?) -> [String] {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return []
        }
        return [value]
    }
}
