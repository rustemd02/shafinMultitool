import XCTest
import ARKit
@testable import shafinMultitool

@MainActor
final class ARSessionOwnershipTests: XCTestCase {

    private final class Runtime: ARSessionRuntime {
        private let identity = NSObject()
        var sessionIdentifier: ObjectIdentifier { ObjectIdentifier(identity) }
        let videoFormatFramesPerSecond: Int? = 60
        weak var delegate: ARSessionDelegate?
        private(set) var runCount = 0
        private(set) var pauseCount = 0

        func run(_ configuration: ARConfiguration, options: ARSession.RunOptions) {
            runCount += 1
        }

        func pause() {
            pauseCount += 1
        }
    }

    private struct Capabilities: ARWorldTrackingCapabilityProviding {
        let evidence: ARWorldTrackingCapabilityEvidence
    }

    private func makeViewModel() -> SceneGeneratorViewModel {
        SceneGeneratorViewModel(
            projectName: "ar-session-owner-" + UUID().uuidString,
            presentationLocale: Locale(identifier: "en")
        )
    }

    private func makeCapabilities(
        worldTracking: Bool = true,
        horizontalPlanes: Bool = true,
        gravity: Bool = true,
        smoothedDepth: Bool = false,
        sceneDepth: Bool = false
    ) -> Capabilities {
        Capabilities(
            evidence: ARWorldTrackingCapabilityEvidence(
                supportsWorldTracking: worldTracking,
                supportsHorizontalPlaneDetection: horizontalPlanes,
                supportsGravityAlignment: gravity,
                supportsSmoothedSceneDepth: smoothedDepth,
                supportsSceneDepth: sceneDepth
            )
        )
    }

    private func request(depth: Bool = false) -> ARWorldTrackingConfigurationRequest {
        ARWorldTrackingConfigurationRequest(depthRequested: depth, initialWorldMap: nil)
    }

    func testOwnerAttachesRunsOnceAndRerunsOnlyForMaterialConfigurationChange() {
        let runtime = Runtime()
        let owner = ARSceneContainer.Coordinator(
            viewModel: makeViewModel(),
            capabilityProvider: makeCapabilities(),
            sessionRuntime: runtime
        )

        owner.attachSession(runtime: runtime)
        XCTAssertTrue(runtime.delegate === owner)

        owner.configureSessionIfNeeded(request: request(), force: true)
        owner.configureSessionIfNeeded(request: request())
        XCTAssertEqual(runtime.runCount, 1)

        owner.configureSessionIfNeeded(request: request(depth: true))
        XCTAssertEqual(runtime.runCount, 2)
    }

    func testGenerationPauseAndResumeUseTheSameRuntimeOwner() {
        let runtime = Runtime()
        let owner = ARSceneContainer.Coordinator(
            viewModel: makeViewModel(),
            capabilityProvider: makeCapabilities(),
            sessionRuntime: runtime
        )

        owner.attachSession(runtime: runtime)
        owner.updateSessionState(
            for: runtime,
            request: request(),
            isGenerating: false,
            shouldForwardCapturedImage: true,
            isSceneGenerated: false,
            isARSessionReady: false,
            isARSessionInterrupted: false,
            isARSessionRecovering: false,
            force: true
        )
        XCTAssertEqual(runtime.runCount, 1)

        owner.updateSessionState(
            for: runtime,
            request: request(),
            isGenerating: true,
            shouldForwardCapturedImage: true,
            isSceneGenerated: false,
            isARSessionReady: false,
            isARSessionInterrupted: false,
            isARSessionRecovering: false
        )
        owner.updateSessionState(
            for: runtime,
            request: request(),
            isGenerating: true,
            shouldForwardCapturedImage: true,
            isSceneGenerated: false,
            isARSessionReady: false,
            isARSessionInterrupted: false,
            isARSessionRecovering: false
        )
        XCTAssertEqual(runtime.pauseCount, 1)

        owner.updateSessionState(
            for: runtime,
            request: request(),
            isGenerating: false,
            shouldForwardCapturedImage: true,
            isSceneGenerated: false,
            isARSessionReady: false,
            isARSessionInterrupted: false,
            isARSessionRecovering: false
        )
        XCTAssertEqual(runtime.runCount, 2)
    }

    func testOwnerReleaseIsTerminalIdempotentAndFencesWrongOrStaleCallbacks() {
        let runtime = Runtime()
        let owner = ARSceneContainer.Coordinator(
            viewModel: makeViewModel(),
            capabilityProvider: makeCapabilities(),
            sessionRuntime: runtime
        )

        owner.attachSession(runtime: runtime)
        let generation = owner.sessionGeneration
        let otherRuntime = Runtime()

        XCTAssertTrue(
            owner.testingAcceptsSessionCallback(
                sessionIdentifier: runtime.sessionIdentifier,
                generation: generation
            )
        )
        XCTAssertFalse(
            owner.testingAcceptsSessionCallback(
                sessionIdentifier: otherRuntime.sessionIdentifier,
                generation: generation
            )
        )
        XCTAssertFalse(
            owner.testingAcceptsSessionCallback(
                sessionIdentifier: runtime.sessionIdentifier,
                generation: generation - 1
            )
        )

        owner.releaseSession()
        owner.releaseSession()

        XCTAssertTrue(owner.isReleased)
        XCTAssertEqual(owner.releaseCount, 1)
        XCTAssertEqual(runtime.pauseCount, 1)
        XCTAssertNil(runtime.delegate)
        XCTAssertFalse(
            owner.testingAcceptsSessionCallback(
                sessionIdentifier: runtime.sessionIdentifier,
                generation: generation
            )
        )
    }

    func testUnsupportedWorldTrackingPublishesRecoveryWithoutRunningSession() {
        let runtime = Runtime()
        let viewModel = makeViewModel()
        let owner = ARSceneContainer.Coordinator(
            viewModel: viewModel,
            capabilityProvider: makeCapabilities(worldTracking: false),
            sessionRuntime: runtime
        )

        owner.attachSession(runtime: runtime)
        owner.configureSessionIfNeeded(request: request(), force: true)

        XCTAssertEqual(runtime.runCount, 0)
        XCTAssertEqual(
            viewModel.errorMessage,
            viewModel.localizedCopy(.generatorErrorARConfigurationUnsupported)
        )
        XCTAssertFalse(viewModel.isARSessionReady)
    }

    func testDeinitPausesAndDetachesRuntime() {
        let runtime = Runtime()
        weak var weakOwner: ARSceneContainer.Coordinator?

        do {
            var owner: ARSceneContainer.Coordinator? = ARSceneContainer.Coordinator(
                viewModel: makeViewModel(),
                capabilityProvider: makeCapabilities(),
                sessionRuntime: runtime
            )
            weakOwner = owner
            owner?.attachSession(runtime: runtime)
            owner = nil
        }

        XCTAssertNil(weakOwner)
        XCTAssertEqual(runtime.pauseCount, 1)
        XCTAssertNil(runtime.delegate)
    }
}
