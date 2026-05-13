import XCTest
@testable import shafinMultitool

final class PauseReasoningCoordinatorTests: XCTestCase {
    func testSkipsWhenProviderUnavailable() async {
        let coordinator = PauseReasoningCoordinator(provider: nil)
        let request = makeRequest(providerConfigVersion: "disabled")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .skipped(reason, diagnostics):
            XCTAssertEqual(reason, "provider_unavailable")
            XCTAssertEqual(diagnostics.fallbackReason, "provider_unavailable")
        default:
            XCTFail("Expected skipped(provider_unavailable)")
        }
    }

    func testAppliesValidRefinementPatch() async {
        let coordinator = PauseReasoningCoordinator(provider: ValidStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-valid")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .refined(presentation, _, diagnostics):
            XCTAssertEqual(presentation.frameId, request.frameId)
            XCTAssertEqual(presentation.shortVerdict, "Обновленный вердикт без смены класса решения.")
            XCTAssertTrue(presentation.strengths.first?.rationale.contains("уточнение") == true)
            XCTAssertTrue(presentation.issues.first?.rationale.contains("уточнение") == true)
            XCTAssertTrue(presentation.actions.first?.expectedOutcome.contains("уточнение") == true)
            XCTAssertEqual(diagnostics.fallbackReason, nil)
        default:
            XCTFail("Expected refined presentation")
        }
    }

    func testRejectsLowFaithfulnessAsFullReject() async {
        let coordinator = PauseReasoningCoordinator(provider: LowFaithfulnessStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-low-faithfulness")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .rejected(violations, diagnostics):
            XCTAssertTrue(violations.contains(.lowFaithfulness))
            XCTAssertEqual(diagnostics.fallbackReason, "low_faithfulness")
        default:
            XCTFail("Expected rejected(low_faithfulness)")
        }
    }

    func testAllowsPartialAcceptForUnknownRuntimeIds() async {
        let coordinator = PauseReasoningCoordinator(provider: UnknownIdsStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-unknown-ids")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .refined(presentation, _, diagnostics):
            XCTAssertEqual(presentation.strengths.first?.rationale, "Хорошее разделение объекта и фона (уточнение).")
            XCTAssertEqual(diagnostics.fallbackReason, "validation_partial_accept")
        default:
            XCTFail("Expected refined with partial accept")
        }
    }

    func testFailsOnTimeout() async {
        let coordinator = PauseReasoningCoordinator(provider: SlowStubProvider(sleepMs: 120))
        let request = makeRequest(
            providerConfigVersion: "stub-timeout",
            constraints: ReasoningConstraints(
                maxLatencyMs: 20,
                maxOutputTokens: 128,
                strictDeterministicGuard: true,
                allowSpeculativeTone: false
            )
        )

        let result = await coordinator.refine(request: request)

        switch result {
        case let .failed(reason, diagnostics):
            XCTAssertEqual(reason, "timeout")
            XCTAssertEqual(diagnostics.fallbackReason, "timeout")
        default:
            XCTFail("Expected failed(timeout)")
        }
    }

    func testRejectsWhenModeIsLive() async {
        let coordinator = PauseReasoningCoordinator(provider: ValidStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-live-mode", mode: .live)

        let result = await coordinator.refine(request: request)

        switch result {
        case let .rejected(violations, diagnostics):
            XCTAssertTrue(violations.contains(.modeNotPause))
            XCTAssertEqual(diagnostics.fallbackReason, "mode_not_pause")
        default:
            XCTFail("Expected rejected(mode_not_pause)")
        }
    }

    func testDoesNotInvokeProviderWhenModeIsLive() async {
        let spyProvider = InvocationSpyProvider()
        let coordinator = PauseReasoningCoordinator(provider: spyProvider)
        let request = makeRequest(providerConfigVersion: "spy-live-mode", mode: .live)

        _ = await coordinator.refine(request: request)

        let invocationCount = await spyProvider.invocationCount
        XCTAssertEqual(invocationCount, 0)
    }

    func testRejectsWhenRequestOrFrameMismatch() async {
        let coordinator = PauseReasoningCoordinator(provider: MismatchedIdsStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-mismatch")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .rejected(violations, diagnostics):
            XCTAssertTrue(violations.contains(.unknownRuntimeId))
            XCTAssertEqual(diagnostics.fallbackReason, "validation_failed")
        default:
            XCTFail("Expected rejected(unknown_runtime_id)")
        }
    }

    func testDropsUnsupportedTraceLinksWithPartialAccept() async {
        let coordinator = PauseReasoningCoordinator(provider: UnsupportedTraceLinksStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-trace-links")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .refined(presentation, optionalTraceItems, diagnostics):
            XCTAssertEqual(presentation.frameId, request.frameId)
            XCTAssertTrue(optionalTraceItems.isEmpty)
            XCTAssertEqual(diagnostics.fallbackReason, "validation_partial_accept")
        default:
            XCTFail("Expected refined with trace partial accept")
        }
    }

    func testRejectsMixedVerdictSemanticShift() async {
        let coordinator = PauseReasoningCoordinator(provider: MixedVerdictShiftStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-mixed-shift")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .rejected(violations, diagnostics):
            XCTAssertTrue(violations.contains(.attemptsToChangeVerdict))
            XCTAssertEqual(diagnostics.fallbackReason, "validation_failed")
        default:
            XCTFail("Expected rejected(attempts_to_change_verdict)")
        }
    }

    func testRejectsNoChangeOverrideWhenActionExists() async {
        let coordinator = PauseReasoningCoordinator(provider: InvalidNoChangeOverrideStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-invalid-no-change")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .rejected(violations, diagnostics):
            XCTAssertTrue(violations.contains(.attemptsToChangeActionTaxonomy))
            XCTAssertEqual(diagnostics.fallbackReason, "validation_failed")
        default:
            XCTFail("Expected rejected(attempts_to_change_action_taxonomy)")
        }
    }

    func testRejectsTaxonomyMutationFromSafetyReport() async {
        let coordinator = PauseReasoningCoordinator(provider: TaxonomyMutationSafetyStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-taxonomy-mutation")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .rejected(violations, diagnostics):
            XCTAssertTrue(violations.contains(.attemptsToChangeIssueTaxonomy))
            XCTAssertEqual(diagnostics.fallbackReason, "validation_failed")
        default:
            XCTFail("Expected rejected(attempts_to_change_issue_taxonomy)")
        }
    }

    func testTruncatesLongOutputWithPartialAccept() async {
        let coordinator = PauseReasoningCoordinator(provider: LongOutputStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-long-output")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .refined(presentation, _, diagnostics):
            XCTAssertLessThanOrEqual(presentation.issues.first?.rationale.count ?? 0, 80)
            XCTAssertEqual(diagnostics.fallbackReason, "validation_partial_accept")
        default:
            XCTFail("Expected refined(validation_partial_accept)")
        }
    }

    func testAcceptsValidatedOptionalTraceItems() async {
        let coordinator = PauseReasoningCoordinator(provider: ValidOptionalTraceStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-optional-trace")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .refined(_, optionalTraceItems, diagnostics):
            XCTAssertEqual(optionalTraceItems.count, 1)
            XCTAssertEqual(optionalTraceItems.first?.sourceKind, .optionalReasoning)
            XCTAssertEqual(diagnostics.fallbackReason, nil)
        default:
            XCTFail("Expected refined with validated optional trace item")
        }
    }

    func testRejectsOptionalTraceWithDeterministicCertainty() async {
        let coordinator = PauseReasoningCoordinator(provider: DeterministicCertaintyOptionalTraceStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-deterministic-certainty")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .refined(_, optionalTraceItems, diagnostics):
            XCTAssertTrue(optionalTraceItems.isEmpty)
            XCTAssertEqual(diagnostics.fallbackReason, "validation_partial_accept")
        default:
            XCTFail("Expected refined with dropped optional trace")
        }
    }

    func testMarksConflictMetadataForOptionalTrace() async {
        let coordinator = PauseReasoningCoordinator(provider: ConflictOptionalTraceStubProvider())
        let request = makeRequest(providerConfigVersion: "stub-conflict-metadata")

        let result = await coordinator.refine(request: request)

        switch result {
        case let .refined(_, optionalTraceItems, _):
            XCTAssertEqual(optionalTraceItems.count, 1)
            XCTAssertNotNil(optionalTraceItems.first?.metadata["conflictWith"])
        default:
            XCTFail("Expected refined with conflict metadata")
        }
    }

    func testFailsWhenCanceledDueToStateChange() async {
        let coordinator = PauseReasoningCoordinator(provider: SlowStubProvider(sleepMs: 300))
        let request = makeRequest(providerConfigVersion: "stub-cancel")

        let task = Task { await coordinator.refine(request: request) }
        task.cancel()
        let result = await task.value

        switch result {
        case let .failed(reason, diagnostics):
            XCTAssertEqual(reason, "canceled_due_to_state_change")
            XCTAssertEqual(diagnostics.fallbackReason, "canceled_due_to_state_change")
        default:
            XCTFail("Expected failed(canceled_due_to_state_change)")
        }
    }

    @MainActor
    func testPipelineDeterminismWithoutProviderKeepsBaselinePausePresentation() async {
        let request = makeRequest(providerConfigVersion: "pipeline-disabled-provider")
        guard let deterministicTrace = request.trace else {
            XCTFail("Expected deterministic trace")
            return
        }

        let pipeline = AnalysisPipeline(reasoningProvider: nil)
        pipeline.testingPreparePauseState(
            critique: request.pausePresentationDraft,
            traceBundle: deterministicTrace,
            revision: 1
        )

        pipeline.testingSchedulePauseReasoningRefinement(request: request, revision: 1)
        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertEqual(pipeline.currentPauseCritique, request.pausePresentationDraft)
        XCTAssertEqual(pipeline.testingPauseTraceBundle, deterministicTrace)
    }

    @MainActor
    func testPipelineCancelsLateReasoningAfterPauseExit() async {
        let request = makeRequest(providerConfigVersion: "pipeline-cancel")
        guard let deterministicTrace = request.trace else {
            XCTFail("Expected deterministic trace")
            return
        }

        let pipeline = AnalysisPipeline(reasoningProvider: SlowStubProvider(sleepMs: 300))
        pipeline.testingPreparePauseState(
            critique: request.pausePresentationDraft,
            traceBundle: deterministicTrace,
            revision: 1
        )

        pipeline.testingSchedulePauseReasoningRefinement(request: request, revision: 1)
        pipeline.clearPausePresentationState()
        try? await Task.sleep(nanoseconds: 420_000_000)

        XCTAssertNil(pipeline.currentPauseCritique)
        XCTAssertNil(pipeline.testingPauseTraceBundle)
    }

    func testDeterministicBaselineRequestRemainsUnchangedWithoutProvider() async {
        let request = makeRequest(providerConfigVersion: "determinism-check")
        let baselineDraft = request.pausePresentationDraft
        let coordinator = PauseReasoningCoordinator(provider: nil)

        let result = await coordinator.refine(request: request)

        switch result {
        case .skipped:
            XCTAssertEqual(request.pausePresentationDraft, baselineDraft)
        default:
            XCTFail("Expected skipped for disabled provider")
        }
    }
}

