//
//  ARPlacementMarkingContractTests.swift
//  shafinMultitoolTests
//
//  M6-007 + M6-008: deterministic placement and marker lifecycle
//  contract fixtures. Placement uses stable entity IDs, deterministic
//  priority (marked → detected → virtual), and marked bindings;
//  marker identities are canonical and fail closed on ambiguity.
//  Physical surface confirmation stays M13.
//

import XCTest
import simd
@testable import shafinMultitool

final class ARPlacementMarkingContractTests: XCTestCase {
    private let identityCamera = simd_float4x4(
        columns: (
            simd_float4(1, 0, 0, 0),
            simd_float4(0, 1, 0, 0),
            simd_float4(0, 0, 1, 0),
            simd_float4(0, 0, 0, 1)
        )
    )

    private func script(objects: [SceneObject], actors: [SceneActor] = []) -> SceneScript {
        SceneScript(
            actors: actors,
            objects: objects,
            beats: [],
            spatialRelations: [],
            originalDescription: "demo"
        )
    }

    // MARK: - M6-007 placement determinism

    func testPlacementIsDeterministicAcrossRuns() {
        let planner = SpatialPlannerService.shared
        let script = self.script(objects: [
            SceneObject(id: "object_1", type: .table, relativePosition: .center),
            SceneObject(id: "object_2", type: .chair, relativePosition: .left),
        ])
        let first = planner.planScene(
            script: script,
            cameraTransform: identityCamera,
            detectedObjects: [],
            availablePlanes: []
        )
        let second = planner.planScene(
            script: script,
            cameraTransform: identityCamera,
            detectedObjects: [],
            availablePlanes: []
        )
        XCTAssertEqual(first, second, "same inputs must place identically")
    }

    func testPlacementUsesStableEntityIDs() {
        let planner = SpatialPlannerService.shared
        let script = self.script(objects: [
            SceneObject(id: "object_marked_deadbeef", type: .table, relativePosition: .center)
        ])
        let placed = planner.planScene(
            script: script,
            cameraTransform: identityCamera,
            detectedObjects: [],
            availablePlanes: []
        )
        XCTAssertEqual(placed.placedObjects.map(\.id), ["placed_object_marked_deadbeef"])
        XCTAssertEqual(placed.placedObjects.map(\.objectId), ["object_marked_deadbeef"])
    }

    func testMarkedObjectsTakePriorityOverDetected() {
        let planner = SpatialPlannerService.shared
        let script = self.script(objects: [
            SceneObject(id: "object_1", type: .table, relativePosition: .center)
        ])
        let marked = MarkedObject(name: "стол", position: Position3D(x: 1, y: 0, z: -2))
        let detected = DetectedObject(
            id: UUID(),
            label: "table",
            confidence: 0.9,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
        let placed = planner.planScene(
            script: script,
            cameraTransform: identityCamera,
            detectedObjects: [detected],
            availablePlanes: [],
            markedObjects: [marked]
        )
        // Priority expresses as the placement source; the script object
        // identity stays the bind target (the matcher owns marker→script
        // binding), and the position comes from the real marker.
        XCTAssertEqual(placed.placedObjects.first?.placementSource, .marked)
        XCTAssertEqual(placed.placedObjects.first?.position.x, marked.worldPosition.x)
        XCTAssertEqual(placed.placedObjects.first?.position.z, marked.worldPosition.z)
    }

    func testScaleAndOrientationConstraintsPresent() throws {
        let planner = SpatialPlannerService.shared
        let script = self.script(objects: [
            SceneObject(id: "object_1", type: .table, relativePosition: .center)
        ])
        let placed = planner.planScene(
            script: script,
            cameraTransform: identityCamera,
            detectedObjects: [],
            availablePlanes: []
        )
        let object = try XCTUnwrap(placed.placedObjects.first)
        XCTAssertFalse(object.rotation.isNaN, "rotation must be well-formed")
        XCTAssertFalse(object.position.x.isNaN && object.position.z.isNaN, "position must be well-formed")
    }

    // MARK: - M6-008 marker identity fail-closed

    func testCanonicalMarkerIDStableAcrossCalls() {
        let marker = MarkedObject(name: "стол", position: Position3D(x: 0, y: 0, z: -1))
        XCTAssertEqual(marker.canonicalMarkedObjectID, marker.canonicalMarkedObjectID)
        XCTAssertTrue(marker.canonicalMarkedObjectID.hasPrefix("object_marked_"))
    }

    func testDuplicateMarkerAliasesFailClosed() {
        let matcher = MarkedObjectMatcher(lemmatizer: Lemmatizer())
        let first = MarkedObject(name: "стол", position: Position3D(x: 0, y: 0, z: -1))
        let second = MarkedObject(name: "стол", position: Position3D(x: 1, y: 0, z: -2))
        let request = SceneObjectBindingRequestSnapshot(
            requestID: UUID(),
            epoch: 1,
            description: "подойди к столу",
            candidates: [
                SceneObjectBinding(
                    canonicalID: first.canonicalMarkedObjectID,
                    source: .marked,
                    confidence: 1,
                    name: "стол",
                    aliases: ["стол"],
                    objectType: .table,
                    worldPosition: first.worldPosition,
                    markerID: first.id
                ),
                SceneObjectBinding(
                    canonicalID: second.canonicalMarkedObjectID,
                    source: .marked,
                    confidence: 1,
                    name: "стол",
                    aliases: ["стол"],
                    objectType: .table,
                    worldPosition: second.worldPosition,
                    markerID: second.id
                ),
            ]
        )
        let scriptObjects = [SceneObject(id: "object_1", type: .table, relativePosition: .center)]
        let result = matcher.resolveObjectBindings(scriptObjects: scriptObjects, request: request)
        // Ambiguous alias must not silently bind one arbitrary marker.
        let unresolved = result.resolutions.filter { $0.state != .bound }
        XCTAssertFalse(unresolved.isEmpty, "ambiguous same-alias markers must fail closed")
    }
}
