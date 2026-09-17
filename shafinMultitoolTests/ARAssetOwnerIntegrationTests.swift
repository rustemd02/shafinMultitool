import XCTest
import ARKit
import CryptoKit
import RealityKit
import UIKit
@testable import shafinMultitool

/// Exercises the bundled resources and the existing scene owners. ARView uses
/// nonAR mode with a test render camera; no sensor camera, tracking, raycast,
/// or ARWorldMap success is asserted.
@MainActor
final class ARAssetOwnerIntegrationTests: XCTestCase {
    private var tintDiagnostics: [[String: Any]] = []

    func testBundledAssetsMatchSelectedProceduralBytesAndNamedLoad() throws {
        let expected: [(String, String, SIMD3<Float>)] = [
            ("Circle", "4ecd4d22e7c8f3b6d2131306d8c179fc238e062b566d127ea1a18892f5c24453", [0.250337392, 0.002, 0.250337392]),
            ("Person", "50ba6e1578fc8e5f82babefb749b07ae1f8bfe70d11b0e7954c59a7ff6d66277", [0.584250033, 1.037034988, 0.188504994])
        ]
        for (name, hash, extents) in expected {
            let url = try XCTUnwrap(Bundle.main.url(forResource: name, withExtension: "usdz"))
            let actualHash = SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(actualHash, hash, "The host app must bundle the selected resource, not a previous asset")
            let model = try ModelEntity.loadModel(named: name)
            _ = try XCTUnwrap(model.model, "Named loading must produce real geometry")
            assertVector(model.visualBounds(relativeTo: model).extents, extents)
        }
    }

