import XCTest
@testable import shafinMultitool

/// M5-021 (local half): background checkpoints the request identity and the
/// editable draft through the persisted snapshot; foreground restores the
/// draft into the editable input state without creating a new job.
/// The backend poll/resume half stays blocked on M5-025 by tracker authority.
@MainActor
final class GenerationBackgroundRecoveryTests: XCTestCase {

    func testBackgroundTeardownCheckpointsDraftAndForegroundRestoresEditableInput() async {
        let projectName = "bg-recovery-\(UUID().uuidString)"
        let viewModel = SceneGeneratorViewModel(projectName: projectName)
        viewModel.sceneDescription = "Марина подходит к стулу."
        viewModel.testingResetGenerationStateTrace()

        // Persist the draft the way the background teardown path does.
        let persistResult = await viewModel.testingPersistProjectSnapshot()
        guard case .success = persistResult else {
            XCTFail("draft checkpoint must persist")
            return
        }

        // Background teardown cancels in-flight work but keeps the draft.
        _ = await viewModel.teardownAndWait()

        // Foreground: a fresh workspace opening the same persisted project
        // restores the draft into the editable input state with no new job.
        let reopened = SceneGeneratorViewModel(projectName: projectName, isNewProject: false)
        XCTAssertEqual(reopened.sceneDescription, "Марина подходит к стулу.")
        XCTAssertEqual(reopened.generationRequestState.phase, .input,
                       "foreground must expose recoverable input, not auto-start a job")
        XCTAssertNil(reopened.generationRequestState.requestID,
                     "no new job identity may be created automatically")
        _ = await reopened.teardownAndWait()
    }
}