private actor ValidStubProvider: ReasoningProvider {
    let providerId = "valid_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(
                shortVerdictOverride: "Обновленный вердикт без смены класса решения.",
                whyGoodByStrengthId: ["str_1": "Хорошее разделение объекта и фона (уточнение)."],
                whyProblematicByIssueId: ["iss_1": "Фон спорит с объектом (уточнение)."],
                actionRationaleByActionId: ["act_1": "Сместите камеру влево и проверьте читаемость (уточнение)."],
                noChangeRationaleOverride: nil
            ),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor LowFaithfulnessStubProvider: ReasoningProvider {
    let providerId = "low_faithfulness_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(
                shortVerdictOverride: "Гарантированно идеальный кадр при любом свете.",
                whyGoodByStrengthId: [:],
                whyProblematicByIssueId: [:],
                actionRationaleByActionId: [:],
                noChangeRationaleOverride: nil
            ),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor UnknownIdsStubProvider: ReasoningProvider {
    let providerId = "unknown_ids_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(
                shortVerdictOverride: nil,
                whyGoodByStrengthId: [
                    "str_1": "Хорошее разделение объекта и фона (уточнение).",
                    "str_unknown": "Неизвестный id"
                ],
                whyProblematicByIssueId: [:],
                actionRationaleByActionId: [:],
                noChangeRationaleOverride: nil
            ),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor SlowStubProvider: ReasoningProvider {
    let providerId = "slow_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    private let sleepMs: UInt64

    init(sleepMs: UInt64) {
        self.sleepMs = sleepMs
    }

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        try await Task.sleep(nanoseconds: sleepMs * 1_000_000)
        return ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: Int(sleepMs))
        )
    }
}

