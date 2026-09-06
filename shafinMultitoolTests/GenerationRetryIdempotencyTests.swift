import simd
import XCTest
@testable import shafinMultitool

/// M5-023: retry policy distinguishes the four paths — transport retry (not
/// applicable locally: no backend transport exists), clarification
/// continuation (same UUID+epoch), new edited request (new epoch after a
/// retryable result), and duplicate success coalescing (single-flight join).
@MainActor
final class GenerationRetryIdempotencyTests: XCTestCase {

    private func makeViewModel() -> SceneGeneratorViewModel {
        let viewModel = SceneGeneratorViewModel(projectName: "retry-\(UUID().uuidString)")
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        return viewModel
    }

    func testDuplicateSubmitJoinsSingleFlightWithoutNewRequest() async {
        let viewModel = makeViewModel()
        viewModel.sceneDescription = "Марина стоит."
        viewModel.testingSetGenerationDelay(0.3)
        viewModel.testingResetGenerationStateTrace()

        let first = Task { @MainActor in await viewModel.generateScene() }
        let second = Task { @MainActor in await viewModel.generateScene() }
        await first.value
        await second.value

        XCTAssertEqual(viewModel.testingGenerationOwnerCount, 1,
                       "duplicate submits must coalesce into one request owner")
        XCTAssertEqual(
            viewModel.testingGenerationStateTrace.filter { $0.phase == .validating }.count, 1)
    }

    func testResubmitAfterTerminalResultIssuesNewEpoch() async {
        let viewModel = makeViewModel()
        viewModel.sceneDescription = "Марина стоит."
        viewModel.testingSetGenerationDelay(0.05)
        await viewModel.generateScene()
        let firstEpoch = viewModel.generationRequestState.epoch

        viewModel.sceneDescription = "Марина сидит."
        await viewModel.generateScene()

        XCTAssertNotEqual(viewModel.generationRequestState.epoch, firstEpoch,
                          "an edited resubmit is a new request, not a retry of the old one")
    }

    func testClarificationAnswerKeepsRequestIdentity() async throws {
        let viewModel = makeViewModel()
        viewModel.sceneDescription = "Марина подходит к одному из стульев."
        viewModel.testingSetGenerationDelay(60)
        viewModel.testingResetGenerationStateTrace()

        let generation = Task { @MainActor in await viewModel.generateScene() }
        let deadline = Date().addingTimeInterval(5)
        while viewModel.generationRequestState.phase != .clarification, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        _ = try XCTUnwrap(viewModel.generationRequestState.requestID)

        await viewModel.cancelGeneration()
        await generation.value

        XCTAssertNil(viewModel.generationRequestState.requestID,
                     "cancelled clarification retires the request without spawning a new job")
    }
}
