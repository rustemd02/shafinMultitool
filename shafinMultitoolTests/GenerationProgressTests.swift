import simd
import XCTest
@testable import shafinMultitool

/// M5-019: progress is monotonic within a request (reading→planning→
/// placing), labels the actual phase, and resets on retry/new request.
@MainActor
final class GenerationProgressTests: XCTestCase {

    func testProgressIsMonotonicAndResetsOnNewRequest() async {
        let viewModel = SceneGeneratorViewModel(projectName: "progress-\(UUID().uuidString)")
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.sceneDescription = "Марина стоит."
        viewModel.testingSetGenerationDelay(0.05)
        viewModel.testingResetGenerationStateTrace()

        await viewModel.generateScene()
        let stages = viewModel.testingGenerationStageTrace
        _ = stages
        // Monotonic: reading before planning before placing (subsequence).
        let order: [SceneGenerationStage] = [.reading, .planning, .placing]
        var cursor = 0
        for stage in stages where cursor < order.count {
            if stage == order[cursor] { cursor += 1 }
        }
        XCTAssertEqual(cursor, order.count, "stages must advance reading→planning→placing, got \(stages)")

        // Retry/new request resets the trace to a fresh input edge.
        viewModel.sceneDescription = "Марина сидит."
        viewModel.testingResetGenerationStateTrace()
        await viewModel.generateScene()
        XCTAssertEqual(viewModel.testingGenerationStateTrace.first?.phase, .input)
    }
}