private actor InvocationSpyProvider: ReasoningProvider {
    let providerId = "invocation_spy_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    private(set) var invocationCount: Int = 0

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        invocationCount += 1
        return ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(shortVerdictOverride: "stub"),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor MismatchedIdsStubProvider: ReasoningProvider {
    let providerId = "mismatch_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        ReasoningResponse(
            requestId: "other_request",
            frameId: "other_frame",
            providerId: providerId,
            textPatch: PauseTextPatch(
                shortVerdictOverride: "Кадр рабочий, но можно чуть улучшить читаемость."
            ),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor UnsupportedTraceLinksStubProvider: ReasoningProvider {
    let providerId = "unsupported_trace_links_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        let invalidOptionalTrace = ExplainabilityTraceItem(
            id: "trc_optional_invalid_1",
            frameId: request.frameId,
            mode: .pause,
            stage: .interpretation,
            sourceKind: .optionalReasoning,
            certainty: .speculative,
            confidence: 0.61,
            timestampMs: 1_710_000_000,
            statement: "Предположительно сдвиг кадра улучшит акцент.",
            evidenceKeys: [],
            dependsOn: [],
            links: [TraceLink(kind: .action, refId: "act_1")],
            audiences: [.debug]
        )

        return ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(
                whyProblematicByIssueId: ["iss_1": "Фон конкурирует с объектом и съедает акцент (уточнение)."]
            ),
            optionalTraceItems: [invalidOptionalTrace],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor MixedVerdictShiftStubProvider: ReasoningProvider {
    let providerId = "mixed_shift_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(shortVerdictOverride: "Хороший кадр, оставьте как есть."),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor InvalidNoChangeOverrideStubProvider: ReasoningProvider {
    let providerId = "invalid_no_change_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(noChangeRationaleOverride: "Ничего не меняйте, кадр уже готов."),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor TaxonomyMutationSafetyStubProvider: ReasoningProvider {
    let providerId = "taxonomy_mutation_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(whyProblematicByIssueId: ["iss_1": "Фон конфликтует с акцентом."]),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: false, violations: [.attemptsToChangeIssueTaxonomy]),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor LongOutputStubProvider: ReasoningProvider {
    let providerId = "long_output_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 80
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        let longIssueText = "Фон конкурирует с главным объектом и снижает читаемость акцента, поэтому сначала упростите фон, затем проверьте баланс после сдвига кадра и повторной оценки."
        return ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(whyProblematicByIssueId: ["iss_1": longIssueText]),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor ValidOptionalTraceStubProvider: ReasoningProvider {
    let providerId = "valid_optional_trace_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        let optionalTrace = ExplainabilityTraceItem(
            id: "trc_optional_reasoning_1",
            frameId: request.frameId,
            mode: .pause,
            stage: .interpretation,
            sourceKind: .optionalReasoning,
            certainty: .probabilistic,
            confidence: 0.74,
            timestampMs: 1_710_000_400,
            statement: "Вероятно, дополнительный акцент на объекте повысит читаемость.",
            evidenceKeys: [],
            dependsOn: ["obs_semantics_1"],
            links: [TraceLink(kind: .summary, refId: "summary_1")],
            audiences: [.core, .debug]
        )

        return ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(whyProblematicByIssueId: ["iss_1": "Фон конкурирует с объектом (уточнение)."]),
            optionalTraceItems: [optionalTrace],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor DeterministicCertaintyOptionalTraceStubProvider: ReasoningProvider {
    let providerId = "deterministic_certainty_optional_trace_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        let invalidOptionalTrace = ExplainabilityTraceItem(
            id: "trc_optional_deterministic_1",
            frameId: request.frameId,
            mode: .pause,
            stage: .interpretation,
            sourceKind: .optionalReasoning,
            certainty: .deterministic,
            confidence: 0.70,
            timestampMs: 1_710_000_500,
            statement: "Опциональное объяснение с deterministic certainty.",
            evidenceKeys: [],
            dependsOn: ["obs_semantics_1"],
            links: [TraceLink(kind: .summary, refId: "summary_1")],
            audiences: [.core, .debug]
        )

        return ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(whyProblematicByIssueId: ["iss_1": "Фон конкурирует с объектом (уточнение)."]),
            optionalTraceItems: [invalidOptionalTrace],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private actor ConflictOptionalTraceStubProvider: ReasoningProvider {
    let providerId = "conflict_optional_trace_stub"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 4000,
        maxOutputChars: 200
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        let optionalTrace = ExplainabilityTraceItem(
            id: "trc_optional_conflict_1",
            frameId: request.frameId,
            mode: .pause,
            stage: .interpretation,
            sourceKind: .optionalReasoning,
            certainty: .probabilistic,
            confidence: 0.62,
            timestampMs: 1_710_000_550,
            statement: "Это хороший признак, сцена стала удачной и читаемой.",
            evidenceKeys: [],
            dependsOn: ["obs_semantics_1"],
            links: [TraceLink(kind: .issue, refId: "iss_1")],
            audiences: [.core, .debug]
        )

        return ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(whyProblematicByIssueId: ["iss_1": "Фон конкурирует с объектом (уточнение)."]),
            optionalTraceItems: [optionalTrace],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 1)
        )
    }
}

