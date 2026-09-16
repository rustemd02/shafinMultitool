import XCTest
import ARKit
import simd
@testable import shafinMultitool

/// Exercises the production ViewModel -> parser -> bundle -> remote seam.
/// Only model inference/HTTP are replaced; request state, questions, planning
/// and commit ownership remain the application implementations.
final class SceneRemoteClarificationFlowTests: XCTestCase {
    private final class CountingProjectStore: DBService {
        var saveAttempts = 0

        override func saveUnifiedSceneProject(_ project: UnifiedSceneProject, worldMap: ARWorldMap?, expectedUpdatedAt: Date?) throws {
            saveAttempts += 1
            try super.saveUnifiedSceneProject(project, worldMap: worldMap, expectedUpdatedAt: expectedUpdatedAt)
        }
    }

    private final class MissingLocalProvider: LocalScenePlanProvider {
        func generatePlan(description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle, state: SceneChunkState?) -> ScenePlanProviderResult? { nil }
        func generatePlanAsync(description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle, state: SceneChunkState?) async -> ScenePlanProviderResult? { nil }
    }

    private final class QuestionProvider: RemoteScenePlanProvider {
        var callCount = 0
        var answers: [SceneClarificationAnswer?] = []
        var questions: [SceneClarificationPayload] = []
        var receipts: [SceneRemoteGenerationReceipt] = []
        var terminalFailure: SceneRemoteGenerationFailure?
        var requiresTransferConsent = false
        var transferRequests: [SceneRemoteTransferRequest] = []
        var acceptedTransferCount = 0

        func generateRemotePlanOutcome(
            description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle,
            state: SceneChunkState?, clarificationHandler: SceneRemoteClarificationHandler?,
            transferConsentHandler: SceneRemoteTransferConsentHandler?
        ) async -> SceneRemotePlanOutcome {
            if requiresTransferConsent {
                guard let policy = SceneTransferPolicyFixture.policy(), let fingerprint = policy.fingerprint else {
                    return .failed(.transferPolicyUnavailable)
                }
                let request = SceneRemoteTransferRequest(
                    requestID: UUID(), requestHash: GenerationProvenance.sha256(description),
                    scriptText: description, markedObjectIDs: markedObjects.map(\.canonicalMarkedObjectID),
                    policy: policy, policyFingerprint: fingerprint
                )
                transferRequests.append(request)
                guard let answer = await transferConsentHandler?(request), answer == request.approval,
                      !Task.isCancelled else { return .failed(.transferDeclined) }
                acceptedTransferCount += 1
            }
            return await generateRemotePlanOutcome(
                description: description, markedObjects: markedObjects, anchors: anchors,
                state: state, clarificationHandler: clarificationHandler
            )
        }

        func generateRemotePlanOutcome(
            description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle,
            state: SceneChunkState?, clarificationHandler: SceneRemoteClarificationHandler?
        ) async -> SceneRemotePlanOutcome {
            if let terminalFailure {
                callCount += 1
                return .failed(terminalFailure)
            }
            let result = await generateRemotePlan(
                description: description, markedObjects: markedObjects, anchors: anchors,
                state: state, clarificationHandler: clarificationHandler
            )
            if let terminalFailure { return .failed(terminalFailure) }
            guard let result else { return .unavailable }
            return .plan(result)
        }

        func generateRemotePlan(description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle, state: SceneChunkState?) async -> ScenePlanProviderResult? {
            XCTFail("Production parsing must forward its request-owned clarification handler")
            return nil
        }

