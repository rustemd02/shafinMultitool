import XCTest
@testable import shafinMultitool

private actor PauseStateProbe {
    private var frameId: String?

    init(frameId: String?) {
        self.frameId = frameId
    }

    func currentPauseFrameId() -> String? {
        frameId
    }

    func setCurrentPauseFrameId(_ frameId: String?) {
        self.frameId = frameId
    }
}

final class DeepCriticOffloadingCoordinatorTests: XCTestCase {
    func testReturnsDisabledWhenFeatureIsDisabled() async {
        let provider = MockDeepCriticProvider { _ in
            XCTFail("Provider should not be called")
            return self.makeCompletedResponse()
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)

        let outcome = await coordinator.offload(
            request: makeRequest(),
            context: DeepCriticPolicyContext(
                featureEnabled: false,
                networkAvailable: true,
                backgroundRemoteWorkAllowed: true,
                visualConsentGranted: false,
                positiveTriggerSatisfied: true,
                currentPauseFrameId: "frame-1",
                reasoningProviderActive: false
            )
        )

        XCTAssertEqual(outcome.kind, .disabled)
    }

    func testReturnsNotTriggeredOutsidePause() async {
        let provider = MockDeepCriticProvider { _ in
            XCTFail("Provider should not be called")
            return self.makeCompletedResponse()
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(mode: .live)

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        XCTAssertEqual(outcome.kind, .notTriggered)
    }

    func testReturnsBlockedWhenNetworkUnavailable() async {
        let provider = MockDeepCriticProvider { _ in
            XCTFail("Provider should not be called")
            return self.makeCompletedResponse()
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest()

        let outcome = await coordinator.offload(
            request: request,
            context: DeepCriticPolicyContext(
                featureEnabled: true,
                networkAvailable: false,
                backgroundRemoteWorkAllowed: true,
                visualConsentGranted: false,
                positiveTriggerSatisfied: true,
                currentPauseFrameId: request.frameId,
                reasoningProviderActive: false
            )
        )

        XCTAssertEqual(outcome.kind, .blocked)
    }

    func testDropsForbiddenTeacherEvidenceButKeepsUsableAdvisory() async {
        let provider = MockDeepCriticProvider { _ in
            self.makeCompletedResponse(
                advisory: DeepCriticAdvisory(
                    disposition: .hardCaseFlag,
                    issueReviews: [],
                    strengthReviews: [],
                    actionReviews: [],
                    explanationPatch: nil,
                    teacherEvidence: self.makeTeacherEvidenceSnapshot(),
                    teacherEvidenceMetadata: self.makeTeacherEvidenceMetadata(frameId: "frame-1"),
                    hardCaseTags: ["hard_case"],
                    confidence: 0.61
                )
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        var request = makeRequest()
        request = makeRequest(constraints: DeepCriticConstraints(
            maxLatencyMs: 2_500,
            allowTextRefinement: false,
            allowTeacherEvidence: false,
            allowActionReorderingAdvice: false
        ))

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .completed(response) = outcome else {
            return XCTFail("Expected completed response")
        }

        XCTAssertNil(response.advisory?.teacherEvidence)
        XCTAssertNil(response.advisory?.teacherEvidenceMetadata)
        XCTAssertEqual(response.advisory?.hardCaseTags, ["hard_case"])
    }

    func testDropsForbiddenActionReviewsButKeepsUsableAdvisory() async {
        let provider = MockDeepCriticProvider { _ in
            self.makeCompletedResponse(
                advisory: DeepCriticAdvisory(
                    disposition: .hardCaseFlag,
                    issueReviews: [],
                    strengthReviews: [],
                    actionReviews: [
                        DeepCriticActionReview(
                            actionId: "action-1",
                            verdict: .deprioritize,
                            rationale: "Рекомендацию стоит понизить в приоритете.",
                            evidenceRefs: ["trace.act.1"]
                        )
                    ],
                    explanationPatch: nil,
                    teacherEvidence: nil,
                    teacherEvidenceMetadata: nil,
                    hardCaseTags: ["review_kept"],
                    confidence: 0.59
                )
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(constraints: DeepCriticConstraints(
            maxLatencyMs: 2_500,
            allowTextRefinement: false,
            allowTeacherEvidence: false,
            allowActionReorderingAdvice: false
        ))

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .completed(response) = outcome else {
            return XCTFail("Expected completed response")
        }

        XCTAssertEqual(response.advisory?.actionReviews, [])
        XCTAssertEqual(response.advisory?.hardCaseTags, ["review_kept"])
    }

    func testFailsValidationWhenForbiddenTextRefinementIsOnlyAdvisoryContent() async {
        let provider = MockDeepCriticProvider { _ in
            self.makeCompletedResponse(
                advisory: DeepCriticAdvisory(
                    disposition: .advisoryRefinement,
                    issueReviews: [],
                    strengthReviews: [],
                    actionReviews: [],
                    explanationPatch: DeepCriticExplanationPatch(
                        shortVerdictOverride: "Кадр стоит немного уточнить.",
                        shortVerdictEvidenceRefs: ["trace.issue.1"],
                        whyGoodByStrengthId: [],
                        whyProblematicByIssueId: [],
                        actionRationaleByActionId: []
                    ),
                    teacherEvidence: nil,
                    teacherEvidenceMetadata: nil,
                    hardCaseTags: [],
                    confidence: 0.55
                )
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(constraints: DeepCriticConstraints(
            maxLatencyMs: 2_500,
            allowTextRefinement: false,
            allowTeacherEvidence: false,
            allowActionReorderingAdvice: false
        ))

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .failed(failure) = outcome else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertEqual(failure.reason, .validationFailed)
    }

    func testDropsWholeExplanationPatchForStructuralViolations() async {
        let provider = MockDeepCriticProvider { _ in
            self.makeCompletedResponse(
                advisory: DeepCriticAdvisory(
                    disposition: .hardCaseFlag,
                    issueReviews: [
                        DeepCriticFindingReview(
                            targetId: "issue-1",
                            targetKind: .issue,
                            verdict: .reinforce,
                            suggestedDelta: 0.05,
                            rationale: "Проблема подтверждается.",
                            evidenceRefs: ["trace.issue.1"]
                        )
                    ],
                    strengthReviews: [],
                    actionReviews: [],
                    explanationPatch: DeepCriticExplanationPatch(
                        shortVerdictOverride: String(repeating: "д", count: 190),
                        shortVerdictEvidenceRefs: ["trace.issue.1"],
                        whyGoodByStrengthId: [],
                        whyProblematicByIssueId: [],
                        actionRationaleByActionId: []
                    ),
                    teacherEvidence: nil,
                    teacherEvidenceMetadata: nil,
                    hardCaseTags: [],
                    confidence: 0.74
                )
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(constraints: DeepCriticConstraints(
            maxLatencyMs: 2_500,
            allowTextRefinement: true,
            allowTeacherEvidence: false,
            allowActionReorderingAdvice: false
        ))

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .completed(response) = outcome else {
            return XCTFail("Expected completed response")
        }

        XCTAssertNil(response.advisory?.explanationPatch)
        XCTAssertEqual(response.advisory?.issueReviews.count, 1)
    }

    func testForcesAllowTextRefinementOffWhenReasoningProviderIsActive() async {
        let provider = MockDeepCriticProvider { request in
            XCTAssertFalse(request.constraints.allowTextRefinement)
            return self.makeCompletedResponse(
                advisory: DeepCriticAdvisory(
                    disposition: .hardCaseFlag,
                    issueReviews: [],
                    strengthReviews: [],
                    actionReviews: [],
                    explanationPatch: DeepCriticExplanationPatch(
                        shortVerdictOverride: "Это не должно примениться.",
                        shortVerdictEvidenceRefs: ["trace.obs.1"],
                        whyGoodByStrengthId: [],
                        whyProblematicByIssueId: [],
                        actionRationaleByActionId: []
                    ),
                    teacherEvidence: nil,
                    teacherEvidenceMetadata: nil,
                    hardCaseTags: ["debug_only"],
                    confidence: 0.66
                )
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(constraints: DeepCriticConstraints(
            maxLatencyMs: 2_500,
            allowTextRefinement: true,
            allowTeacherEvidence: false,
            allowActionReorderingAdvice: false
        ))

        let outcome = await coordinator.offload(
            request: request,
            context: DeepCriticPolicyContext(
                featureEnabled: true,
                networkAvailable: true,
                backgroundRemoteWorkAllowed: true,
                visualConsentGranted: false,
                positiveTriggerSatisfied: true,
                currentPauseFrameId: request.frameId,
                reasoningProviderActive: true
            )
        )

        guard case let .completed(response) = outcome else {
            return XCTFail("Expected completed response")
        }

        XCTAssertNil(response.advisory?.explanationPatch)
        XCTAssertEqual(response.advisory?.hardCaseTags, ["debug_only"])
    }

    func testRejectsLowFaithfulnessExplanationPatch() async {
        let provider = MockDeepCriticProvider { _ in
            self.makeCompletedResponse(
                advisory: DeepCriticAdvisory(
                    disposition: .advisoryRefinement,
                    issueReviews: [],
                    strengthReviews: [],
                    actionReviews: [],
                    explanationPatch: DeepCriticExplanationPatch(
                        shortVerdictOverride: "Это идеальный и безошибочный кадр для немедленного релиза.",
                        shortVerdictEvidenceRefs: ["trace.issue.1"],
                        whyGoodByStrengthId: [],
                        whyProblematicByIssueId: [],
                        actionRationaleByActionId: []
                    ),
                    teacherEvidence: nil,
                    teacherEvidenceMetadata: nil,
                    hardCaseTags: [],
                    confidence: 0.9
                )
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(constraints: DeepCriticConstraints(
            maxLatencyMs: 2_500,
            allowTextRefinement: true,
            allowTeacherEvidence: false,
            allowActionReorderingAdvice: false
        ))

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .failed(failure) = outcome else {
            return XCTFail("Expected failed validation")
        }
        XCTAssertEqual(failure.reason, .validationFailed)
    }

    func testRejectsExplanationPatchWithUnsupportedEvidenceRefs() async {
        let provider = MockDeepCriticProvider { _ in
            self.makeCompletedResponse(
                advisory: DeepCriticAdvisory(
                    disposition: .advisoryRefinement,
                    issueReviews: [],
                    strengthReviews: [],
                    actionReviews: [],
                    explanationPatch: DeepCriticExplanationPatch(
                        shortVerdictOverride: "Кадр почти готов, но стоит мягко усилить фокус.",
                        shortVerdictEvidenceRefs: ["synthetic.ref"],
                        whyGoodByStrengthId: [],
                        whyProblematicByIssueId: [],
                        actionRationaleByActionId: []
                    ),
                    teacherEvidence: nil,
                    teacherEvidenceMetadata: nil,
                    hardCaseTags: [],
                    confidence: 0.63
                )
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(constraints: DeepCriticConstraints(
            maxLatencyMs: 2_500,
            allowTextRefinement: true,
            allowTeacherEvidence: false,
            allowActionReorderingAdvice: false
        ))

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .failed(failure) = outcome else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertEqual(failure.reason, .validationFailed)
    }

    func testRejectsExplanationPatchWithOrphanedShortVerdictEvidenceRefs() async {
        let provider = MockDeepCriticProvider { _ in
            self.makeCompletedResponse(
                advisory: DeepCriticAdvisory(
                    disposition: .hardCaseFlag,
                    issueReviews: [],
                    strengthReviews: [],
                    actionReviews: [],
                    explanationPatch: DeepCriticExplanationPatch(
                        shortVerdictOverride: nil,
                        shortVerdictEvidenceRefs: ["trace.issue.1"],
                        whyGoodByStrengthId: [],
                        whyProblematicByIssueId: [],
                        actionRationaleByActionId: []
                    ),
                    teacherEvidence: nil,
                    teacherEvidenceMetadata: nil,
                    hardCaseTags: ["kept"],
                    confidence: 0.58
                )
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)

        let outcome = await coordinator.offload(
            request: makeRequest(constraints: DeepCriticConstraints(
                maxLatencyMs: 2_500,
                allowTextRefinement: true,
                allowTeacherEvidence: false,
                allowActionReorderingAdvice: false
            )),
            context: makeContext(currentPauseFrameId: "frame-1")
        )

        guard case let .failed(failure) = outcome else {
            return XCTFail("Expected validation failure")
        }
        XCTAssertEqual(failure.reason, .validationFailed)
    }

    func testRejectsMalformedRefusedResponseEnvelope() async {
        let provider = MockDeepCriticProvider { _ in
            self.makeResponse(
                requestId: "wrong-request",
                frameId: "frame-1",
                status: .refused,
                advisory: DeepCriticAdvisory(
                    disposition: .hardCaseFlag,
                    issueReviews: [],
                    strengthReviews: [],
                    actionReviews: [],
                    explanationPatch: nil,
                    teacherEvidence: nil,
                    teacherEvidenceMetadata: nil,
                    hardCaseTags: ["should_not_exist"],
                    confidence: 0.22
                ),
                failureReason: .policyRefused
            )
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest()

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .failed(failure) = outcome else {
            return XCTFail("Expected malformed-envelope validation failure")
        }
        XCTAssertEqual(failure.reason, .validationFailed)
    }

    func testRejectsResponseWhenPauseStateChangesBeforeCompletion() async {
        let pauseState = PauseStateProbe(frameId: "frame-1")
        let provider = MockDeepCriticProvider { _ in
            await pauseState.setCurrentPauseFrameId("frame-2")
            return self.makeCompletedResponse()
        }
        let coordinator = DeepCriticOffloadingCoordinator(
            provider: provider,
            currentPauseFrameProvider: {
                await pauseState.currentPauseFrameId()
            }
        )
        let request = makeRequest()

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .failed(failure) = outcome else {
            return XCTFail("Expected stale-state validation failure")
        }
        XCTAssertEqual(failure.reason, .validationFailed)
    }

    func testReturnsNotTriggeredWhenSceneSemanticsAreInvalid() async {
        let provider = MockDeepCriticProvider { _ in
            XCTFail("Provider should not be called")
            return self.makeCompletedResponse()
        }
        let invalidSemantics = SceneSemanticsReport(
            frameId: "frame-1",
            mode: .pause,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.72,
            primarySubject: SceneSemanticsReport.PrimarySubject(
                kind: .person,
                label: "subject",
                region: NormalizedRect(x: 0.20, y: 0.15, width: 0.30, height: 0.45),
                confidence: 0.10
            ),
            dominance: SceneSemanticsReport.VisualDominanceState(
                hasClearFocus: true,
                focusCompetitionScore: 0.92,
                backgroundClutterScore: 0.31
            ),
            readability: SceneSemanticsReport.SemanticReadabilityState(
                subjectReadable: true,
                lookSpaceAdequate: true,
                edgePressureScore: 0.18,
                separationScore: 0.66
            ),
            ambiguities: [],
            assumptions: []
        )
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(semanticsOverride: invalidSemantics)

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        XCTAssertEqual(outcome.kind, .notTriggered)
    }

    func testFailsValidationWhenResponseExceedsProviderByteLimit() async {
        let provider = MockDeepCriticProvider(
            capabilities: DeepCriticCapabilities(
                supportsStructuredOnly: true,
                supportsRedactedVisual: true,
                supportsRussian: true,
                maxRequestBytes: 2_000_000,
                maxResponseBytes: 1,
                allowsTeacherEvidence: true
            )
        ) { _ in
            self.makeCompletedResponse()
        }
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest()

        let outcome = await coordinator.offload(
            request: request,
            context: makeContext(currentPauseFrameId: request.frameId)
        )

        guard case let .failed(failure) = outcome else {
            return XCTFail("Expected oversized response failure")
        }
        XCTAssertEqual(failure.reason, .validationFailed)
    }

    func testBlocksRedactedVisualWhenAttachmentSizeIsDegenerate() async {
        let provider = MockDeepCriticProvider { _ in
            XCTFail("Provider should not be called")
            return self.makeCompletedResponse()
        }
        let candidate = DeepCriticVisualAttachmentCandidate(
            kind: .subjectCrop,
            pixelWidth: 0,
            pixelHeight: 120,
            hasExif: false,
            bytes: Data([0x01, 0x02, 0x03])
        )
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(
            trigger: .explicitUserRequest,
            preferredPrivacyTier: .redactedVisual,
            visualAttachmentCandidate: candidate
        )

        let outcome = await coordinator.offload(
            request: request,
            context: DeepCriticPolicyContext(
                featureEnabled: true,
                networkAvailable: true,
                backgroundRemoteWorkAllowed: true,
                visualConsentGranted: true,
                positiveTriggerSatisfied: true,
                currentPauseFrameId: request.frameId,
                reasoningProviderActive: false
            )
        )

        XCTAssertEqual(outcome.kind, .blocked)
    }

    func testBlocksRedactedVisualWhenLongEdgeExceedsCap() async {
        let provider = MockDeepCriticProvider { _ in
            XCTFail("Provider should not be called")
            return self.makeCompletedResponse()
        }
        let candidate = DeepCriticVisualAttachmentCandidate(
            kind: .frame,
            pixelWidth: 1_600,
            pixelHeight: 900,
            hasExif: false,
            bytes: Data([0x01, 0x02, 0x03])
        )
        let coordinator = DeepCriticOffloadingCoordinator(provider: provider)
        let request = makeRequest(
            trigger: .explicitUserRequest,
            preferredPrivacyTier: .redactedVisual,
            visualAttachmentCandidate: candidate
        )

        let outcome = await coordinator.offload(
            request: request,
            context: DeepCriticPolicyContext(
                featureEnabled: true,
                networkAvailable: true,
                backgroundRemoteWorkAllowed: true,
                visualConsentGranted: true,
                positiveTriggerSatisfied: true,
                currentPauseFrameId: request.frameId,
                reasoningProviderActive: false
            )
        )

        XCTAssertEqual(outcome.kind, .blocked)
    }
}

private extension DeepCriticOffloadingCoordinatorTests {
    func makeContext(currentPauseFrameId: String) -> DeepCriticPolicyContext {
        DeepCriticPolicyContext(
            featureEnabled: true,
            networkAvailable: true,
            backgroundRemoteWorkAllowed: true,
            visualConsentGranted: false,
            positiveTriggerSatisfied: true,
            currentPauseFrameId: currentPauseFrameId,
            reasoningProviderActive: false
        )
    }

    func makeRequest(mode: AnalysisMode = .pause,
                     frameId: String = "frame-1",
                     trigger: DeepCriticTrigger = .ambiguousLocalCase,
                     preferredPrivacyTier: DeepCriticPrivacyTier = .structuredOnly,
                     semanticsOverride: SceneSemanticsReport? = nil,
                     visualAttachmentCandidate: DeepCriticVisualAttachmentCandidate? = nil,
                     constraints: DeepCriticConstraints = .automaticDefault) -> DeepCriticOffloadRequest {
        let semantics = semanticsOverride ?? SceneSemanticsReport(
            frameId: frameId,
            mode: mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.72,
            primarySubject: SceneSemanticsReport.PrimarySubject(
                kind: .person,
                label: "subject",
                region: NormalizedRect(x: 0.20, y: 0.15, width: 0.30, height: 0.45),
                confidence: 0.81
            ),
            dominance: SceneSemanticsReport.VisualDominanceState(
                hasClearFocus: true,
                focusCompetitionScore: 0.24,
                backgroundClutterScore: 0.31
            ),
            readability: SceneSemanticsReport.SemanticReadabilityState(
                subjectReadable: true,
                lookSpaceAdequate: true,
                edgePressureScore: 0.18,
                separationScore: 0.66
            ),
            ambiguities: [],
            assumptions: []
        )

        let issue = FrameIssue(
            id: "issue-1",
            type: .subjectNotProminentEnough,
            severity: 0.52,
            confidence: 0.48,
            rationale: "Главный объект читается слабее, чем должен.",
            evidence: [EvidenceRef(source: .snapshot, key: "composition.subject_area_ratio", value: "0.11", confidence: 0.48)],
            affectedRegion: NormalizedRect(x: 0.20, y: 0.15, width: 0.30, height: 0.45),
            suggestedFixTypes: [.reframing]
        )

        let strength = FrameStrength(
            id: "strength-1",
            type: .goodLightEmphasis,
            confidence: 0.67,
            rationale: "Свет помогает отделить объект от фона.",
            evidence: [EvidenceRef(source: .snapshot, key: "lighting.exposure", value: "0.62", confidence: 0.67)],
            supportingRegion: NormalizedRect(x: 0.18, y: 0.12, width: 0.34, height: 0.48)
        )

        let critique = CritiqueReport(
            frameId: frameId,
            mode: mode,
            verdict: .mixed,
            verdictConfidence: 0.46,
            strengths: [strength],
            issues: [issue],
            summary: CritiqueSummary(
                id: "summary-1",
                shortVerdict: "Кадр близок к рабочему, но фокус на объекте пока слабый.",
                whyGood: "Свет уже помогает держать внимание на объекте.",
                whyProblematic: "Главный объект пока недостаточно доминирует."
            ),
            traceRefs: ["trace.issue.1", "trace.strength.1"],
            fallbackUsed: false
        )

        let action = RecommendationAction(
            id: "action-1",
            actionType: .increaseSubjectSize,
            priority: 0,
            targetRegion: NormalizedRect(x: 0.20, y: 0.15, width: 0.30, height: 0.45),
            linkedIssueIds: [issue.id],
            expectedOutcome: "Сделайте главный объект крупнее, чтобы усилить фокус.",
            guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.40, suppressWhenMoving: false),
            overlayHint: nil
        )

        let plan = RecommendationPlan(
            frameId: frameId,
            mode: mode,
            inputVerdict: .mixed,
            primaryAction: action,
            secondaryActions: [],
            deferredActions: [],
            noChangeRationale: nil,
            planConfidence: 0.51
        )

        let traceExcerpt = DeepCriticTraceExcerpt(
            observations: [DeepCriticTraceFact(refId: "trace.obs.1", kind: "observation", message: "subject area ratio low")],
            interpretations: [DeepCriticTraceFact(refId: "trace.issue.1", kind: "issue", message: issue.rationale)],
            recommendations: [DeepCriticTraceFact(refId: "trace.act.1", kind: "action", message: action.expectedOutcome)]
        )

        return DeepCriticOffloadRequest(
            requestId: "request-1",
            frameId: frameId,
            mode: mode,
            locale: "ru-RU",
            trigger: trigger,
            preferredPrivacyTier: preferredPrivacyTier,
            localBundle: DeepCriticLocalBundle(
                semantics: semantics,
                critique: critique,
                plan: plan,
                fusedNeuralEvidence: nil,
                neuralMetadata: nil,
                traceExcerpt: traceExcerpt,
                visualAttachmentCandidate: visualAttachmentCandidate
            ),
            constraints: constraints,
            correlation: DeepCriticCorrelation(
                localCritiqueSummaryId: critique.summary.id,
                localPlanSummaryId: action.id,
                localNeuralBundleVersion: nil,
                sessionEphemeralId: "session-1"
            )
        )
    }

    func makeCompletedResponse(advisory: DeepCriticAdvisory? = nil) -> DeepCriticResponse {
        makeResponse(
            requestId: "request-1",
            frameId: "frame-1",
            status: .completed,
            advisory: advisory ?? DeepCriticAdvisory(
                disposition: .hardCaseFlag,
                issueReviews: [],
                strengthReviews: [],
                actionReviews: [],
                explanationPatch: nil,
                teacherEvidence: nil,
                teacherEvidenceMetadata: nil,
                hardCaseTags: ["needs_review"],
                confidence: 0.62
            ),
            failureReason: nil
        )
    }

    func makeResponse(requestId: String,
                      frameId: String,
                      status: DeepCriticResponseStatus,
                      advisory: DeepCriticAdvisory?,
                      failureReason: DeepCriticFailureReason?) -> DeepCriticResponse {
        DeepCriticResponse(
            schemaVersion: DeepCriticTransportEnvelope.currentSchemaVersion,
            responseId: "response-1",
            requestId: requestId,
            frameId: frameId,
            status: status,
            advisory: advisory,
            failureReason: failureReason,
            producedAt: Date(timeIntervalSince1970: 1_777_000_000)
        )
    }

    func makeTeacherEvidenceSnapshot() -> NeuralEvidenceSnapshot {
        NeuralEvidenceSnapshot(
            schemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: "frame-1",
            mode: .pause,
            capturedAt: Date(timeIntervalSince1970: 1_777_000_000),
            bundleVersion: "teacher.bundle.v1",
            headOutputs: []
        )
    }

    func makeTeacherEvidenceMetadata(frameId: String) -> NeuralEvidenceRuntimeMetadata {
        NeuralEvidenceRuntimeMetadata(
            metadataSchemaVersion: NeuralEvidenceSnapshot.currentSchemaVersion,
            frameId: frameId,
            mode: .pause,
            providerKind: .remoteTeacher,
            inferenceTarget: .offloaded,
            modelFamily: "teacher",
            modelVersion: "v1",
            preprocessingVersion: "prep.v1",
            thresholdProfile: "teacher.debug",
            producedAt: Date(timeIntervalSince1970: 1_777_000_010),
            latencyMs: 120,
            roiStrategy: .fullFrameOnly,
            failureReason: nil
        )
    }
}
