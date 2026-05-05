import XCTest
@testable import shafinMultitool

final class VisualSemanticEvidenceCoordinatorTests: XCTestCase {
    func testSkipsWhenProviderUnavailable() async {
        let coordinator = VisualSemanticEvidenceCoordinator(provider: nil)
        let request = makeRequest()

        let result = await coordinator.fetchEvidence(request: request)

        switch result {
        case let .skipped(reason, diagnostics):
            XCTAssertEqual(reason, "provider_unavailable")
            XCTAssertEqual(diagnostics.fallbackReason, "provider_unavailable")
        default:
            XCTFail("Expected skipped(provider_unavailable)")
        }
    }

    func testRejectsLiveModeWithoutCallingProvider() async {
        let spy = VisualEvidenceInvocationSpyProvider()
        let coordinator = VisualSemanticEvidenceCoordinator(provider: spy)
        let request = makeRequest(mode: .live)

        let result = await coordinator.fetchEvidence(request: request)

        switch result {
        case let .rejected(violations, diagnostics):
            XCTAssertTrue(violations.contains(.modeNotPause))
            XCTAssertEqual(diagnostics.fallbackReason, "mode_not_pause")
        default:
            XCTFail("Expected rejected(mode_not_pause)")
        }

        let invocations = await spy.invocations
        XCTAssertEqual(invocations, 0)
    }

    func testAcceptsValidResponse() async {
        let response = makeValidResponse()
        let provider = MockVLMVisualEvidenceProvider(fixedResponse: response)
        let coordinator = VisualSemanticEvidenceCoordinator(provider: provider)
        let request = makeRequest()

        let result = await coordinator.fetchEvidence(request: request)

        switch result {
        case let .accepted(validation, diagnostics):
            XCTAssertTrue(validation.accepted)
            XCTAssertEqual(validation.acceptedPrimaryEntityRef, "ent-person-1")
            XCTAssertEqual(validation.acceptedSecondaryEntityRef, "ent-vase-1")
            XCTAssertEqual(validation.acceptedSuggestedActionIds, [.removeDistractingObject])
            XCTAssertNil(diagnostics.fallbackReason)
        default:
            XCTFail("Expected accepted validation")
        }
    }

    func testRejectsInvalidResponseAndFallsBackDeterministically() async {
        let response = makeInvalidResponseWithContradictoryActions()
        let provider = MockVLMVisualEvidenceProvider(fixedResponse: response)
        let coordinator = VisualSemanticEvidenceCoordinator(provider: provider)
        let request = makeRequest()

        let result = await coordinator.fetchEvidence(request: request)

        switch result {
        case let .rejected(violations, diagnostics):
            XCTAssertTrue(violations.contains(.contradictoryKeepAndCorrect))
            XCTAssertEqual(diagnostics.fallbackReason, "validation_failed")
        default:
            XCTFail("Expected rejected(contradictory_keep_and_correct)")
        }
    }

    func testFailsOnTimeout() async {
        let provider = MockVLMVisualEvidenceProvider(sleepMs: 250)
        let coordinator = VisualSemanticEvidenceCoordinator(provider: provider, timeoutMs: 20)
        let request = makeRequest()

        let result = await coordinator.fetchEvidence(request: request)

        switch result {
        case let .failed(reason, diagnostics):
            XCTAssertEqual(reason, "timeout")
            XCTAssertEqual(diagnostics.fallbackReason, "timeout")
        default:
            XCTFail("Expected failed(timeout)")
        }
    }

    @MainActor
    func testPipelineIntegrationBuildsPauseRequestAndAcceptsProviderEvidence() async {
        let pipeline = AnalysisPipeline(
            reasoningProvider: nil,
            visualEvidenceProvider: MockVLMVisualEvidenceProvider(),
            neuralEvidenceService: nil
        )
        let snapshot = makeSnapshot(mode: .pause)
        let semantics = makeSemantics(mode: .pause, frameId: snapshot.frameId)
        let critique = makeCritique(mode: .pause, frameId: snapshot.frameId)
        let plan = makePlan(mode: .pause, frameId: snapshot.frameId, issueId: critique.issues[0].id)
        let request = pipeline.testingBuildPauseVisualEvidenceRequest(
            snapshot: snapshot,
            semantics: semantics,
            critique: critique,
            plan: plan,
            neuralOutcome: nil
        )

        XCTAssertEqual(request.mode, .pause)
        XCTAssertEqual(request.frameId, snapshot.frameId)
        XCTAssertEqual(request.localContext.critique.frameId, snapshot.frameId)

        let result = await pipeline.testingResolvePauseVisualEvidence(request: request)
        switch result {
        case let .accepted(validation, _):
            XCTAssertTrue(validation.accepted)
        default:
            XCTFail("Expected accepted provider evidence in pipeline integration test")
        }
    }
}

