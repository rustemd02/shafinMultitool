import Foundation

protocol VisualSemanticEvidenceProvider: Sendable {
    var providerId: String { get }
    var capabilities: VisualSemanticEvidenceCapabilities { get }

    func fetchVisualEvidence(request: VLMVisualEvidenceRequest) async throws -> VLMVisualEvidenceResponse
}

struct VisualSemanticEvidenceCapabilities: Equatable, Sendable {
    let supportsOffline: Bool
    let supportsRemote: Bool
    let supportsPrivacyTiers: Set<VLMPrivacyTier>
}

enum VisualSemanticEvidenceProviderFactory {
    static func makeDefaultProvider() -> VisualSemanticEvidenceProvider? {
        let configured = ProcessInfo.processInfo.environment["CAMERA_VLM_VISUAL_EVIDENCE_PROVIDER"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch configured {
        case "mock":
            return MockVLMVisualEvidenceProvider()
        case "remote":
            return RemoteVLMVisualEvidenceProvider()
        default:
            return nil
        }
    }
}

enum VisualEvidenceCoordinatorResult: Sendable {
    case skipped(reason: String, diagnostics: VLMEvidenceDiagnostics)
    case accepted(validation: VLMEvidenceValidationResult, diagnostics: VLMEvidenceDiagnostics)
    case rejected(violations: [VLMEvidenceViolation], diagnostics: VLMEvidenceDiagnostics)
    case failed(reason: String, diagnostics: VLMEvidenceDiagnostics)
}

actor VisualSemanticEvidenceCoordinator {
    private let provider: VisualSemanticEvidenceProvider?
    private let timeoutMs: Int

    init(provider: VisualSemanticEvidenceProvider?, timeoutMs: Int = 900) {
        self.provider = provider
        self.timeoutMs = min(1_500, max(100, timeoutMs))
    }

    func fetchEvidence(request: VLMVisualEvidenceRequest) async -> VisualEvidenceCoordinatorResult {
        guard request.mode == .pause else {
            return .rejected(
                violations: [.modeNotPause],
                diagnostics: makeDiagnostics(
                    privacyTier: request.privacyTier,
                    fallbackReason: "mode_not_pause"
                )
            )
        }

        let requestViolations = request.validate()
        if !requestViolations.isEmpty {
            return .rejected(
                violations: requestViolations,
                diagnostics: makeDiagnostics(
                    privacyTier: request.privacyTier,
                    fallbackReason: "request_validation_failed"
                )
            )
        }

        guard let provider else {
            return .skipped(
                reason: "provider_unavailable",
                diagnostics: makeDiagnostics(
                    privacyTier: request.privacyTier,
                    fallbackReason: "provider_unavailable"
                )
            )
        }

        if !provider.capabilities.supportsPrivacyTiers.contains(request.privacyTier) {
            return .skipped(
                reason: "policy_blocked",
                diagnostics: makeDiagnostics(
                    privacyTier: request.privacyTier,
                    fallbackReason: "policy_blocked"
                )
            )
        }

        let startedAt = Date()
        let callResult = await callProviderWithTimeout(provider: provider, request: request)
        let latencyMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000.0))

