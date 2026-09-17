import simd
import XCTest
@testable import shafinMultitool

/// M6-006: surface search is readiness-gated, reports tracking limitations
/// with retry/reposition guidance, applies a bounded search window, and
/// never selects a fake surface.
@MainActor
final class SurfaceSearchPolicyTests: XCTestCase {

    private final class HitSurfaceRaycaster: SceneSurfaceRaycasting {
        var hit: SceneSurfaceRaycastResult
        private(set) var callCount = 0
        private(set) var rayCallCount = 0

        init(position: SIMD3<Float>) {
            var transform = matrix_identity_float4x4
            transform.columns.3 = SIMD4(position.x, position.y, position.z, 1)
            hit = SceneSurfaceRaycastResult(worldTransform: transform)
        }

        func raycastSurfaces(from point: CGPoint) -> [SceneSurfaceRaycastResult] {
            callCount += 1
            return [hit]
        }

        func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
            rayCallCount += 1
            return nil
        }
    }

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

    func testExpiredSearchWindowSurfacesTimeoutGuidanceWithoutSelectingSurface() throws {
        let viewModel = makeViewModel()
        let expected = SIMD3<Float>(0.25, 0.6, -1.5)
        let raycaster = HitSurfaceRaycaster(position: expected)
        viewModel.surfaceRaycaster = raycaster
        viewModel.testingSetPlanningContext(
            cameraTransform: matrix_identity_float4x4,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.testingMarkARSessionReady()
        viewModel.toggleMarkingMode()
        XCTAssertTrue(viewModel.isMarkingMode)

        // A real provider hit opens naming before the bounded window expires.
        viewModel.handleTapForMarker(at: CGPoint(x: 320, y: 240))
        let initial = try XCTUnwrap(viewModel.pendingMarkerPosition)
        XCTAssertEqual(initial.x, expected.x)
        XCTAssertEqual(initial.y, expected.y)
        XCTAssertEqual(initial.z, expected.z)
        XCTAssertTrue(viewModel.showMarkerNameInput)
        XCTAssertEqual(raycaster.callCount, 1)

        // Expire the actual handler deadline; the second query still returns a
        // finite hit, so timeout is the rejection reason rather than a miss.
        viewModel.testingSetSurfaceSearchDeadline(.distantPast)
        viewModel.handleTapForMarker(at: CGPoint(x: 300, y: 220))
        XCTAssertEqual(raycaster.callCount, 2, "Preserve query-before-deadline ordering")
        XCTAssertEqual(viewModel.statusMessage, viewModel.localizedCopy(.generatorErrorSurfaceTimeout))
        XCTAssertNil(viewModel.pendingMarkerPosition,
                     "Timeout must discard the previous pending marker")
        XCTAssertFalse(viewModel.showMarkerNameInput)
        XCTAssertTrue(viewModel.isMarkingMode, "The user can retry after the renewed search window")
        viewModel.createMarker(withName: "expired")
        XCTAssertTrue(viewModel.markedObjects.isEmpty)

        // The timeout renews the existing deadline, allowing the next actual
        // hit to start a fresh naming transaction with new, unmodified XYZ.
        let retryExpected = SIMD3<Float>(-0.4, 0.8, -2.75)
        var retryTransform = matrix_identity_float4x4
        retryTransform.columns.3 = SIMD4(retryExpected.x, retryExpected.y, retryExpected.z, 1)
        raycaster.hit = SceneSurfaceRaycastResult(worldTransform: retryTransform)
        viewModel.handleTapForMarker(at: CGPoint(x: 320, y: 240))
        let retry = try XCTUnwrap(viewModel.pendingMarkerPosition)
        XCTAssertEqual(retry.x, retryExpected.x)
        XCTAssertEqual(retry.y, retryExpected.y)
        XCTAssertEqual(retry.z, retryExpected.z)
        XCTAssertTrue(viewModel.showMarkerNameInput)
        XCTAssertEqual(raycaster.callCount, 3)
        XCTAssertEqual(raycaster.rayCallCount, 0)
        viewModel.createMarker(withName: "renewed")
        XCTAssertEqual(viewModel.markedObjects.count, 1)
        let marker = try XCTUnwrap(viewModel.markedObjects.first)
        XCTAssertEqual(marker.worldPosition.x, retryExpected.x)
        XCTAssertEqual(marker.worldPosition.y, retryExpected.y)
        XCTAssertEqual(marker.worldPosition.z, retryExpected.z)
        XCTAssertNil(viewModel.pendingMarkerPosition)
        XCTAssertFalse(viewModel.showMarkerNameInput)
        XCTAssertFalse(viewModel.isMarkingMode)
    }
}