private actor VisualEvidenceInvocationSpyProvider: VisualSemanticEvidenceProvider {
    let providerId = "spy_visual_evidence"
    let capabilities = VisualSemanticEvidenceCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsPrivacyTiers: [.structuredOnly, .redactedVisual]
    )

    private(set) var invocations = 0

    func fetchVisualEvidence(request: VLMVisualEvidenceRequest) async throws -> VLMVisualEvidenceResponse {
        invocations += 1
        return makeValidResponse(
            mode: request.mode,
            privacyTier: request.privacyTier,
            requestId: request.requestId,
            frameId: request.frameId
        )
    }
}

private func makeRequest(mode: AnalysisMode = .pause,
                         frameId: String = "pause-frame-301",
                         requestId: String = "vlm-req-301") -> VLMVisualEvidenceRequest {
    let critique = makeCritique(mode: mode, frameId: frameId)
    let plan = makePlan(mode: mode, frameId: frameId, issueId: critique.issues[0].id)
    let localContext = VLMVisualEvidenceLocalContext(
        frameFeatureSnapshotExcerpt: ["mode": mode.rawValue],
        sceneSemantics: makeSemantics(mode: mode, frameId: frameId),
        critique: critique,
        recommendationPlan: plan,
        semanticTipDrafts: [
            SemanticTipDraftContext(
                draftId: "draft-1",
                tipType: nil,
                actionType: .removeDistractingObject,
                actionFrame: .moveObject,
                targetEntityRef: "ent-vase-1",
                targetEntityKind: .prop,
                targetEntityDisplayLabel: "ваза",
                linkedIssueIds: [critique.issues[0].id],
                linkedStrengthIds: [],
                linkedActionIds: [plan.primaryAction?.id ?? "action-remove-vase"],
                priorityBand: .primaryCorrective
            )
        ],
        groundedEntities: [
            VLMGroundedEntity(
                entityRef: "ent-person-1",
                kind: .person,
                role: .primarySubject,
                region: NormalizedRect(x: 0.20, y: 0.12, width: 0.33, height: 0.46),
                detectorLabel: "person",
                detectorConfidence: 0.90,
                displayLabelCandidate: "герой",
                displayLabelConfidence: 0.90
            ),
            VLMGroundedEntity(
                entityRef: "ent-vase-1",
                kind: .prop,
                role: .distractingObject,
                region: NormalizedRect(x: 0.35, y: 0.14, width: 0.15, height: 0.25),
                detectorLabel: "vase",
                detectorConfidence: 0.83,
                displayLabelCandidate: "ваза",
                displayLabelConfidence: 0.83
            )
        ],
        localNeuralEvidenceSummary: nil
    )

    return VLMVisualEvidenceRequest(
        schemaVersion: .s1,
        requestId: requestId,
        frameId: frameId,
        mode: mode,
        locale: "ru-RU",
        privacyTier: .structuredOnly,
        trigger: .ambiguousLocalCase,
        visualInput: nil,
        localContext: localContext,
        allowedCatalog: .prS01,
        constraints: .default,
        correlation: VLMVisualEvidenceCorrelation(
            localCritiqueSummaryId: critique.summary.id,
            localPlanSummaryId: plan.primaryAction?.id,
            semanticCatalogVersion: VLMAllowedSemanticCatalog.prS01.catalogVersion,
            offloadingSchemaVersion: "h12",
            providerConfigVersion: "test",
            sessionEphemeralId: "session-301"
        )
    )
}