        switch callResult {
        case .cancelled:
            return .failed(
                reason: "canceled_due_to_state_change",
                diagnostics: makeDiagnostics(
                    privacyTier: request.privacyTier,
                    latencyMs: latencyMs,
                    fallbackReason: "canceled_due_to_state_change"
                )
            )
        case .timedOut:
            return .failed(
                reason: "timeout",
                diagnostics: makeDiagnostics(
                    privacyTier: request.privacyTier,
                    latencyMs: latencyMs,
                    fallbackReason: "timeout"
                )
            )
        case .failed:
            return .failed(
                reason: "runtime_error",
                diagnostics: makeDiagnostics(
                    privacyTier: request.privacyTier,
                    latencyMs: latencyMs,
                    fallbackReason: "runtime_error"
                )
            )
        case .success(let response):
            let validation = response.validate(against: request)
            let diagnostics = mergedDiagnostics(
                base: response.diagnostics,
                latencyMs: latencyMs,
                fallbackReason: validation.accepted ? nil : "validation_failed"
            )

            if validation.accepted {
                return .accepted(validation: validation, diagnostics: diagnostics)
            }
            return .rejected(violations: validation.violations, diagnostics: diagnostics)
        }
    }

    private enum ProviderCallResult {
        case success(VLMVisualEvidenceResponse)
        case failed
        case cancelled
        case timedOut
    }

    private func callProviderWithTimeout(provider: VisualSemanticEvidenceProvider,
                                         request: VLMVisualEvidenceRequest) async -> ProviderCallResult {
        if Task.isCancelled {
            return .cancelled
        }

        let timeoutNs = UInt64(timeoutMs) * 1_000_000
        return await withTaskGroup(of: ProviderCallResult.self) { group in
            group.addTask {
                if Task.isCancelled { return .cancelled }
                do {
                    let response = try await provider.fetchVisualEvidence(request: request)
                    return .success(response)
                } catch {
                    return .failed
                }
            }

            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNs)
                } catch {
                    if Task.isCancelled { return .cancelled }
                }
                if Task.isCancelled { return .cancelled }
                return .timedOut
            }

            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    private func mergedDiagnostics(base: VLMEvidenceDiagnostics,
                                   latencyMs: Int,
                                   fallbackReason: String?) -> VLMEvidenceDiagnostics {
        VLMEvidenceDiagnostics(
            latencyMs: base.latencyMs ?? latencyMs,
            providerModelFamily: base.providerModelFamily,
            providerModelVersion: base.providerModelVersion,
            promptVersion: base.promptVersion,
            privacyTier: base.privacyTier,
            fallbackReason: fallbackReason ?? base.fallbackReason
        )
    }

    private func makeDiagnostics(privacyTier: VLMPrivacyTier,
                                 latencyMs: Int = 0,
                                 fallbackReason: String?) -> VLMEvidenceDiagnostics {
        VLMEvidenceDiagnostics(
            latencyMs: latencyMs,
            providerModelFamily: nil,
            providerModelVersion: nil,
            promptVersion: "vlm-evidence-coordinator-v1",
            privacyTier: privacyTier,
            fallbackReason: fallbackReason
        )
    }
}

private enum RemoteVLMVisualEvidenceProviderError: Error {
    case notImplemented
}

actor RemoteVLMVisualEvidenceProvider: VisualSemanticEvidenceProvider {
    let providerId = "remote_vlm_visual_evidence_v1"
    let capabilities = VisualSemanticEvidenceCapabilities(
        supportsOffline: false,
        supportsRemote: true,
        supportsPrivacyTiers: [.structuredOnly, .redactedVisual]
    )

    func fetchVisualEvidence(request: VLMVisualEvidenceRequest) async throws -> VLMVisualEvidenceResponse {
        throw RemoteVLMVisualEvidenceProviderError.notImplemented
    }
}

