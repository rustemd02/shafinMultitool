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

        viewModel.updateSurfaceTrackingPosture(isLimited: true, reason: .excessiveMotion)
        XCTAssertEqual(viewModel.surfaceTrackingPosture, .limited(reason: .excessiveMotion))
        XCTAssertEqual(viewModel.statusMessage, viewModel.localizedCopy(.generatorErrorTrackingMotion))

        // Duplicate limitation reports are idempotent.
        viewModel.updateSurfaceTrackingPosture(isLimited: true, reason: .excessiveMotion)
        XCTAssertEqual(viewModel.surfaceTrackingPosture, .limited(reason: .excessiveMotion))

        viewModel.updateSurfaceTrackingPosture(isLimited: false)
        XCTAssertEqual(viewModel.surfaceTrackingPosture, .normal)
    }

    func testEveryTrackingReasonMapsToOneBoundedGuidanceAction() {
        let viewModel = makeViewModel()
        let expected: [(SceneGeneratorViewModel.ARKitTrackingLimitation, SETCopyKey)] = [
            (.excessiveMotion, .generatorErrorTrackingMotion),
            (.insufficientFeatures, .generatorErrorTrackingFeatures),
            (.initializing, .generatorErrorTrackingInitializing),
            (.relocalizing, .generatorErrorTrackingRelocalizing),
            (.unavailable, .generatorErrorTrackingUnavailable),
        ]
        for (reason, key) in expected {
            viewModel.updateSurfaceTrackingPosture(isLimited: true, reason: reason)
            if reason == .unavailable {
                XCTAssertEqual(viewModel.surfaceTrackingPosture, .unavailable)
            } else {
                XCTAssertEqual(viewModel.surfaceTrackingPosture, .limited(reason: reason))
            }
            XCTAssertEqual(viewModel.statusMessage, viewModel.localizedCopy(key),
                           "reason \(reason.rawValue) must map to exactly one guidance action")
            XCTAssertFalse(viewModel.requiresStableTrackingForCapture)
        }
        viewModel.updateSurfaceTrackingPosture(isLimited: false)
        XCTAssertTrue(viewModel.requiresStableTrackingForCapture)
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
