import XCTest
import ARKit
@testable import shafinMultitool

final class ARConfigurationPolicyTests: XCTestCase {

    private struct Capabilities: ARWorldTrackingCapabilityProviding {
        let evidence: ARWorldTrackingCapabilityEvidence
    }

    private func policy(
        worldTracking: Bool = true,
        horizontalPlanes: Bool = true,
        gravity: Bool = true,
        smoothedDepth: Bool = false,
        sceneDepth: Bool = false
    ) -> ARWorldTrackingConfigurationPolicy {
        ARWorldTrackingConfigurationPolicy(
            capabilityProvider: Capabilities(
                evidence: ARWorldTrackingCapabilityEvidence(
                    supportsWorldTracking: worldTracking,
                    supportsHorizontalPlaneDetection: horizontalPlanes,
                    supportsGravityAlignment: gravity,
                    supportsSmoothedSceneDepth: smoothedDepth,
                    supportsSceneDepth: sceneDepth
                )
            )
        )
    }

    private func request(depth: Bool = false) -> ARWorldTrackingConfigurationRequest {
        ARWorldTrackingConfigurationRequest(depthRequested: depth, initialWorldMap: nil)
    }

    func testWorldTrackingUnsupportedFailsBeforeConfiguration() {
        let result = policy(worldTracking: false).makePlan(for: request())

        XCTAssertEqual(result, .failure(.worldTrackingUnsupported))
    }

    func testBasePlanKeepsOnlySupportedBaseOptions() {
        let result = policy().makePlan(for: request())

        guard case .success(let plan) = result else {
            return XCTFail("supported world tracking must produce a plan")
        }
        XCTAssertEqual(plan.depth, .none)
        XCTAssertTrue(plan.planeDetectionIsHorizontal)
        XCTAssertTrue(plan.worldAlignmentIsGravity)
        XCTAssertTrue(plan.environmentTexturingIsNone)
        XCTAssertTrue(plan.sceneReconstructionIsNone)
        XCTAssertNil(plan.initialWorldMap)

        let configuration = policy().makeConfiguration(for: plan)
        XCTAssertEqual(configuration.planeDetection, [.horizontal])
        XCTAssertEqual(configuration.worldAlignment, .gravity)
        XCTAssertEqual(configuration.environmentTexturing, .none)
        XCTAssertTrue(configuration.sceneReconstruction.isEmpty)
        XCTAssertTrue(configuration.frameSemantics.isEmpty)
        XCTAssertNil(configuration.initialWorldMap)
    }

    func testRequestedDepthPrefersSmoothedSceneDepth() {
        let result = policy(smoothedDepth: true, sceneDepth: true).makePlan(for: request(depth: true))

        guard case .success(let plan) = result else {
            return XCTFail("supported depth must produce a plan")
        }
        XCTAssertEqual(plan.depth, .smoothedSceneDepth)
        XCTAssertFalse(plan.depthWasDegraded)
        XCTAssertTrue(policy(smoothedDepth: true, sceneDepth: true).makeConfiguration(for: plan).frameSemantics.contains(.smoothedSceneDepth))
    }

    func testRequestedDepthFallsBackToSceneDepth() {
        let result = policy(sceneDepth: true).makePlan(for: request(depth: true))

        guard case .success(let plan) = result else {
            return XCTFail("scene depth fallback must produce a plan")
        }
        XCTAssertEqual(plan.depth, .sceneDepth)
        XCTAssertFalse(plan.depthWasDegraded)
        let configuration = policy(sceneDepth: true).makeConfiguration(for: plan)
        XCTAssertTrue(configuration.frameSemantics.contains(.sceneDepth))
        XCTAssertFalse(configuration.frameSemantics.contains(.smoothedSceneDepth))
    }

    func testRequestedDepthUnavailableDegradesWithoutClaimingDepth() {
        let result = policy().makePlan(for: request(depth: true))

        guard case .success(let plan) = result else {
            return XCTFail("optional depth absence must remain a usable base plan")
        }
        XCTAssertEqual(plan.depth, .unavailable)
        XCTAssertTrue(plan.depthWasDegraded)
        XCTAssertTrue(policy().makeConfiguration(for: plan).frameSemantics.isEmpty)
    }

    func testBaseCapabilityFailureIsTypedAndDoesNotEnableUnsupportedOptions() {
        let planeFailure = policy(horizontalPlanes: false).makePlan(for: request())
        XCTAssertEqual(planeFailure, .failure(.baseConfigurationUnsupported))

        let gravityFailure = policy(gravity: false).makePlan(for: request())
        XCTAssertEqual(gravityFailure, .failure(.baseConfigurationUnsupported))
    }
}