actor MockVLMVisualEvidenceProvider: VisualSemanticEvidenceProvider {
    let providerId = "mock_vlm_visual_evidence_v1"
    let capabilities = VisualSemanticEvidenceCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsPrivacyTiers: [.structuredOnly, .redactedVisual]
    )

    private let fixedResponse: VLMVisualEvidenceResponse?
    private let sleepMs: Int

    init(fixedResponse: VLMVisualEvidenceResponse? = nil, sleepMs: Int = 0) {
        self.fixedResponse = fixedResponse
        self.sleepMs = max(0, sleepMs)
    }

    func fetchVisualEvidence(request: VLMVisualEvidenceRequest) async throws -> VLMVisualEvidenceResponse {
        if sleepMs > 0 {
            try await Task.sleep(nanoseconds: UInt64(sleepMs) * 1_000_000)
        }

        if let fixedResponse {
            return fixedResponse
        }

        let primaryEntity = request.localContext.groundedEntities.first {
            $0.role == .primarySubject
        } ?? request.localContext.groundedEntities.first

        let secondaryEntity = request.localContext.groundedEntities.first {
            $0.role == .distractingObject || $0.role == .faceContourOccluder || $0.role == .foregroundObject
        }

        let suggestedActions = suggestedActionIds(request: request)
        let issue = request.localContext.critique.issues.first
        let strength = request.localContext.critique.strengths.first
        let confidence = min(0.95, max(0.45, issue?.confidence ?? strength?.confidence ?? 0.72))

        let observation = makeObservation(
            request: request,
            issue: issue,
            strength: strength,
            primaryEntityRef: primaryEntity?.entityRef,
            secondaryEntityRef: secondaryEntity?.entityRef,
            suggestedActions: suggestedActions,
            confidence: confidence
        )

        let relation: [VLMEntityRelation]
        if let primaryEntityRef = primaryEntity?.entityRef,
           let secondaryEntityRef = secondaryEntity?.entityRef,
           issue != nil {
            relation = [
                VLMEntityRelation(
                    relationId: "rel_\(request.frameId)_1",
                    sourceEntityRef: secondaryEntityRef,
                    targetEntityRef: primaryEntityRef,
                    relationType: .blocks,
                    dimension: observation.dimension,
                    score: observation.score,
                    confidence: confidence,
                    uncertaintyReasons: [],
                    supportedObservationIds: [observation.observationId]
                )
            ]
        } else {
            relation = []
        }

        return VLMVisualEvidenceResponse(
            schemaVersion: request.schemaVersion,
            requestId: request.requestId,
            frameId: request.frameId,
            mode: .pause,
            providerId: providerId,
            status: .completed,
            primaryEntityRef: primaryEntity?.entityRef,
            primaryEntityKind: primaryEntity?.kind ?? .person,
            primaryEntityDisplayLabelCandidate: primaryEntity?.displayLabelCandidate ?? "герой",
            primaryEntityLabelConfidence: primaryEntity?.displayLabelConfidence ?? 0.8,
            secondaryEntityRef: secondaryEntity?.entityRef,
            secondaryEntityKind: secondaryEntity?.kind,
            secondaryEntityDisplayLabelCandidate: secondaryEntity?.displayLabelCandidate,
            secondaryEntityLabelConfidence: secondaryEntity?.displayLabelConfidence,
            observations: [observation],
            relations: relation,
            suggestedActionIds: suggestedActions,
            explanation: VLMSecondaryExplanation(
                language: request.locale,
                summary: issue?.rationale ?? strength?.rationale ?? request.localContext.critique.summary.shortVerdict,
                caveats: []
            ),
            safety: VLMEvidenceSafetyReport(passed: true, violations: []),
            diagnostics: VLMEvidenceDiagnostics(
                latencyMs: sleepMs,
                providerModelFamily: "mock-vlm",
                providerModelVersion: "s1",
                promptVersion: "mock-vlm-evidence-v1",
                privacyTier: request.privacyTier,
                fallbackReason: nil
            )
        )
    }

    private func suggestedActionIds(request: VLMVisualEvidenceRequest) -> [SemanticActionType] {
        let fromDrafts = request.localContext.semanticTipDrafts.map(\.actionType)
        var seen: Set<SemanticActionType> = []
        let dedupedDrafts = fromDrafts.filter {
            if seen.contains($0) {
                return false
            }
            seen.insert($0)
            return true
        }
        if !dedupedDrafts.isEmpty {
            return Array(dedupedDrafts.prefix(request.constraints.maxSuggestedActionIds))
        }
        return [.changeCameraAngle]
    }

    private func makeObservation(request: VLMVisualEvidenceRequest,
                                 issue: FrameIssue?,
                                 strength: FrameStrength?,
                                 primaryEntityRef: String?,
                                 secondaryEntityRef: String?,
                                 suggestedActions: [SemanticActionType],
                                 confidence: Double) -> VLMVisualEvidenceObservation {
        let observationId = "obs_\(request.frameId)_1"

        if let issue {
            return VLMVisualEvidenceObservation(
                observationId: observationId,
                dimension: dimension(for: issue.type),
                polarity: .supportsProblem,
                score: min(1.0, max(0.0, issue.severity)),
                confidence: confidence,
                uncertaintyReasons: [],
                primaryEntityRef: primaryEntityRef,
                secondaryEntityRef: secondaryEntityRef,
                visualProblemType: visualProblemType(for: issue.type),
                visualStrengthType: nil,
                supportedIssueIds: [issue.id],
                supportedStrengthIds: [],
                suggestedActionIds: suggestedActions,
                evidenceNote: issue.rationale
            )
        }

        if let strength {
            return VLMVisualEvidenceObservation(
                observationId: observationId,
                dimension: .subjectReadability,
                polarity: .supportsStrength,
                score: strength.confidence,
                confidence: confidence,
                uncertaintyReasons: [],
                primaryEntityRef: primaryEntityRef,
                secondaryEntityRef: secondaryEntityRef,
                visualProblemType: nil,
                visualStrengthType: visualStrengthType(for: strength.type),
                supportedIssueIds: [],
                supportedStrengthIds: [strength.id],
                suggestedActionIds: suggestedActions,
                evidenceNote: strength.rationale
            )
        }

        return VLMVisualEvidenceObservation(
            observationId: observationId,
            dimension: .frameIntent,
            polarity: .neutralContext,
            score: 0.55,
            confidence: confidence,
            uncertaintyReasons: [],
            primaryEntityRef: primaryEntityRef,
            secondaryEntityRef: secondaryEntityRef,
            visualProblemType: nil,
            visualStrengthType: nil,
            supportedIssueIds: [],
            supportedStrengthIds: [],
            suggestedActionIds: suggestedActions,
            evidenceNote: request.localContext.critique.summary.shortVerdict
        )
    }

    private func dimension(for issueType: IssueTypeV1) -> VLMVisualEvidenceDimension {
        switch issueType {
        case .backlightHidesSubject:
            return .lightingRelation
        case .horizonDistracts:
            return .frameIntent
        case .backgroundCompetesWithSubject, .frameVisuallyOverloaded, .sceneHasNoClearFocus:
            return .clutter
        case .insufficientLookSpace, .subjectTooCloseToEdge:
            return .frameIntent
        case .subjectNotProminentEnough:
            return .subjectReadability
        }
    }

    private func visualProblemType(for issueType: IssueTypeV1) -> VisualProblemType {
        switch issueType {
        case .subjectTooCloseToEdge:
            return .subjectEdgePressure
        case .subjectNotProminentEnough:
            return .weakSubjectProminence
        case .backgroundCompetesWithSubject:
            return .backgroundCompetition
        case .insufficientLookSpace:
            return .insufficientLookSpace
        case .backlightHidesSubject:
            return .subjectBlendsIntoDarkBackground
        case .sceneHasNoClearFocus:
            return .unclearFocusHierarchy
        case .frameVisuallyOverloaded:
            return .backgroundClutter
        case .horizonDistracts:
            return .tiltedHorizon
        }
    }

    private func visualStrengthType(for strengthType: StrengthTypeV1) -> VisualStrengthType {
        switch strengthType {
        case .goodSubjectIsolation:
            return .cleanSubjectSeparation
        case .goodLightEmphasis:
            return .flatteringLightDirection
        case .clearFocusHierarchy:
            return .clearFocusHierarchy
        case .stableHorizonSupportsScene:
            return .stableHorizon
        case .balancedCompositionForScene:
            return .balancedSceneComposition
        }
    }
}