        func generateRemotePlan(
            description: String, markedObjects: [MarkedObject], anchors: SourceAnchorBundle,
            state: SceneChunkState?, clarificationHandler: SceneRemoteClarificationHandler?
        ) async -> ScenePlanProviderResult? {
            callCount += 1
            let question = SceneClarificationPayload(
                id: "subject-\(UUID().uuidString)", requestID: UUID(), epoch: 0,
                prompt: "Who is the main subject?", targetReference: nil,
                options: [.init(id: "first", label: "Alex"), .init(id: "second", label: "Mara")],
                allowsFreeText: true, maximumFreeTextCharacters: 160,
                observedDiagnostics: [], attempt: 0
            )
            questions.append(question)
            let answer = await clarificationHandler?(question)
            answers.append(answer)
            guard let answer else { return nil }
            let name = answer == .choice("first") ? "Alex" : "Mara"
            let receipt = SceneRemoteGenerationReceipt(
                jobID: "fixture-job-\(callCount)", requestID: question.requestID,
                requestHash: GenerationProvenance.sha256(description),
                idempotencyKey: "fixture-\(question.requestID.uuidString)",
                backendSchemaVersion: SceneAPIVersion.backendSchemaVersion,
                scriptSchemaVersion: SceneAPIVersion.scriptSchemaVersion,
                modelVersion: "fixture-model", promptVersion: "fixture-prompt",
                providerName: "fixture-provider", providerVersion: "fixture-version"
            )
            receipts.append(receipt)
            // Deliberately returns a valid result even when cancelled: the
            // bundle/VM fence, not the test provider, must suppress it.
            return ScenePlanProviderResult(
                plan: ScenePlanIR(
                    actors: [.init(ref: "actor_1", type: .human, name: name)], objects: [],
                    beats: [.init(ref: "beat_1", actions: [.init(actorRef: "actor_1", type: .stand)])],
                    spatialRelations: [], referenceBindings: .init()
                ),
                usedLegacySceneScriptBridge: true,
                reasonCodes: ["remote_plan_used"],
                generationContributors: [.remoteService(receipt)]
            )
        }
    }

    private func parser(provider: QuestionProvider) -> SceneParserService {
        let parser = SceneParserService(localProvider: MissingLocalProvider())
        parser.configureRemoteOffload(enabled: true, provider: provider)
        return parser
    }