private func makeRequest(providerConfigVersion: String,
                         constraints: ReasoningConstraints = .pauseDefault,
                         mode: AnalysisMode = .pause) -> ReasoningRequest {
    let frameId = "frame_reasoning_1"

    let strength = FrameStrength(
        id: "str_1",
        type: .goodSubjectIsolation,
        confidence: 0.82,
        rationale: "Хорошее разделение объекта и фона",
        evidence: [EvidenceRef(source: .semantics, key: "semantics.readability.separationScore", value: "0.82")],
        supportingRegion: NormalizedRect(x: 0.30, y: 0.25, width: 0.25, height: 0.35)
    )
    let issue = FrameIssue(
        id: "iss_1",
        type: .backgroundCompetesWithSubject,
        severity: 0.71,
        confidence: 0.73,
        rationale: "Фон конкурирует с главным объектом",
        evidence: [EvidenceRef(source: .semantics, key: "semantics.dominance.backgroundClutterScore", value: "0.78")],
        affectedRegion: NormalizedRect(x: 0.55, y: 0.15, width: 0.35, height: 0.45),
        suggestedFixTypes: [.angleAdjustment]
    )

    let critique = CritiqueReport(
        frameId: frameId,
        mode: mode,
        verdict: .mixed,
        verdictConfidence: 0.68,
        strengths: [strength],
        issues: [issue],
        summary: CritiqueSummary(
            id: "summary_1",
            shortVerdict: "Кадр рабочий, но фон отвлекает внимание.",
            whyGood: "Есть читаемый главный объект.",
            whyProblematic: "Фон перетягивает акцент."
        ),
        traceRefs: ["trc_frame_reasoning_1_crit_i01", "trc_frame_reasoning_1_crit_s01", "trc_frame_reasoning_1_crit_summary_main"],
        fallbackUsed: false
    )

    let action = RecommendationAction(
        id: "act_1",
        actionType: .moveFrameLeft,
        priority: 1,
        targetRegion: NormalizedRect(x: 0.55, y: 0.15, width: 0.35, height: 0.45),
        linkedIssueIds: ["iss_1"],
        expectedOutcome: "Сместите камеру влево, чтобы снизить конкуренцию фона.",
        guardrail: ActionGuardrail(requiresStillCamera: true, minConfidence: 0.50, suppressWhenMoving: true),
        overlayHint: OverlayHint(id: "ov_act_1", kind: .arrow, targetRegion: nil, direction: .left)
    )

    let plan = RecommendationPlan(
        frameId: frameId,
        mode: mode,
        inputVerdict: .mixed,
        primaryAction: action,
        secondaryActions: [],
        deferredActions: [],
        noChangeRationale: nil,
        planConfidence: 0.70
    )

    let trace = makeDeterministicTraceBundle(frameId: frameId, mode: mode, critique: critique, plan: plan)

    let draft = PauseCritiquePresentation(
        frameId: frameId,
        verdict: critique.verdict,
        verdictConfidence: critique.verdictConfidence,
        summaryId: critique.summary.id,
        shortVerdict: critique.summary.shortVerdict,
        whyGood: critique.summary.whyGood,
        whyProblematic: critique.summary.whyProblematic,
        strengths: [
            PauseStrengthRow(
                strengthId: strength.id,
                type: strength.type,
                rationale: strength.rationale,
                confidence: strength.confidence,
                supportingRegion: strength.supportingRegion,
                traceRefId: "trc_frame_reasoning_1_crit_s01"
            )
        ],
        issues: [
            PauseIssueRow(
                issueId: issue.id,
                type: issue.type,
                severity: issue.severity,
                confidence: issue.confidence,
                rationale: issue.rationale,
                affectedRegion: issue.affectedRegion,
                suggestedFixTypes: issue.suggestedFixTypes,
                traceRefId: "trc_frame_reasoning_1_crit_i01"
            )
        ],
        actions: [
            PauseActionRow(
                actionId: action.id,
                actionType: action.actionType,
                priority: action.priority,
                confidence: min(plan.planConfidence, issue.confidence + 0.10),
                linkedIssueIds: action.linkedIssueIds,
                expectedOutcome: action.expectedOutcome,
                targetRegion: action.targetRegion,
                overlayHintId: action.overlayHint?.id,
                traceRefId: "trc_frame_reasoning_1_crit_i01"
            )
        ],
        noChangeRationale: nil,
        assumptions: [],
        traceRootIds: critique.traceRefs,
        fallbackUsed: false
    )

    return ReasoningRequest(
        requestId: "req_reasoning_1",
        frameId: frameId,
        mode: mode,
        locale: "ru-RU",
        critique: critique,
        plan: plan,
        trace: trace,
        pausePresentationDraft: draft,
        constraints: constraints,
        correlation: ReasoningCorrelation(
            pipelineVersion: "camera_analysis_v1",
            contractVersion: "camera_analysis_contracts_v1",
            providerConfigVersion: providerConfigVersion
        )
    )
}