    func testSavedSceneReopensThroughProductionActorCreationWithIndependentTintedClones() async throws {
        let name = "ar-asset-owner-\(UUID().uuidString)"
        let store = DBService.shared
        addTeardownBlock { @MainActor in store.deleteUnifiedSceneProject(named: name) { _ in } }
        let actors = [makeActor(id: "one", position: [-0.6, 0, -1.2], rotation: 0),
                      makeActor(id: "two", position: [0.6, 0, -1.4], rotation: .pi / 2)]
        let planned = PlannedScene(placedActors: actors, placedObjects: [])
        let script = SceneScript(
            actors: actors.map { SceneActor(id: $0.actorId, type: .human, name: $0.name) },
            objects: [],
            beats: [SceneBeat(id: "hold", actions: actors.map {
                SceneAction(id: "stand_\($0.id)", actorId: $0.actorId, type: .stand)
            })],
            spatialRelations: [], originalDescription: "Два актёра стоят на своих отметках."
        )
        let project = UnifiedSceneProject(name: name, parsedScript: script, plannedScene: planned)
        try store.saveUnifiedSceneProject(project, worldMap: nil)

        let first = SceneGeneratorViewModel(projectName: name, isNewProject: false, projectStore: store)
        // Reuse the existing seam solely for the unavailable map capture. All
        // asset creation, persistence and reopening below use production code.
        first.testingWorldMapCaptureOverride = { .success(nil) }
        addTeardownBlock { @MainActor in _ = await first.teardownAndWait() }
        let view = ARView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), cameraMode: .nonAR, automaticallyConfigureSession: false)
        first.attachARView(view)
        let entities = try await waitForActors(actors, in: view)
        for (index, actor) in actors.enumerated() {
            let entity = try XCTUnwrap(entities[actor.id])
            try assertProductionActor(entity, actor: actor, index: index)
        }
        let beforeRender = try await captureOwnerRender(
            view, entities: entities, name: "ar-owner-saved-two-actors",
            scope: "production saved-scene owner; nonAR rendering only",
            cameraPosition: [2.8, 2.2, 3.0], cameraTarget: [0, 0.8, -1.3])
        let one = try XCTUnwrap(entities[actors[0].id])
        let two = try XCTUnwrap(entities[actors[1].id])
        XCTAssertFalse(one === two)
        let secondScale = two.scale
        let secondTint = try tint(of: two)
        one.scale *= 1.25
        one.model?.materials = [SimpleMaterial(color: .red, roughness: 0.3, isMetallic: false)]
        assertVector(two.scale, secondScale)
        try assertTint(of: two, equals: secondTint, context: "independent clone after other actor mutation")

        let save = await first.testingPersistProjectSnapshot()
        if case .failure(let error) = save { XCTFail("Production snapshot failed: \(error)") }
        let firstTeardown = await first.teardownAndWait()
        XCTAssertEqual(firstTeardown, .released)
        let reopened = SceneGeneratorViewModel(projectName: name, isNewProject: false, projectStore: store)
        reopened.testingWorldMapCaptureOverride = { .success(nil) }
        addTeardownBlock { @MainActor in _ = await reopened.teardownAndWait() }
        XCTAssertEqual(reopened.projectID, project.id)
        XCTAssertEqual(reopened.plannedScene, planned)
        let reopenedView = ARView(frame: view.frame, cameraMode: .nonAR, automaticallyConfigureSession: false)
        reopened.attachARView(reopenedView)
        let restored = try await waitForActors(actors, in: reopenedView)
        for (index, actor) in actors.enumerated() {
            try assertProductionActor(try XCTUnwrap(restored[actor.id]), actor: actor, index: index)
        }
        let reopenedRender = try await captureOwnerRender(
            reopenedView, entities: restored, name: "ar-owner-reopened-two-actors",
            scope: "production reopened-scene owner; nonAR rendering only",
            cameraPosition: [2.8, 2.2, 3.0], cameraTarget: [0, 0.8, -1.3])
        try attachRenderMetadata([beforeRender, reopenedRender], name: "ar-owner-saved-and-reopened-metadata")
        XCTAssertNil(store.loadUnifiedSceneProject(named: name)?.1, "The test did not manufacture an ARWorldMap")
        let reopenedTeardown = await reopened.teardownAndWait()
        XCTAssertEqual(reopenedTeardown, .released)
    }

    func testLegacyNamedAnchorsRebuildAssetsUsingPersistedActorMetadata() async throws {
        let name = "ar-assets-legacy-\(UUID().uuidString)"
        let store = DBService.shared
        defer { store.deleteMap(with: name) { _ in } }
        var personTransform = matrix_identity_float4x4
        personTransform.columns.3 = [-0.4, 0, -1.5, 1]
        var pointTransform = matrix_identity_float4x4
        pointTransform.columns.3 = [0.8, 0, -2.1, 1]
        let person = ARAnchor(name: "Person", transform: personTransform)
        let point = ARAnchor(name: "Circle", transform: pointTransform)
        var actor = ActorData(id: 41, name: "Сохранённый актёр", red: 0.2, green: 0.5, blue: 0.8, alpha: 1)
        actor.anchorIDs = [person.identifier, point.identifier]
        try store.saveARWorldMap(map: nil, sceneData: SceneData(name: name, actors: [actor], script: ""))
        let metadata = try XCTUnwrap(store.loadSceneData(sceneName: name))
        XCTAssertEqual(metadata.actors?.first?.anchorIDs, actor.anchorIDs)
        let restoredPerson = try archiveRoundTrip(person)
        let restoredPoint = try archiveRoundTrip(point)
        let interactor = CameraScreenInteractor()
        interactor.sceneData = metadata
        let view = ARView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        defer { withExtendedLifetime((interactor, view)) {} }
        // These are the same owner methods used by retrieveActorModels after
        // ARKit returns anchors. Capturing/relocalizing a real map is external.
        let personEntity = try XCTUnwrap(interactor.placeActor(named: try XCTUnwrap(restoredPerson.name), for: restoredPerson, arView: view))
        interactor.setColorToModel(entity: personEntity, anchor: restoredPerson)
        let pointEntity = try XCTUnwrap(interactor.addPoint(named: try XCTUnwrap(restoredPoint.name), for: restoredPoint, arView: view))
        interactor.setColorToModel(entity: pointEntity, anchor: restoredPoint)
        XCTAssertEqual(view.scene.anchors.count, 2)
        XCTAssertTrue(personEntity.children.contains { $0.name == actor.name })
        XCTAssertEqual(try XCTUnwrap(personEntity.model).mesh.bounds.extents.y, 1.037034988, accuracy: 0.00001)
        XCTAssertEqual(try XCTUnwrap(pointEntity.model).mesh.bounds.extents.y, 0.002, accuracy: 0.000001)
        assertVector(pointEntity.scale, [0.6, 0.6, 0.6])
        XCTAssertNotNil(personEntity.components[CollisionComponent.self])
        XCTAssertNotNil(pointEntity.components[CollisionComponent.self])
        try assertTint(of: personEntity, equals: actor.color, context: "legacy Person tint")
        try assertTint(of: pointEntity, equals: actor.color, context: "legacy Circle tint")
        XCTAssertEqual(restoredPerson.identifier, actor.anchorIDs[0])
        XCTAssertEqual(restoredPoint.identifier, actor.anchorIDs[1])

        // ARAnchor activation needs tracking. These are explicitly render-only
        // clones of the already asserted production outputs, at archived poses.
        // Match the initial drawable geometry of the passing saved-scene capture.
        // The zero-size source view above still exercises the legacy owner.
        let renderView = ARView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), cameraMode: .nonAR, automaticallyConfigureSession: false)
        let personClone = personEntity.clone(recursive: true)
        let pointClone = pointEntity.clone(recursive: true)
        var originalWorldAnchors: [AnchorEntity] = []
        for (clone, archivedAnchor) in [(personClone, restoredPerson), (pointClone, restoredPoint)] {
            let world = AnchorEntity(world: archivedAnchor.transform)
            world.addChild(clone)
            renderView.scene.addAnchor(world)
            originalWorldAnchors.append(world)
        }
        do {
            let legacyRender = try await captureOwnerRender(
                renderView, entities: ["legacy-person": personClone, "legacy-circle": pointClone],
                name: "ar-legacy-world-clones-render-only",
                scope: "render-only world clones from legacy owners; no ARAnchor activation or map restoration",
                cameraPosition: [1.8, 2.6, 1.2], cameraTarget: [0.2, 0.45, -1.8])
            try attachRenderMetadata([legacyRender], name: "ar-legacy-world-clones-render-only-metadata")
        } catch {
            let originalFailure = error
            // A -> B -> A diagnostic. The first failure remains recorded and is
            // rethrown below. Keep the renderer, anchors, materials and labels.
            do {
                var swaps: [(id: String, original: ModelEntity, fresh: ModelEntity,
                             anchor: AnchorEntity, children: [Entity])] = []
                var sharedMeshReferences: [String: Bool] = [:]
                for (index, original) in [personClone, pointClone].enumerated() {
                    let fresh = try ModelEntity.loadModel(named: index == 0 ? "Person" : "Circle")
                    var freshModel = try XCTUnwrap(fresh.model)
                    let originalModel = try XCTUnwrap(original.model)
                    let id = index == 0 ? "legacy-person" : "legacy-circle"
                    sharedMeshReferences[id] = freshModel.mesh === originalModel.mesh
                    // Copy the state authored by createModel/addPoint explicitly.
                    // Reassigning another entity's whole ComponentSet traps in
                    // RealityFoundation on this runtime (retained native19 crash).
                    // Gesture bindings and internal entity state are not copied;
                    // this diagnostic cannot isolate those from clone identity.
                    fresh.transform = original.transform
                    fresh.collision = original.collision
                    fresh.isEnabled = original.isEnabled
                    freshModel.materials = originalModel.materials
                    fresh.model = freshModel
                    fresh.name = original.name
                    assertVector(freshModel.mesh.bounds.extents, originalModel.mesh.bounds.extents)
                    swaps.append((id, original, fresh, originalWorldAnchors[index], Array(original.children)))
                }
                @MainActor func restoreOriginals() {
                    for swap in swaps {
                        for child in swap.children { swap.original.addChild(child) }
                        swap.fresh.removeFromParent()
                        swap.anchor.addChild(swap.original)
                    }
                }
                defer { restoreOriginals() }
                for swap in swaps {
                    swap.original.removeFromParent()
                    for child in swap.children { swap.fresh.addChild(child) }
                    swap.anchor.addChild(swap.fresh)
                }
                do {
                    var control = try await captureOwnerRender(
                        renderView, entities: Dictionary(uniqueKeysWithValues: swaps.map { ($0.id, $0.fresh) }),
                        name: "ar-legacy-B-fresh-roots-same-context",
                        scope: "B diagnostic fresh roots and meshes; same world anchors, transform, collision, enabled state, material values and original label entities; gesture/internal state not matched; A failure remains",
                        cameraPosition: [1.8, 2.6, 1.2], cameraTarget: [0.2, 0.45, -1.8],
                        diagnosticContext: ["phase": "B", "fresh_mesh_same_reference_as_A": sharedMeshReferences])
                    control["fresh_mesh_same_reference_as_A"] = sharedMeshReferences
                    try attachRenderMetadata([control], name: "ar-legacy-B-fresh-roots-metadata")
                } catch {
                    print("[AR_ASSET_ABA_B_FAILURE] \(error); shared_mesh_references=\(sharedMeshReferences)")
                }
                restoreOriginals()
                do {
                    let restored = try await captureOwnerRender(
                        renderView, entities: Dictionary(uniqueKeysWithValues: swaps.map { ($0.id, $0.original) }),
                        name: "ar-legacy-A-original-roots-restored",
                        scope: "A diagnostic original clone instances restored after B; same anchors and label entities; original failure remains",
                        cameraPosition: [1.8, 2.6, 1.2], cameraTarget: [0.2, 0.45, -1.8])
                    try attachRenderMetadata([restored], name: "ar-legacy-A-original-roots-restored-metadata")
                } catch {
                    print("[AR_ASSET_ABA_RESTORED_A_FAILURE] \(error)")
                }
            } catch {
                print("[AR_ASSET_ABA_SETUP_FAILURE] \(error)")
            }
            throw originalFailure
        }
    }

    private func archiveRoundTrip(_ anchor: ARAnchor) throws -> ARAnchor {
        let data = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
        let restored = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: ARAnchor.self, from: data))
        XCTAssertEqual(restored.name, anchor.name)
        XCTAssertEqual(restored.identifier, anchor.identifier)
        for index in 0..<4 { XCTAssertEqual(restored.transform[index], anchor.transform[index]) }
        return restored
    }

    private func makeActor(id: String, position: SIMD3<Float>, rotation: Float) -> PlannedScene.PlacedActor {
        let point = Position3D(position)
        return PlannedScene.PlacedActor(id: id, actorId: "actor_\(id)", type: .human, name: id,
            initialPosition: point, initialRotation: rotation, path: [point], pathDurations: [],
            pathPoses: [.standing], pathCameras: [nil], pathAnnotations: [nil], pathBeatIDs: [nil])
    }

    private func waitForActors(_ actors: [PlannedScene.PlacedActor], in view: ARView) async throws -> [String: ModelEntity] {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        repeat {
            var found: [String: ModelEntity] = [:]
            for actor in actors {
                let name = "storyboard_actor|\(actor.id)|\(actor.actorId)"
                for anchor in view.scene.anchors {
                    if let entity = anchor.findEntity(named: name) as? ModelEntity { found[actor.id] = entity }
                }
            }
            if found.count == actors.count { return found }
            try await Task.sleep(for: .milliseconds(10))
        } while ContinuousClock.now < deadline
        XCTFail("Production attachment did not create the persisted actors")
        throw NSError(domain: "ARAssetOwnerIntegrationTests", code: 1)
    }

    private func assertProductionActor(_ entity: ModelEntity, actor: PlannedScene.PlacedActor, index: Int) throws {
        let model = try XCTUnwrap(entity.model)
        // The fallback box has actor.size.y here; the bundled mesh retains its
        // source height before the production uniform scale is applied.
        XCTAssertEqual(model.mesh.bounds.extents.y, 1.037034988, accuracy: 0.00001)
        XCTAssertEqual(model.mesh.bounds.extents.y * entity.scale.y, actor.size.y, accuracy: 0.00001)
        assertVector(entity.scale, SIMD3<Float>(repeating: entity.scale.y))
        assertVector(entity.position, actor.initialPosition.simdVector)
        let expectedRotation = simd_quatf(angle: actor.initialRotation, axis: [0,1,0])
        assertVector(entity.orientation.act([0,0,1]), expectedRotation.act([0,0,1]))
        XCTAssertNotNil(entity.components[CollisionComponent.self])
        try assertTint(of: entity,
                       equals: SceneGeneratorViewModel.actorRenderStyle(for: actor, at: index).uiColor,
                       context: "production actor \(actor.id)")
        XCTAssertFalse(entity.children.isEmpty, "Production actor creation must attach its label")
    }


    /// UIKit equality includes representation details. Compare physical channel
    /// values only after both colors are explicitly converted into the same sRGB.
    /// 1e-5 allows Float/component conversion noise, far below one 8-bit step.
    private func assertTint(of entity: ModelEntity, equals expected: UIColor, context: String,
                            file: StaticString = #filePath, line: UInt = #line) throws {
        let actual = try tint(of: entity)
        let actualRGBA = try sRGBComponents(actual)
        let expectedRGBA = try sRGBComponents(expected)
        let deltas = zip(actualRGBA, expectedRGBA).map { abs($0 - $1) }
        let diagnostic: [String: Any] = [
            "context": context, "entity": entity.name,
            "actual_color_space": String(describing: actual.cgColor.colorSpace?.name),
            "expected_color_space": String(describing: expected.cgColor.colorSpace?.name),
            "actual_original_components": actual.cgColor.components?.map(Double.init) ?? [],
            "expected_original_components": expected.cgColor.components?.map(Double.init) ?? [],
            "comparison_space": "sRGB", "resolved_style": "light",
            "actual_rgba": actualRGBA, "expected_rgba": expectedRGBA,
            "absolute_deltas": deltas, "absolute_tolerance": 0.00001
        ]
        tintDiagnostics.append(diagnostic)
        let data = try JSONSerialization.data(withJSONObject: diagnostic, options: [.sortedKeys])
        print("[AR_ASSET_TINT] \(String(decoding: data, as: UTF8.self))")
        for component in 0..<4 {
            XCTAssertEqual(actualRGBA[component], expectedRGBA[component], accuracy: 0.00001,
                           "\(context), sRGB component \(component); actual=\(actualRGBA), expected=\(expectedRGBA)",
                           file: file, line: line)
        }
    }

    private func sRGBComponents(_ color: UIColor) throws -> [Double] {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let resolved = color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let converted = try XCTUnwrap(resolved.cgColor.converted(to: space, intent: .relativeColorimetric, options: nil))
        let components = try XCTUnwrap(converted.components).map(Double.init)
        guard components.count == 4, components.allSatisfy(\.isFinite) else {
            throw captureFailure("Invalid sRGB components: \(components)")
        }
        return components
    }

    @MainActor
    private final class CaptureState {
        var active = true
        var sceneUpdates = 0
        var snapshotFinished = false
        var image: UIImage?
        var snapshotFinishedAt: TimeInterval?
    }

    private func captureOwnerRender(_ view: ARView, entities: [String: ModelEntity], name: String,
                                    scope: String, cameraPosition: SIMD3<Float>,
                                    cameraTarget: SIMD3<Float>, diagnosticContext: [String: Any] = [:]) async throws -> [String: Any] {
        let captureStartedAt = ProcessInfo.processInfo.systemUptime
        guard view.superview == nil, !entities.isEmpty else {
            throw captureFailure("Capture requires an unmounted test-owned view and nonempty entities")
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        let previousKeyWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        controller.view = UIView(frame: scene.coordinateSpace.bounds)
        window.rootViewController = controller
        window.windowLevel = .normal + 1
        let oldBounds = view.bounds
        let oldCenter = view.center
        let oldTransform = view.transform
        let oldBackground = view.environment.background
        let oldRenderOptions = view.renderOptions
        let renderAid = AnchorEntity(world: .zero)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 50
        camera.look(at: cameraTarget, from: cameraPosition, relativeTo: nil)
        renderAid.addChild(camera)
        let light = DirectionalLight()
        light.light.intensity = 2500
        light.look(at: cameraTarget, from: [3, 5, 3], relativeTo: nil)
        renderAid.addChild(light)
        view.scene.addAnchor(renderAid)
        view.environment.background = .color(UIColor(white: 0.12, alpha: 1))
        // Match the real ARSceneContainer render policy. Both recorded legacy
        // failures remain open; these options did not resolve the blank capture.
        view.renderOptions = [.disableMotionBlur, .disableDepthOfField, .disableCameraGrain,
                              .disablePersonOcclusion, .disableGroundingShadows, .disableHDR]
        let state = CaptureState()
        let subscription = view.scene.subscribe(to: SceneEvents.Update.self) { _ in
            // The SDK callback has no actor annotation. Do not move its event
            // across executors; signal only the MainActor-owned lifetime gate.
            Task { @MainActor in
                guard state.active else { return }
                state.sceneUpdates += 1
            }
        }
        defer {
            state.active = false
            subscription.cancel()
            view.scene.removeAnchor(renderAid)
            view.removeFromSuperview()
            view.transform = .identity
            view.bounds = oldBounds
            view.center = oldCenter
            view.transform = oldTransform
            view.environment.background = oldBackground
            view.renderOptions = oldRenderOptions
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKey()
        }
        // Fixed 4:3 render bounds, scaled to fit the current simulator window.
        // This does not force an orientation or alter the app's real root view.
        view.transform = .identity
        view.bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        controller.view.addSubview(view)
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        let scale = min(controller.view.bounds.width / 800, controller.view.bounds.height / 600)
        guard scale.isFinite, scale > 0 else { throw captureFailure("No usable window geometry") }
        view.transform = CGAffineTransform(scaleX: scale, y: scale)
        view.center = CGPoint(x: controller.view.bounds.midX, y: controller.view.bounds.midY)
        view.layoutIfNeeded()
        let sceneDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while state.sceneUpdates < 3, ContinuousClock.now < sceneDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard state.sceneUpdates >= 3 else { throw captureFailure("RealityKit produced no scene updates for \(name)") }

        var entityRecords: [[String: Any]] = []
        let actualCameraTransform = view.cameraTransform
        let actualCameraInverse = simd_inverse(actualCameraTransform.matrix)
        for id in entities.keys.sorted() {
            let entity = try XCTUnwrap(entities[id])
            let model = try XCTUnwrap(entity.model)
            let center = entity.convert(position: model.mesh.bounds.center, to: nil)
            let projected = try XCTUnwrap(view.project(center), "Render camera cannot project \(id)")
            guard entity.isActive, view.bounds.insetBy(dx: 8, dy: 8).contains(projected) else {
                throw captureFailure("Entity \(id) is inactive or outside the render frame: \(projected)")
            }
            var projectedCorners: [[Double]] = []
            var cameraDepths: [Double] = []
            for x in [model.mesh.bounds.min.x, model.mesh.bounds.max.x] {
                for y in [model.mesh.bounds.min.y, model.mesh.bounds.max.y] {
                    for z in [model.mesh.bounds.min.z, model.mesh.bounds.max.z] {
                        let world = entity.convert(position: [x, y, z], to: nil)
                        let cameraPoint = actualCameraInverse * SIMD4<Float>(world, 1)
                        cameraDepths.append(Double(-cameraPoint.z))
                        let corner = try XCTUnwrap(view.project(world), "Cannot project \(id) mesh corner")
                        guard view.bounds.insetBy(dx: 8, dy: 8).contains(corner) else {
                            throw captureFailure("Entity \(id) mesh is clipped by the render frame")
                        }
                        projectedCorners.append([Double(corner.x), Double(corner.y)])
                    }
                }
            }
            entityRecords.append([
                "id": id, "name": entity.name, "mesh_extents": vector(model.mesh.bounds.extents),
                "entity_id": String(describing: entity.id),
                "parent_entity_id": entity.parent.map { String(describing: $0.id) } ?? "none",
                "local_position": vector(entity.position), "world_position": vector(entity.position(relativeTo: nil)),
                "scale": vector(entity.scale), "rgba_srgb": try sRGBComponents(tint(of: entity)),
                "projected_center": [Double(projected.x), Double(projected.y)],
                "projected_mesh_corners": projectedCorners,
                "camera_forward_depths": cameraDepths,
                "is_active": entity.isActive,
                "material_bindings": materialBindings(of: entity),
                "world_transform_columns": matrixColumns(entity.transformMatrix(relativeTo: nil))
            ])
        }
        let snapshotRequestedAt = ProcessInfo.processInfo.systemUptime
        let snapshotRequestedUTC = Date().timeIntervalSince1970
        view.snapshot(saveToHDR: false) { image in
            Task { @MainActor in
                guard state.active, !state.snapshotFinished else { return }
                state.image = image
                state.snapshotFinishedAt = ProcessInfo.processInfo.systemUptime
                state.snapshotFinished = true
            }
        }
        let snapshotDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while !state.snapshotFinished, ContinuousClock.now < snapshotDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        guard state.snapshotFinished else { throw captureFailure("RealityKit snapshot timed out for \(name)") }
        let image = try XCTUnwrap(state.image, "RealityKit snapshot returned nil for \(name)")
        let cgImage = try XCTUnwrap(image.cgImage)
        guard cgImage.width >= 160, cgImage.height >= 120 else { throw captureFailure("Snapshot dimensions are too small") }
        let contentFraction = try nonBackgroundFraction(cgImage)
        let png = try XCTUnwrap(image.pngData())
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = name + ".png"
        attachment.lifetime = .keepAlways
        add(attachment)
        let receipt: [String: Any] = [
            "name": name, "scope": scope, "renderer": "RealityKit ARView.nonAR",
            "diagnostic_context": diagnosticContext,
            "physical_ar_verified": false, "human_appearance_approved": false,
            "camera_position": vector(cameraPosition), "camera_target": vector(cameraTarget),
            "actual_camera_transform_columns": matrixColumns(actualCameraTransform.matrix),
            "perspective_camera_transform_columns": matrixColumns(camera.transformMatrix(relativeTo: nil)),
            "initial_view_bounds": [Double(oldBounds.width), Double(oldBounds.height)],
            "camera_fov_degrees": 50, "light_intensity": 2500, "light_position": [3, 5, 3],
            "render_options_raw_value": view.renderOptions.rawValue,
            "render_options": ["disableMotionBlur", "disableDepthOfField", "disableCameraGrain",
                               "disablePersonOcclusion", "disableGroundingShadows", "disableHDR"],
            "render_policy_owner": "ARSceneContainer.makeUIView",
            "render_bounds": [800, 600], "window_scale": Double(scale),
            "scene_updates": state.sceneUpdates,
            "snapshot_requested_utc_seconds": snapshotRequestedUTC,
            "snapshot_requested_after_capture_start_seconds": snapshotRequestedAt - captureStartedAt,
            "snapshot_callback_after_capture_start_seconds": (state.snapshotFinishedAt ?? snapshotRequestedAt) - captureStartedAt,
            "png_width": cgImage.width, "png_height": cgImage.height,
            "png_sha256": SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined(),
            "non_background_fraction": contentFraction, "entities": entityRecords
        ]
        guard contentFraction >= 0.002, contentFraction < 0.9 else {
            // Preserve the real failed image and parameters for diagnosis.
            try attachRenderMetadata([receipt], name: name + "-failed-metadata")
            let originalFailure = captureFailure("Snapshot is blank or lacks its expected uniform background: fraction=\(contentFraction)")
            if name == "ar-legacy-world-clones-render-only" {
                // Observe readiness without moving/replacing the scene or
                // reclassifying the initial failed capture. The original FAIL
                // remains unconditional, even if later geometry appears.
                do {
                    try await observeLegacyFirstVisibleFrame(view, updates: state,
                        name: name, captureStartedAt: captureStartedAt)
                } catch {
                    print("[AR_ASSET_FIRST_VISIBLE_OBSERVATION_ERROR] \(error)")
                }
            }
            throw originalFailure
        }
        return receipt
    }

    private func observeLegacyFirstVisibleFrame(_ view: ARView, updates: CaptureState,
                                                name: String, captureStartedAt: TimeInterval) async throws {
        let observationStartedAt = ProcessInfo.processInfo.systemUptime
        let deadline = observationStartedAt + 5
        var samples: [[String: Any]] = []
        var firstVisible = false
        for index in 1...12 {
            let priorUpdateCount = updates.sceneUpdates
            // Await a new scene interval, not an arbitrary rendering delay.
            while updates.sceneUpdates <= priorUpdateCount, ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            guard updates.sceneUpdates > priorUpdateCount,
                  ProcessInfo.processInfo.systemUptime < deadline else { break }
            let sample = CaptureState()
            defer { sample.active = false }
            let requestAt = ProcessInfo.processInfo.systemUptime
            view.snapshot(saveToHDR: false) { image in
                Task { @MainActor in
                    guard sample.active, !sample.snapshotFinished else { return }
                    sample.image = image
                    sample.snapshotFinishedAt = ProcessInfo.processInfo.systemUptime
                    sample.snapshotFinished = true
                }
            }
            while !sample.snapshotFinished, ProcessInfo.processInfo.systemUptime < deadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            sample.active = false
            var row: [String: Any] = ["index": index,
                "request_after_capture_start_seconds": requestAt - captureStartedAt,
                "scene_updates": updates.sceneUpdates,
                "callback_completed": sample.snapshotFinished]
            if let callbackAt = sample.snapshotFinishedAt {
                row["callback_after_capture_start_seconds"] = callbackAt - captureStartedAt
            }
            guard sample.snapshotFinished else {
                row["result"] = "callback_timeout"
                samples.append(row)
                break
            }
            if let image = sample.image, let cgImage = image.cgImage,
               cgImage.width >= 160, cgImage.height >= 120, let png = image.pngData() {
                let fraction = try nonBackgroundFraction(cgImage)
                row["png_sha256"] = SHA256.hash(data: png).map { String(format: "%02x", $0) }.joined()
                row["png_width"] = cgImage.width
                row["png_height"] = cgImage.height
                row["non_background_fraction"] = fraction
                firstVisible = fraction >= 0.002 && fraction < 0.9
                row["result"] = firstVisible ? "first_later_visible_frame" : "still_blank_or_invalid_background"
                if firstVisible {
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = name + "-first-later-visible-frame.png"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            } else {
                row["result"] = "nil_or_invalid_image"
            }
            samples.append(row)
            if firstVisible { break }
        }
        let observation: [String: Any] = ["schema": "setos-ar-first-visible-observation-v1",
            "scope": "diagnostic later snapshots of unchanged legacy scene; initial capture remains FAIL",
            "scene_or_material_mutations": false, "render_graph_mutations": false,
            "max_duration_seconds": 5, "max_samples": 12,
            "elapsed_seconds": ProcessInfo.processInfo.systemUptime - observationStartedAt,
            "first_later_visible_frame_observed": firstVisible, "samples": samples,
            "initial_blank_gate_preserved": true, "physical_ar_verified": false]
        let data = try JSONSerialization.data(withJSONObject: observation, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name + "-first-visible-observation.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func nonBackgroundFraction(_ image: CGImage) throws -> Double {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let didDraw = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard didDraw else { throw captureFailure("Cannot inspect rendered pixels") }
        // ARView's fixed plain background occupies the corner. This only rejects
        // blank/invalid captures; it is not a substitute for viewing the image.
        let background = Array(pixels.prefix(3)).map(Int.init)
        var different = 0
        for pixel in 0..<(size * size) {
            let distance = (0..<3).map { abs(Int(pixels[pixel * 4 + $0]) - background[$0]) }.max() ?? 0
            if distance > 12 { different += 1 }
        }
        return Double(different) / Double(size * size)
    }

    private func attachRenderMetadata(_ captures: [[String: Any]], name: String) throws {
        var resources: [[String: Any]] = []
        for asset in ["Circle", "Person"] {
            let url = try XCTUnwrap(Bundle.main.url(forResource: asset, withExtension: "usdz"))
            let data = try Data(contentsOf: url)
            resources.append(["name": asset, "bytes": data.count,
                "sha256": SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()])
        }
        let metadata: [String: Any] = [
            "schema": "setos-ar-owner-render-evidence-v1",
            "bundle_identifier": Bundle.main.bundleIdentifier ?? "",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "resource_identity": resources, "captures": captures,
            "tint_diagnostics": tintDiagnostics, "ar_session_started": false,
            "visual_review": "pending; nonblank pixels alone do not approve appearance"
        ]
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name + ".json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func vector(_ value: SIMD3<Float>) -> [Double] { [Double(value.x), Double(value.y), Double(value.z)] }

    private func matrixColumns(_ value: simd_float4x4) -> [[Double]] {
        (0..<4).map { index in
            let column = value[index]
            return [Double(column.x), Double(column.y), Double(column.z), Double(column.w)]
        }
    }

    private func materialBindings(of entity: Entity) -> [[String: Any]] {
        var records: [[String: Any]] = []
        if let model = entity.components[ModelComponent.self] {
            let parts = model.mesh.contents.models.flatMap { meshModel in
                meshModel.parts.map { part -> [String: Any] in
                    ["model_id": meshModel.id, "part_id": part.id,
                     "material_index": part.materialIndex,
                     "material_index_valid": part.materialIndex >= 0 && part.materialIndex < model.materials.count]
                }
            }
            records.append(["entity_name": entity.name, "material_count": model.materials.count,
                            "material_types": model.materials.map { String(describing: type(of: $0)) },
                            "parts": parts])
        }
        for child in entity.children { records += materialBindings(of: child) }
        return records
    }

    private func captureFailure(_ message: String) -> NSError {
        XCTFail(message)
        return NSError(domain: "ARAssetOwnerRenderCapture", code: 1,
                       userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func tint(of entity: ModelEntity) throws -> UIColor {
        try XCTUnwrap(entity.model?.materials.first as? SimpleMaterial).color.tint
    }

    private func assertVector(_ actual: SIMD3<Float>, _ expected: SIMD3<Float>, file: StaticString = #filePath, line: UInt = #line) {
        for index in 0..<3 { XCTAssertEqual(actual[index], expected[index], accuracy: 0.00001, file: file, line: line) }
    }
}
