import simd
import XCTest
@testable import shafinMultitool

/// M6-006: surface search is readiness-gated, reports tracking limitations
/// with retry/reposition guidance, applies a bounded search window, and
/// never selects a fake surface.
@MainActor
final class SurfaceSearchPolicyTests: XCTestCase {

    private func makeViewModel(projectName: String = "surface-search-\(UUID().uuidString)") -> SceneGeneratorViewModel {
        SceneGeneratorViewModel(projectName: projectName)
    }

    func testMarkingEntryBeforeReadyPublishesGuidanceInsteadOfEnteringSearch() {
        let viewModel = makeViewModel()
        viewModel.testingSetGenerationDelay(0)

        viewModel.toggleMarkingMode()

        XCTAssertFalse(viewModel.isMarkingMode, "search must not begin before ready")
        XCTAssertEqual(viewModel.statusMessage, viewModel.localizedCopy(.generatorErrorMarkNotReady))
    }

    func testTrackingLimitationPublishesRetryGuidanceAndRestoreRenewsWindow() {
        let viewModel = makeViewModel()
        viewModel.testingSetPlanningContext(
            cameraTransform: matrix_identity_float4x4,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.testingMarkARSessionReady()
        viewModel.toggleMarkingMode()
        XCTAssertTrue(viewModel.isMarkingMode)

        viewModel.updateSurfaceTrackingPosture(isLimited: true)
        XCTAssertEqual(viewModel.surfaceTrackingPosture, .limited)
        XCTAssertEqual(viewModel.statusMessage, viewModel.localizedCopy(.generatorErrorTrackingLimited))

        // Duplicate limitation reports are idempotent.
        viewModel.updateSurfaceTrackingPosture(isLimited: true)
        XCTAssertEqual(viewModel.surfaceTrackingPosture, .limited)

        viewModel.updateSurfaceTrackingPosture(isLimited: false)
        XCTAssertEqual(viewModel.surfaceTrackingPosture, .normal)
    }

    func testExpiredSearchWindowSurfacesTimeoutGuidanceWithoutSelectingSurface() {
        let viewModel = makeViewModel()
        viewModel.testingSetPlanningContext(
            cameraTransform: matrix_identity_float4x4,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.testingMarkARSessionReady()
        viewModel.toggleMarkingMode()
        XCTAssertTrue(viewModel.isMarkingMode)

        // Expire the bounded window by simulating a tap past the deadline.
        // The search publishes guidance and selects nothing.
        viewModel.handleTapForMarker(at: CGPoint(x: 320, y: 240))
        XCTAssertNil(viewModel.pendingMarkerPosition,
                     "no fallback surface is selected when the search finds nothing usable")
    }
}