private func makeDeterministicTraceBundle(frameId: String,
                                          mode: AnalysisMode,
                                          critique: CritiqueReport,
                                          plan: RecommendationPlan) -> ExplainabilityTraceBundle {
    let observationId = "obs_semantics_1"
    let issueInterpretationId = "itp_issue_1"
    let strengthInterpretationId = "itp_strength_1"
    let summaryInterpretationId = "itp_summary_1"
    let recommendationId = "rec_action_1"

    let items: [ExplainabilityTraceItem] = [
        ExplainabilityTraceItem(
            id: observationId,
            frameId: frameId,
            mode: mode,
            stage: .observation,
            sourceKind: .semanticsSignal,
            certainty: .probabilistic,
            confidence: 0.95,
            timestampMs: 1_710_000_000,
            statement: "Собраны сигналы читаемости сцены.",
            evidenceKeys: [],
            dependsOn: [],
            links: [],
            audiences: [.core, .debug]
        ),
        ExplainabilityTraceItem(
            id: issueInterpretationId,
            frameId: frameId,
            mode: mode,
            stage: .interpretation,
            sourceKind: .deterministicRule,
            certainty: .deterministic,
            confidence: critique.issues.first?.confidence ?? 0.73,
            timestampMs: 1_710_000_100,
            statement: critique.issues.first?.rationale ?? "Фон конкурирует с главным объектом.",
            evidenceKeys: critique.issues.first?.evidence.map(\.key) ?? [],
            dependsOn: [observationId],
            links: [TraceLink(kind: .issue, refId: "iss_1")],
            audiences: [.core, .debug]
        ),
        ExplainabilityTraceItem(
            id: strengthInterpretationId,
            frameId: frameId,
            mode: mode,
            stage: .interpretation,
            sourceKind: .deterministicRule,
            certainty: .deterministic,
            confidence: critique.strengths.first?.confidence ?? 0.82,
            timestampMs: 1_710_000_200,
            statement: critique.strengths.first?.rationale ?? "Хорошее разделение объекта и фона.",
            evidenceKeys: critique.strengths.first?.evidence.map(\.key) ?? [],
            dependsOn: [observationId],
            links: [TraceLink(kind: .strength, refId: "str_1")],
            audiences: [.core, .debug]
        ),
        ExplainabilityTraceItem(
            id: summaryInterpretationId,
            frameId: frameId,
            mode: mode,
            stage: .interpretation,
            sourceKind: .deterministicRule,
            certainty: .deterministic,
            confidence: critique.verdictConfidence,
            timestampMs: 1_710_000_300,
            statement: critique.summary.shortVerdict,
            evidenceKeys: [],
            dependsOn: [observationId],
            links: [TraceLink(kind: .summary, refId: critique.summary.id)],
            audiences: [.core, .debug]
        ),
        ExplainabilityTraceItem(
            id: recommendationId,
            frameId: frameId,
            mode: mode,
            stage: .recommendation,
            sourceKind: .plannerPolicy,
            certainty: .deterministic,
            confidence: min(plan.planConfidence, (critique.issues.first?.confidence ?? 0.73) + 0.1),
            timestampMs: 1_710_000_350,
            statement: plan.primaryAction?.expectedOutcome ?? "Сместите камеру влево.",
            evidenceKeys: [],
            dependsOn: [issueInterpretationId],
            links: [TraceLink(kind: .action, refId: "act_1")],
            audiences: [.core, .debug]
        )
    ]

    return ExplainabilityTraceBundle(
        frameId: frameId,
        mode: mode,
        items: items,
        rootSummaryIds: [summaryInterpretationId]
    )
}
