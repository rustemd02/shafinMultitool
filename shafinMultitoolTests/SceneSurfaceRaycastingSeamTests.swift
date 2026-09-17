//
//  SceneSurfaceRaycastingSeamTests.swift
//  shafinMultitoolTests
//
//  M6-020: fake event tests over the surface raycast seam. Unit tests
//  drive hit/miss marker events through the injected provider; the
//  production adapter remains the ARView wrapper.
//

import XCTest
import simd
@testable import shafinMultitool

@MainActor
final class SceneSurfaceRaycastingSeamTests: XCTestCase {
    private final class FakeSurfaceRaycaster: SceneSurfaceRaycasting {
        var hits: [SceneSurfaceRaycastResult]
        var ray: (origin: SIMD3<Float>, direction: SIMD3<Float>)?
        var callCount = 0
        var rayCallCount = 0

        init(hits: [SceneSurfaceRaycastResult], ray: (origin: SIMD3<Float>, direction: SIMD3<Float>)? = nil) {
            self.hits = hits
            self.ray = ray
        }

        func raycastSurfaces(from point: CGPoint) -> [SceneSurfaceRaycastResult] {
            callCount += 1
            return hits
        }

        func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
            rayCallCount += 1
            return ray
        }
    }

    private func hit(at position: SIMD3<Float>) -> SceneSurfaceRaycastResult {
        var transform = matrix_identity_float4x4
        transform.columns.3 = SIMD4(position.x, position.y, position.z, 1)
        return SceneSurfaceRaycastResult(worldTransform: transform)
    }

    func testTapWithFakeHitOpensMarkerNaming() throws {
        let viewModel = SceneGeneratorViewModel(projectName: "seam-hit-\(UUID().uuidString.prefix(6))")
        let raycaster = FakeSurfaceRaycaster(hits: [hit(at: SIMD3(0.5, 0, -1.5))])
        viewModel.surfaceRaycaster = raycaster
        viewModel.isMarkingMode = true
        viewModel.handleTapForMarker(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(raycaster.callCount, 1)
        let position = try XCTUnwrap(viewModel.pendingMarkerPosition)
        XCTAssertEqual(position.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(position.z, -1.5, accuracy: 0.0001)
        XCTAssertTrue(viewModel.showMarkerNameInput)
    }

    func testTapWithMissAndNoFallbackSurfacesTypedRejection() {
        let viewModel = SceneGeneratorViewModel(projectName: "seam-miss-\(UUID().uuidString.prefix(6))")
        let raycaster = FakeSurfaceRaycaster(hits: [])
        viewModel.surfaceRaycaster = raycaster
        viewModel.isMarkingMode = true
        viewModel.handleTapForMarker(at: CGPoint(x: 100, y: 100))
        XCTAssertNil(viewModel.pendingMarkerPosition)
        XCTAssertFalse(viewModel.showMarkerNameInput)
    }

    func testMissWithLiveCameraTransformDoesNotInventMarkerPosition() {
        let origin = SIMD3<Float>(0.4, 1.7, 2)
        let rays: [(origin: SIMD3<Float>, direction: SIMD3<Float>)?] = [
            nil,
            (origin: origin, direction: SIMD3<Float>(0, 0, -1)),
            (origin: origin, direction: SIMD3<Float>(0, -1, -1))
        ]
        for ray in rays {
            let viewModel = SceneGeneratorViewModel(projectName: "seam-live-miss-\(UUID().uuidString.prefix(6))")
            var camera = matrix_identity_float4x4
            camera.columns.3 = SIMD4(origin.x, origin.y, origin.z, 1)
            viewModel.testingSetPlanningContext(cameraTransform: camera, planes: [])
            let raycaster = FakeSurfaceRaycaster(hits: [], ray: ray)
            viewModel.surfaceRaycaster = raycaster
            viewModel.isMarkingMode = true

            viewModel.handleTapForMarker(at: CGPoint(x: 100, y: 100))

            XCTAssertEqual(raycaster.callCount, 1)
            XCTAssertEqual(raycaster.rayCallCount, 0, "A marker miss must not enter the virtual-position fallback")
            XCTAssertNil(viewModel.pendingMarkerPosition)
            XCTAssertFalse(viewModel.showMarkerNameInput)
            XCTAssertTrue(viewModel.isMarkingMode, "The user can retry on an observed surface")
            XCTAssertEqual(viewModel.statusMessage, viewModel.localizedCopy(.generatorErrorMarkFailed))
            viewModel.createMarker(withName: "unsupported")
            XCTAssertTrue(viewModel.markedObjects.isEmpty)
        }
    }

    func testObservedPlaneHeightWithoutSurfaceHitDoesNotAuthorizeMarker() {
        let viewModel = SceneGeneratorViewModel(projectName: "seam-plane-miss-\(UUID().uuidString.prefix(6))")
        var camera = matrix_identity_float4x4
        camera.columns.3 = SIMD4<Float>(0.4, 1.7, 2, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: camera, planes: [.init(alignment: .horizontal, y: 0.6)]
        )
        let raycaster = FakeSurfaceRaycaster(
            hits: [], ray: (origin: SIMD3<Float>(0.4, 1.7, 2), direction: SIMD3<Float>(0, -1, -1))
        )
        viewModel.surfaceRaycaster = raycaster
        viewModel.isMarkingMode = true

        viewModel.handleTapForMarker(at: CGPoint(x: 90, y: 120))

        XCTAssertEqual(raycaster.callCount, 1)
        XCTAssertEqual(raycaster.rayCallCount, 0)
        XCTAssertNil(viewModel.pendingMarkerPosition,
                     "A plane height has no footprint proving that this tap hit an observed surface")
        XCTAssertFalse(viewModel.showMarkerNameInput)
        XCTAssertEqual(viewModel.statusMessage, viewModel.localizedCopy(.generatorErrorMarkFailed))
        viewModel.createMarker(withName: "unsupported-plane")
        XCTAssertTrue(viewModel.markedObjects.isEmpty)
    }

    func testMissOrNonfiniteHitClearsPreviousPendingMarkerAndNaming() throws {
        let viewModel = SceneGeneratorViewModel(projectName: "seam-invalid-hit-\(UUID().uuidString.prefix(6))")
        var camera = matrix_identity_float4x4
        camera.columns.3 = SIMD4<Float>(0, 1.7, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: camera, planes: [.init(alignment: .horizontal, y: 0)]
        )
        let validHit = hit(at: SIMD3<Float>(0.25, 0.6, -1.5))
        let raycaster = FakeSurfaceRaycaster(
            hits: [validHit], ray: (origin: SIMD3<Float>(0, 1.7, 0), direction: SIMD3<Float>(0, -1, -1))
        )
        viewModel.surfaceRaycaster = raycaster
        viewModel.isMarkingMode = true
        let rejectedResults: [[SceneSurfaceRaycastResult]] = [
            [],
            [hit(at: SIMD3<Float>(Float.nan, 0, -1))],
            [hit(at: SIMD3<Float>(0, Float.infinity, -1))],
            [hit(at: SIMD3<Float>(0, 0, -Float.infinity))]
        ]
        for rejected in rejectedResults {
            raycaster.hits = [validHit]
            viewModel.handleTapForMarker(at: CGPoint(x: 30, y: 40))
            _ = try XCTUnwrap(viewModel.pendingMarkerPosition)
            XCTAssertTrue(viewModel.showMarkerNameInput)

            raycaster.hits = rejected
            viewModel.handleTapForMarker(at: CGPoint(x: 130, y: 140))

            XCTAssertNil(viewModel.pendingMarkerPosition, "The rejected tap cannot leave an earlier position nameable")
            XCTAssertFalse(viewModel.showMarkerNameInput)
            XCTAssertEqual(viewModel.statusMessage, viewModel.localizedCopy(.generatorErrorMarkFailed))
            viewModel.createMarker(withName: "rejected")
            XCTAssertTrue(viewModel.markedObjects.isEmpty)
        }
        XCTAssertEqual(raycaster.rayCallCount, 0)
    }

    func testFiniteSurfaceHitPreservesXYZAndMarkerTransactionWithObservedPlane() throws {
        // These are provider-result contract fixtures. They do not simulate
        // ARKit plane discovery or qualify physical surface accuracy.
        for expected in [SIMD3<Float>(0.5, 0, -1.5), SIMD3<Float>(-0.4, 0.8, -2.75)] {
            let viewModel = SceneGeneratorViewModel(projectName: "seam-finite-hit-\(UUID().uuidString.prefix(6))")
            var camera = matrix_identity_float4x4
            camera.columns.3 = SIMD4<Float>(0.2, 1.7, 0.3, 1)
            viewModel.testingSetPlanningContext(
                cameraTransform: camera, planes: [.init(alignment: .horizontal, y: expected.y)]
            )
            let raycaster = FakeSurfaceRaycaster(hits: [hit(at: expected)])
            viewModel.surfaceRaycaster = raycaster
            viewModel.isMarkingMode = true

            viewModel.handleTapForMarker(at: CGPoint(x: 50, y: 60))

            let pending = try XCTUnwrap(viewModel.pendingMarkerPosition)
            XCTAssertEqual(pending.x, expected.x)
            XCTAssertEqual(pending.y, expected.y)
            XCTAssertEqual(pending.z, expected.z)
            XCTAssertTrue(viewModel.showMarkerNameInput)
            XCTAssertEqual(raycaster.callCount, 1)
            XCTAssertEqual(raycaster.rayCallCount, 0)
            viewModel.createMarker(withName: "surface")
            XCTAssertEqual(viewModel.markedObjects.count, 1)
            let marker = try XCTUnwrap(viewModel.markedObjects.first)
            XCTAssertEqual(marker.worldPosition.x, expected.x)
            XCTAssertEqual(marker.worldPosition.y, expected.y)
            XCTAssertEqual(marker.worldPosition.z, expected.z)
            XCTAssertTrue(marker.canonicalMarkedObjectID.hasPrefix("object_marked_"))
            XCTAssertNil(viewModel.pendingMarkerPosition)
            XCTAssertFalse(viewModel.showMarkerNameInput)
            XCTAssertFalse(viewModel.isMarkingMode)
        }
    }

    func testMarkingModeGateRejectsBeforeRaycast() {
        let viewModel = SceneGeneratorViewModel(projectName: "seam-gate-\(UUID().uuidString.prefix(6))")
        let raycaster = FakeSurfaceRaycaster(hits: [hit(at: SIMD3(0, 0, -1))])
        viewModel.surfaceRaycaster = raycaster
        viewModel.isMarkingMode = false
        viewModel.handleTapForMarker(at: CGPoint(x: 100, y: 100))
        XCTAssertEqual(raycaster.callCount, 0, "raycast must not run when marking mode is off")
        XCTAssertNil(viewModel.pendingMarkerPosition)
    }

    func testMarkerNamingTransactionCreatesStableIdentity() throws {
        let viewModel = SceneGeneratorViewModel(projectName: "seam-name-\(UUID().uuidString.prefix(6))")
        let raycaster = FakeSurfaceRaycaster(hits: [hit(at: SIMD3(0.25, 0, -1))])
        viewModel.surfaceRaycaster = raycaster
        viewModel.isMarkingMode = true
        viewModel.handleTapForMarker(at: CGPoint(x: 50, y: 50))
        viewModel.createMarker(withName: "стол")
        XCTAssertEqual(viewModel.markedObjects.count, 1)
        let marker = try XCTUnwrap(viewModel.markedObjects.first)
        XCTAssertTrue(marker.canonicalMarkedObjectID.hasPrefix("object_marked_"))
        // Naming closes the transaction: pending state cleared, mode off.
        XCTAssertNil(viewModel.pendingMarkerPosition)
        XCTAssertFalse(viewModel.showMarkerNameInput)
        XCTAssertFalse(viewModel.isMarkingMode)
        // Cancel path discards without residue.
        viewModel.isMarkingMode = true
        viewModel.handleTapForMarker(at: CGPoint(x: 50, y: 50))
        viewModel.cancelMarkerCreation()
        XCTAssertEqual(viewModel.markedObjects.count, 1)
        XCTAssertNil(viewModel.pendingMarkerPosition)
    }

    func testEmptyNameRejectedByTransaction() {
        let viewModel = SceneGeneratorViewModel(projectName: "seam-empty-\(UUID().uuidString.prefix(6))")
        let raycaster = FakeSurfaceRaycaster(hits: [hit(at: SIMD3(0, 0, -1))])
        viewModel.surfaceRaycaster = raycaster
        viewModel.isMarkingMode = true
        viewModel.handleTapForMarker(at: CGPoint(x: 10, y: 10))
        viewModel.createMarker(withName: "   ")
        XCTAssertTrue(viewModel.markedObjects.isEmpty, "blank name must not create a marker")
    }
}
