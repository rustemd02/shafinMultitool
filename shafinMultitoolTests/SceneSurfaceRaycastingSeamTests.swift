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

        init(hits: [SceneSurfaceRaycastResult], ray: (origin: SIMD3<Float>, direction: SIMD3<Float>)? = nil) {
            self.hits = hits
            self.ray = ray
        }

        func raycastSurfaces(from point: CGPoint) -> [SceneSurfaceRaycastResult] {
            callCount += 1
            return hits
        }

        func ray(through point: CGPoint) -> (origin: SIMD3<Float>, direction: SIMD3<Float>)? {
            ray
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