private func makeValidResponse(mode: AnalysisMode = .pause,
                               privacyTier: VLMPrivacyTier = .structuredOnly,
                               requestId: String = "vlm-req-301",
                               frameId: String = "pause-frame-301") -> VLMVisualEvidenceResponse {
    VLMVisualEvidenceResponse(
        schemaVersion: .s1,
        requestId: requestId,
        frameId: frameId,
        mode: mode,
        providerId: "mock-vlm-semantic-v1",
        status: .completed,
        primaryEntityRef: "ent-person-1",
        primaryEntityKind: .person,
        primaryEntityDisplayLabelCandidate: "герой",
        primaryEntityLabelConfidence: 0.88,
        secondaryEntityRef: "ent-vase-1",
        secondaryEntityKind: .prop,
        secondaryEntityDisplayLabelCandidate: "ваза",
        secondaryEntityLabelConfidence: 0.82,
        observations: [
            VLMVisualEvidenceObservation(
                observationId: "obs-301",
                dimension: .faceVisibility,
                polarity: .supportsProblem,
                score: 0.74,
                confidence: 0.80,
                uncertaintyReasons: [],
                primaryEntityRef: "ent-person-1",
                secondaryEntityRef: "ent-vase-1",
                visualProblemType: .faceContourOcclusion,
                visualStrengthType: nil,
                supportedIssueIds: ["issue-301"],
                supportedStrengthIds: [],
                suggestedActionIds: [.removeDistractingObject],
                evidenceNote: "Предмет перекрывает контур лица."
            )
        ],
        relations: [
            VLMEntityRelation(
                relationId: "rel-301",
                sourceEntityRef: "ent-vase-1",
                targetEntityRef: "ent-person-1",
                relationType: .blocks,
                dimension: .faceVisibility,
                score: 0.70,
                confidence: 0.79,
                uncertaintyReasons: [],
                supportedObservationIds: ["obs-301"]
            )
        ],
        suggestedActionIds: [.removeDistractingObject],
        explanation: VLMSecondaryExplanation(
            language: "ru-RU",
            summary: "Сейчас предмет перекрывает линию лица.",
            caveats: []
        ),
        safety: VLMEvidenceSafetyReport(passed: true, violations: []),
        diagnostics: VLMEvidenceDiagnostics(
            latencyMs: 30,
            providerModelFamily: "mock-vlm",
            providerModelVersion: "s1-dev",
            promptVersion: "vlm-evidence-s1",
            privacyTier: privacyTier,
            fallbackReason: nil
        )
    )
}

private func makeInvalidResponseWithContradictoryActions() -> VLMVisualEvidenceResponse {
    var response = makeValidResponse()
    response = VLMVisualEvidenceResponse(
        schemaVersion: response.schemaVersion,
        requestId: response.requestId,
        frameId: response.frameId,
        mode: response.mode,
        providerId: response.providerId,
        status: response.status,
        primaryEntityRef: response.primaryEntityRef,
        primaryEntityKind: response.primaryEntityKind,
        primaryEntityDisplayLabelCandidate: response.primaryEntityDisplayLabelCandidate,
        primaryEntityLabelConfidence: response.primaryEntityLabelConfidence,
        secondaryEntityRef: response.secondaryEntityRef,
        secondaryEntityKind: response.secondaryEntityKind,
        secondaryEntityDisplayLabelCandidate: response.secondaryEntityDisplayLabelCandidate,
        secondaryEntityLabelConfidence: response.secondaryEntityLabelConfidence,
        observations: response.observations,
        relations: response.relations,
        suggestedActionIds: [.removeDistractingObject, .keepCurrentSetup],
        explanation: response.explanation,
        safety: response.safety,
        diagnostics: response.diagnostics
    )
    return response
}

