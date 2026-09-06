import simd
import XCTest
@testable import shafinMultitool

/// M5-030: success atomically carries generator/model/schema provenance;
/// legacy projects without the field decode honestly with nil provenance.
@MainActor
final class GenerationSuccessProvenanceTests: XCTestCase {

    func testSuccessfulGenerationStampsProvenanceAtomically() async {
        let viewModel = SceneGeneratorViewModel(projectName: "provenance-\(UUID().uuidString)")
        var cameraTransform = matrix_identity_float4x4
        cameraTransform.columns.3 = SIMD4<Float>(0, 1.5, 0, 1)
        viewModel.testingSetPlanningContext(
            cameraTransform: cameraTransform,
            planes: [ScenePlaneSnapshot(alignment: .horizontal, y: 0)]
        )
        viewModel.sceneDescription = "Марина стоит."
        viewModel.testingSetGenerationDelay(0.05)

        await viewModel.generateScene()

        XCTAssertEqual(viewModel.generationRequestState.phase, .success)
        let provenance = try! XCTUnwrap(viewModel.plannedScene?.provenance,
                                        "success must carry provenance atomically")
        XCTAssertEqual(provenance.generatorVersion, "scene-generator-v1")
        XCTAssertEqual(provenance.modelContractVersion, SETCompositionNetContract.contractVersion)
        XCTAssertEqual(provenance.schemaVersion, "scene-annotation-v1")
        _ = await viewModel.teardownAndWait()
    }

    func testLegacyPlannedSceneDecodesWithoutProvenance() throws {
        let legacyJSON = """
        {"placedActors":[],"placedObjects":[]}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(PlannedScene.self, from: legacyJSON)
        XCTAssertNil(decoded.provenance, "legacy projects decode honestly without provenance")

        var stamped = decoded
        stamped.provenance = .current
        let reencoded = try JSONEncoder().encode(stamped)
        let roundTripped = try JSONDecoder().decode(PlannedScene.self, from: reencoded)
        XCTAssertEqual(roundTripped.provenance, .current)
    }
}