    @MainActor
    private func viewModel(provider: QuestionProvider, projectStore: DBService = .shared) -> SceneGeneratorViewModel {
        let projectName = "remote-clarification-test-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName, projectStore: projectStore, parserService: parser(provider: provider))
        addTeardownBlock { @MainActor in
            _ = await viewModel.teardownAndWait()
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                projectStore.deleteUnifiedSceneProject(named: projectName) { _ in continuation.resume() }
            }
        }
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(cameraTransform: transform, planes: [.init(alignment: .horizontal, y: 0)])
        viewModel.updateGenerationMotionPreferences(reduceMotion: true)
        viewModel.sceneDescription = "A person stands still."
        return viewModel
    }

    @MainActor
    private func question(from viewModel: SceneGeneratorViewModel) async throws -> SceneClarificationPayload {
        let deadline = Date().addingTimeInterval(5)
        while viewModel.clarificationRequest == nil && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try XCTUnwrap(viewModel.clarificationRequest)
    }

    @MainActor
    func testTransferConsentPrecedesSemanticQuestionWithoutConsumingItsBudget() async throws {
        let provider = QuestionProvider()
        provider.requiresTransferConsent = true
        let viewModel = viewModel(provider: provider)
        let generation = Task { await viewModel.generateScene() }
        let transferQuestion = try await question(from: viewModel)
        let transfer = try XCTUnwrap(viewModel.remoteTransferRequest)
        let ownerID = viewModel.generationRequestState.requestID
        let epoch = viewModel.generationRequestState.epoch
        let remaining = viewModel.clarificationAttemptsRemaining
        XCTAssertEqual(transferQuestion.id, transfer.id)
        XCTAssertEqual(transferQuestion.options.map(\.id), ["send", "decline"])
        XCTAssertFalse(transferQuestion.allowsFreeText)
        XCTAssertEqual(provider.callCount, 0)
        XCTAssertEqual(provider.acceptedTransferCount, 0)
        XCTAssertTrue(provider.questions.isEmpty)
        let submission = await viewModel.submitClarificationAnswer(.choice("send"), for: transferQuestion)
        XCTAssertEqual(submission, .accepted)
        let semanticQuestion = try await question(from: viewModel)
        XCTAssertNil(viewModel.remoteTransferRequest)
        XCTAssertNotEqual(semanticQuestion.id, transferQuestion.id)
        XCTAssertEqual(viewModel.clarificationAttemptsRemaining, remaining)
        XCTAssertEqual(semanticQuestion.requestID, ownerID)
        XCTAssertEqual(semanticQuestion.epoch, epoch)
        let answer = await viewModel.submitClarificationAnswer(.choice("second"), for: semanticQuestion)
        XCTAssertEqual(answer, .accepted)
        await generation.value
        XCTAssertEqual(provider.transferRequests.count, 1)
        XCTAssertEqual(provider.acceptedTransferCount, 1)
        XCTAssertEqual(provider.answers.first ?? nil, .choice("second"))
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 1)
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
    }

    @MainActor
    func testDecliningTransferPreservesSavedSceneAndEditableDraftWithoutFallback() async throws {
        let provider = QuestionProvider()
        let viewModel = viewModel(provider: provider)
        let originalGeneration = Task { await viewModel.generateScene() }
        let originalQuestion = try await question(from: viewModel)
        _ = await viewModel.submitClarificationAnswer(.choice("second"), for: originalQuestion)
        await originalGeneration.value
        let previousPlan = viewModel.plannedScene
        let previousScript = viewModel.parsedScript
        let previousCommits = viewModel.testingGenerationCommitCount
        let previousCalls = provider.callCount
        provider.requiresTransferConsent = true
        viewModel.sceneDescription = "A person walks across the room."
        let expectedDraft = viewModel.sceneDescription
        let generation = Task { await viewModel.generateScene() }
        let consent = try await question(from: viewModel)
        let submission = await viewModel.submitClarificationAnswer(.choice("decline"), for: consent)
        XCTAssertEqual(submission, .accepted)
        await generation.value
        XCTAssertEqual(provider.callCount, previousCalls)
        XCTAssertEqual(provider.acceptedTransferCount, 0)
        XCTAssertEqual(viewModel.generationRequestState.phase, .input)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.remoteTransferRequest)
        XCTAssertEqual(viewModel.sceneDescription, expectedDraft)
        XCTAssertEqual(viewModel.parsedScript, previousScript)
        XCTAssertEqual(viewModel.plannedScene, previousPlan)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, previousCommits)
    }

    @MainActor
    func testCancelledTransferCannotApproveTheNextGeneration() async throws {
        let provider = QuestionProvider()
        provider.requiresTransferConsent = true
        let viewModel = viewModel(provider: provider)
        let first = Task { await viewModel.generateScene() }
        let oldConsent = try await question(from: viewModel)
        await viewModel.cancelGeneration()
        await first.value
        XCTAssertNil(viewModel.remoteTransferRequest)
        XCTAssertEqual(provider.callCount, 0)
        let second = Task { await viewModel.generateScene() }
        let newConsent = try await question(from: viewModel)
        XCTAssertNotEqual(newConsent.id, oldConsent.id)
        let stale = await viewModel.submitClarificationAnswer(.choice("send"), for: oldConsent)
        XCTAssertEqual(stale, .rejected(.staleRequest))
        XCTAssertEqual(viewModel.remoteTransferRequest?.id, newConsent.id)
        XCTAssertEqual(provider.acceptedTransferCount, 0)
        _ = await viewModel.submitClarificationAnswer(.choice("decline"), for: newConsent)
        await second.value
        XCTAssertEqual(provider.callCount, 0)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
    }

    @MainActor
    func testEditingTextRetiresConsentWithoutSendingTheOldSnapshot() async throws {
        let provider = QuestionProvider()
        provider.requiresTransferConsent = true
        let viewModel = viewModel(provider: provider)
        let generation = Task { await viewModel.generateScene() }
        let oldConsent = try await question(from: viewModel)
        viewModel.sceneDescription = "A different scene stays on the device."
        await generation.value
        let stale = await viewModel.submitClarificationAnswer(.choice("send"), for: oldConsent)
        XCTAssertFalse(stale.isAccepted)
        XCTAssertNil(viewModel.remoteTransferRequest)
        XCTAssertEqual(provider.acceptedTransferCount, 0)
        XCTAssertEqual(provider.callCount, 0)
        XCTAssertEqual(viewModel.generationRequestState.phase, .input)
        XCTAssertEqual(viewModel.sceneDescription, "A different scene stays on the device.")
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
    }

    @MainActor
    func testChangingMarkersRetiresConsentWithoutSendingTheOldReferences() async throws {
        let provider = QuestionProvider()
        provider.requiresTransferConsent = true
        let viewModel = viewModel(provider: provider)
        let generation = Task { await viewModel.generateScene() }
        let oldConsent = try await question(from: viewModel)
        viewModel.markedObjects.append(MarkedObject(name: "New table", position: .init(x: 0, y: 0, z: -1)))
        await generation.value
        let stale = await viewModel.submitClarificationAnswer(.choice("send"), for: oldConsent)
        XCTAssertFalse(stale.isAccepted)
        XCTAssertNil(viewModel.remoteTransferRequest)
        XCTAssertEqual(provider.acceptedTransferCount, 0)
        XCTAssertEqual(provider.callCount, 0)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        XCTAssertEqual(viewModel.generationRequestState.phase, .input)
    }

    @MainActor
    func testProductionParserUsesConfiguredRemoteAndActualChoiceInV9Full() async throws {
        let modeKey = "scene_generator_v9_runtime_mode"
        let originalMode = UserDefaults.standard.object(forKey: modeKey)
        UserDefaults.standard.set("v9_full", forKey: modeKey)
        defer {
            if let originalMode { UserDefaults.standard.set(originalMode, forKey: modeKey) }
            else { UserDefaults.standard.removeObject(forKey: modeKey) }
        }
        let provider = QuestionProvider()
        let output = await parser(provider: provider).parseAsyncForGeneration(
            "A person stands still.",
            clarificationHandler: { _ in .choice("second") }
        )
        XCTAssertEqual(provider.callCount, 1)
        XCTAssertEqual(provider.answers.count, 1)
        XCTAssertEqual(provider.answers.first ?? nil, .choice("second"))
        XCTAssertEqual(output.result.script.actors.first?.name, "Mara")
        XCTAssertEqual(output.result.generationProvenance?.acceptedContributors, provider.receipts.map(SceneGenerationContributor.remoteService))
        XCTAssertEqual(output.result.generationProvenance?.chunks?.first?.providerRoute, .remoteService)
        XCTAssertTrue(output.runtimeTrace?.reasons.contains(where: { $0.contains("remote_plan_used") }) == true)
    }

    @MainActor
    func testProductionGenerationFreeTextResumesSameOwnerAndCommitsOnce() async throws {
        let provider = QuestionProvider()
        let viewModel = viewModel(provider: provider)
        let generation = Task { await viewModel.generateScene() }
        let payload = try await question(from: viewModel)
        let requestID = viewModel.generationRequestState.requestID
        let epoch = viewModel.generationRequestState.epoch
        XCTAssertEqual(payload.requestID, requestID)
        XCTAssertEqual(payload.epoch, epoch)
        XCTAssertNotEqual(payload.requestID, provider.questions.first?.requestID)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        XCTAssertTrue(provider.answers.isEmpty)
        let submission = await viewModel.submitClarificationAnswer(.freeText("The person at the window"), for: payload)
        XCTAssertEqual(submission, .accepted)
        await generation.value
        XCTAssertEqual(provider.answers.count, 1)
        XCTAssertEqual(provider.answers.first ?? nil, .freeText("The person at the window"))
        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 1)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 1)
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        XCTAssertEqual(viewModel.generationRequestState.requestID, requestID)
        XCTAssertEqual(viewModel.generationRequestState.epoch, epoch)
        XCTAssertNil(viewModel.clarificationRequest)
        let origin = try XCTUnwrap(viewModel.plannedScene?.provenance)
        XCTAssertEqual(origin.acceptedContributors, provider.receipts.map(SceneGenerationContributor.remoteService))
        let projectName = viewModel.sceneTitle
        XCTAssertEqual(DBService.shared.loadUnifiedSceneProject(named: projectName)?.0.plannedScene?.provenance, origin)
        _ = await viewModel.teardownAndWait()
        let reopened = SceneGeneratorViewModel(projectName: projectName, isNewProject: false)
        XCTAssertEqual(reopened.plannedScene?.provenance, origin)
        _ = await reopened.teardownAndWait()
    }

    @MainActor
    func testRemoteQuestionRejectsStaleAndUnknownAnswersBeforeResume() async throws {
        let provider = QuestionProvider()
        let viewModel = viewModel(provider: provider)
        let generation = Task { await viewModel.generateScene() }
        let payload = try await question(from: viewModel)
        let stale = await viewModel.submitClarificationAnswer(
            .choice("second"), requestID: UUID(), epoch: payload.epoch, clarificationID: payload.id
        )
        XCTAssertEqual(stale, .rejected(.staleRequest))
        let invalid = await viewModel.submitClarificationAnswer(.choice("unknown"), for: payload)
        XCTAssertEqual(invalid, .rejected(.invalidAnswer))
        XCTAssertEqual(viewModel.clarificationRequest?.id, payload.id)
        XCTAssertTrue(provider.answers.isEmpty)
        let accepted = await viewModel.submitClarificationAnswer(.choice("second"), for: payload)
        XCTAssertEqual(accepted, .accepted)
        await generation.value
        XCTAssertEqual(provider.answers.first ?? nil, .choice("second"))
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 1)
    }

    @MainActor
    func testCancelRemoteQuestionDoesNotCommitFallbackAndRetryRejectsOldSheet() async throws {
        let provider = QuestionProvider()
        let viewModel = viewModel(provider: provider)
        let originalDraft = viewModel.sceneDescription
        let firstGeneration = Task { await viewModel.generateScene() }
        let oldQuestion = try await question(from: viewModel)
        await viewModel.cancelGeneration()
        await firstGeneration.value
        XCTAssertEqual(viewModel.generationRequestState.phase, .input)
        XCTAssertEqual(viewModel.sceneDescription, originalDraft)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        XCTAssertNil(viewModel.clarificationRequest)
        XCTAssertEqual(provider.answers.count, 1)
        XCTAssertNil(provider.answers.first ?? nil)

        let secondGeneration = Task { await viewModel.generateScene() }
        let newQuestion = try await question(from: viewModel)
        XCTAssertNotEqual(newQuestion.requestID, oldQuestion.requestID)
        let stale = await viewModel.submitClarificationAnswer(.choice("first"), for: oldQuestion)
        XCTAssertEqual(stale, .rejected(.staleRequest))
        let accepted = await viewModel.submitClarificationAnswer(.choice("second"), for: newQuestion)
        XCTAssertEqual(accepted, .accepted)
        await secondGeneration.value
        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(provider.answers.last ?? nil, .choice("second"))
        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 2)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 1)
        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
    }

    @MainActor
    func testTerminalRemoteFailureIsPreservedAndCannotReplaceLastCompletedDocument() async throws {
        let provider = QuestionProvider()
        let parser = parser(provider: provider)
        _ = await parser.parseAsyncForGeneration(
            "A person stands still.", clarificationHandler: { _ in .choice("second") }
        )
        let previousDocument = try XCTUnwrap(parser.lastDocumentState)
        for failure in [SceneRemoteGenerationFailure.contentExpired, .serviceDisabled, .invalidServiceResponse] {
            provider.terminalFailure = failure
            let output = await parser.parseAsyncForGeneration("Another person speaks.")
            XCTAssertEqual(output.result.remoteFailure, failure)
            XCTAssertTrue(output.result.script.isEmpty, "A terminal decision must not commit a local replacement")
            XCTAssertEqual(parser.lastDocumentState, previousDocument)
        }
        XCTAssertEqual(provider.callCount, 4)
    }

    @MainActor
    func testExpiredResultPreservesDraftAndSavedSceneUntilExplicitNewGenerate() async throws {
        let provider = QuestionProvider()
        let store = CountingProjectStore(projectLeases: .shared)
        let viewModel = viewModel(provider: provider, projectStore: store)
        let generation = Task { await viewModel.generateScene() }
        let payload = try await question(from: viewModel)
        _ = await viewModel.submitClarificationAnswer(.choice("second"), for: payload)
        await generation.value
        let savedPlan = try XCTUnwrap(viewModel.plannedScene)
        let savedScript = try XCTUnwrap(viewModel.parsedScript)
        let savedProject = try XCTUnwrap(DBService.shared.loadUnifiedSceneProject(named: viewModel.sceneTitle)?.0)
        let newDraft = "Another person speaks."
        viewModel.sceneDescription = newDraft
        // Editing the draft intentionally saves metadata. Baseline after that
        // user action so the test isolates any write caused by failed generation.
        let beforeExpiry = try XCTUnwrap(store.loadUnifiedSceneProject(named: viewModel.sceneTitle)?.0)
        XCTAssertEqual(beforeExpiry.sceneDescription, newDraft)
        let saveAttemptsBeforeExpiry = store.saveAttempts
        provider.terminalFailure = .contentExpired

        await viewModel.generateScene()
        XCTAssertEqual(provider.callCount, 2)
        XCTAssertEqual(viewModel.generationRequestState.phase, .terminalFailure)
        XCTAssertEqual(viewModel.generationRequestState.failure, .remoteExpired)
        XCTAssertEqual(viewModel.sceneDescription, newDraft)
        XCTAssertEqual(viewModel.plannedScene, savedPlan)
        XCTAssertEqual(viewModel.parsedScript, savedScript)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 1)
        XCTAssertEqual(DBService.shared.loadUnifiedSceneProject(named: viewModel.sceneTitle)?.0.plannedScene, savedProject.plannedScene)
        XCTAssertEqual(store.loadUnifiedSceneProject(named: viewModel.sceneTitle)?.0.updatedAt, beforeExpiry.updatedAt)
        XCTAssertEqual(store.saveAttempts, saveAttemptsBeforeExpiry, "An expired generation must not attempt persistence")
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertTrue(viewModel.canSubmitScene)
        await Task.yield()
        XCTAssertEqual(provider.callCount, 2, "Presenting expiry must not create another remote job")

        await viewModel.generateScene() // The existing Generate action is the sole new-request owner.
        XCTAssertEqual(provider.callCount, 3)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 1)
        XCTAssertEqual(store.saveAttempts, saveAttemptsBeforeExpiry)
    }

    @MainActor
    func testLateRemoteFailureAfterCancellationCannotReopenErrorOrCommit() async throws {
        let provider = QuestionProvider()
        let viewModel = viewModel(provider: provider)
        let draft = viewModel.sceneDescription
        let generation = Task { await viewModel.generateScene() }
        _ = try await question(from: viewModel)
        provider.terminalFailure = .contentExpired
        await viewModel.cancelGeneration()
        await generation.value
        XCTAssertEqual(viewModel.generationRequestState.phase, .input)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertEqual(viewModel.sceneDescription, draft)
        XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        XCTAssertEqual(provider.callCount, 1)
    }

    @MainActor
    func testOtherGoneFailuresReachExistingErrorSurfaceWithoutParseEmpty() async throws {
        for (failure, expected) in [
            (SceneRemoteGenerationFailure.serviceDisabled, SceneGenerationFailureKind.remoteDisabled),
            (.invalidServiceResponse, .malformed)
        ] {
            let provider = QuestionProvider()
            provider.terminalFailure = failure
            let viewModel = viewModel(provider: provider)
            let draft = viewModel.sceneDescription
            await viewModel.generateScene()
            XCTAssertEqual(viewModel.generationRequestState.phase, .terminalFailure)
            XCTAssertEqual(viewModel.generationRequestState.failure, expected)
            XCTAssertNotNil(viewModel.errorMessage)
            XCTAssertEqual(viewModel.sceneDescription, draft)
            XCTAssertEqual(provider.callCount, 1)
            XCTAssertEqual(viewModel.testingGenerationCommitCount, 0)
        }
    }

    @MainActor
    func testCancelledParseCannotReplaceLastCompletedDocumentContext() async throws {
        let provider = QuestionProvider()
        let parser = parser(provider: provider)
        _ = await parser.parseAsyncForGeneration(
            "A person stands still.", clarificationHandler: { _ in .choice("second") }
        )
        let previousDocument = try XCTUnwrap(parser.lastDocumentState)
        let previousTrace = parser.lastRuntimeTrace
        let presented = expectation(description: "second parse awaits an answer")
        var continuation: CheckedContinuation<SceneClarificationAnswer?, Never>?
        let task = Task {
            await parser.parseAsyncForGeneration(
                "Another person speaks.",
                clarificationHandler: { _ in
                    await withCheckedContinuation { pending in
                        continuation = pending
                        presented.fulfill()
                    }
                }
            )
        }
        await fulfillment(of: [presented], timeout: 3)
        task.cancel()
        continuation?.resume(returning: .choice("first"))
        _ = await task.value
        XCTAssertEqual(parser.lastDocumentState, previousDocument)
        XCTAssertEqual(parser.lastRuntimeTrace, previousTrace)
    }
}