private func makeSnapshot(mode: AnalysisMode,
                          frameId: String = "pause-frame-301") -> FrameFeatureSnapshot {
    FrameFeatureSnapshot(
        frameId: frameId,
        mode: mode,
        capturedAt: Date(timeIntervalSince1970: 1_720_000_000),
        sources: FeatureSourceStatus(
            vision: SourceState(available: true, freshnessMs: 20, confidence: 0.90),
            horizon: SourceState(available: true, freshnessMs: 20, confidence: 0.88),
            lighting: SourceState(available: true, freshnessMs: 30, confidence: 0.84),
            detr: SourceState(available: true, freshnessMs: 45, confidence: 0.86),
            aesthetic: SourceState(available: true, freshnessMs: 120, confidence: 0.73)
        ),
        composition: .init(horizontalOffset: 0.20, verticalOffset: 0.06, subjectAreaRatio: 0.18, saliencyLeftRightBalance: 0.12, saliencyTopBottomBalance: 0.04),
        subjectSignals: .init(faceDetected: true, personDetected: true, personCount: 1, topObjectLabel: "vase", topObjectConfidence: 0.83, primaryCandidateRegion: NormalizedRect(x: 0.20, y: 0.12, width: 0.33, height: 0.46), primaryCandidateConfidence: 0.90),
        horizon: .init(angleDegrees: 0.9, confidence: 0.90),
        lighting: .init(exposureBiasHint: -0.1, backlightIndex: 0.41, keyToFillRatio: 1.4),
        motion: .init(state: .still, shakeLevel: 0.12),
        aesthetics: .init(score: 0.63, scoreConfidence: 0.70),
        objects: .init(totalCount: 3, topKLabels: ["vase", "lamp", "book"]),
        technicalFlags: []
    )
}

private func makeSemantics(mode: AnalysisMode, frameId: String) -> SceneSemanticsReport {
    SceneSemanticsReport(
        frameId: frameId,
        mode: mode,
        sceneType: .singleCharacterMedium,
        sceneTypeConfidence: 0.81,
        primarySubject: .init(kind: .person, label: "person", region: NormalizedRect(x: 0.20, y: 0.12, width: 0.33, height: 0.46), confidence: 0.89),
        dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.32, backgroundClutterScore: 0.36),
        readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.28, separationScore: 0.72),
        ambiguities: [],
        assumptions: []
    )
}

private func makeCritique(mode: AnalysisMode, frameId: String) -> CritiqueReport {
    CritiqueReport(
        frameId: frameId,
        mode: mode,
        verdict: .mixed,
        verdictConfidence: 0.74,
        strengths: [
            FrameStrength(
                id: "strength-301",
                type: .goodSubjectIsolation,
                confidence: 0.66,
                rationale: "Субъект отделен от фона.",
                evidence: [EvidenceRef(source: .semantics, key: "readability.subjectReadable", value: "true", confidence: 0.8)]
            )
        ],
        issues: [
            FrameIssue(
                id: "issue-301",
                type: .backgroundCompetesWithSubject,
                severity: 0.63,
                confidence: 0.75,
                rationale: "Предмет рядом с лицом конкурирует за внимание.",
                evidence: [EvidenceRef(source: .semantics, key: "dominance.focusCompetitionScore", value: "0.32", confidence: 0.75)],
                affectedRegion: NormalizedRect(x: 0.35, y: 0.14, width: 0.15, height: 0.25),
                suggestedFixTypes: [.angleAdjustment]
            )
        ],
        summary: CritiqueSummary(id: "summary-301", shortVerdict: "Кадр близок к рабочему, но есть помеха у лица."),
        traceRefs: ["trace-301"],
        fallbackUsed: false
    )
}

private func makePlan(mode: AnalysisMode, frameId: String, issueId: String) -> RecommendationPlan {
    RecommendationPlan(
        frameId: frameId,
        mode: mode,
        inputVerdict: .mixed,
        primaryAction: RecommendationAction(
            id: "action-remove-vase",
            actionType: .reduceBackgroundDistractions,
            priority: 1,
            targetRegion: NormalizedRect(x: 0.35, y: 0.14, width: 0.15, height: 0.25),
            linkedIssueIds: [issueId],
            expectedOutcome: "Уберите предмет у лица, чтобы восстановить контур героя.",
            guardrail: ActionGuardrail(requiresStillCamera: false, minConfidence: 0.45, suppressWhenMoving: true),
            overlayHint: nil
        ),
        secondaryActions: [],
        deferredActions: [],
        noChangeRationale: nil,
        planConfidence: 0.74
    )
}
