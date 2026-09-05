//
//  ARSceneContainer.swift
//  shafinMultitool
//
//  Created on 30.11.2025.
//

import SwiftUI
import ARKit
import RealityKit
import CoreVideo
import UIKit

/// The only lifecycle seam used by the workspace owner. `ARSession` adopts it
/// directly; tests can provide a call-counting runtime without pretending to
/// produce camera frames or planes.
protocol ARSessionRuntime: AnyObject {
    var sessionIdentifier: ObjectIdentifier { get }
    var delegate: ARSessionDelegate? { get set }
    var videoFormatFramesPerSecond: Int? { get }
    func run(_ configuration: ARConfiguration, options: ARSession.RunOptions)
    func pause()
}

extension ARSession: ARSessionRuntime {
    var sessionIdentifier: ObjectIdentifier { ObjectIdentifier(self) }
    var videoFormatFramesPerSecond: Int? { configuration?.videoFormat.framesPerSecond }
}

protocol ARSessionOwnerReleaseHandling: AnyObject {
    func releaseSession()
}

enum ARWorldTrackingDepthSelection: String, Equatable, Sendable {
    case none
    case smoothedSceneDepth
    case sceneDepth
    /// The request was explicit, but neither supported depth semantic exists.
    /// The applied configuration remains depth-free.
    case unavailable
}

enum ARWorldTrackingConfigurationFailure: Error, Equatable, Sendable {
    case worldTrackingUnsupported
    case baseConfigurationUnsupported

    var recoveryCopyKey: SETCopyKey {
        .generatorErrorARConfigurationUnsupported
    }
}

struct ARWorldTrackingCapabilityEvidence: Equatable, Sendable {
    let supportsWorldTracking: Bool
    let supportsHorizontalPlaneDetection: Bool
    let supportsGravityAlignment: Bool
    let supportsSmoothedSceneDepth: Bool
    let supportsSceneDepth: Bool
}

protocol ARWorldTrackingCapabilityProviding {
    var evidence: ARWorldTrackingCapabilityEvidence { get }
}

/// Production capability adapter. Simulator and hardware values are read from
/// ARKit itself; no simulator result is interpreted as tracking quality.
struct ARKitWorldTrackingCapabilityAdapter: ARWorldTrackingCapabilityProviding {
    var evidence: ARWorldTrackingCapabilityEvidence {
        let supportsWorldTracking = ARWorldTrackingConfiguration.isSupported
        return ARWorldTrackingCapabilityEvidence(
            supportsWorldTracking: supportsWorldTracking,
            supportsHorizontalPlaneDetection: supportsWorldTracking,
            supportsGravityAlignment: supportsWorldTracking,
            supportsSmoothedSceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth),
            supportsSceneDepth: ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)
        )
    }
}

struct ARWorldTrackingConfigurationRequest: Equatable {
    let depthRequested: Bool
    let initialWorldMap: ARWorldMap?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.depthRequested == rhs.depthRequested
            && lhs.initialWorldMap === rhs.initialWorldMap
    }
}

struct ARWorldTrackingConfigurationPlan: Equatable {
    let depth: ARWorldTrackingDepthSelection
    let planeDetectionIsHorizontal: Bool
    let worldAlignmentIsGravity: Bool
    let environmentTexturingIsNone: Bool
    let sceneReconstructionIsNone: Bool
    let initialWorldMap: ARWorldMap?

    var depthWasDegraded: Bool {
        depth == .unavailable
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.depth == rhs.depth
            && lhs.planeDetectionIsHorizontal == rhs.planeDetectionIsHorizontal
            && lhs.worldAlignmentIsGravity == rhs.worldAlignmentIsGravity
            && lhs.environmentTexturingIsNone == rhs.environmentTexturingIsNone
            && lhs.sceneReconstructionIsNone == rhs.sceneReconstructionIsNone
            && lhs.initialWorldMap === rhs.initialWorldMap
    }
}

struct ARWorldTrackingConfigurationPolicy {
    let capabilityProvider: any ARWorldTrackingCapabilityProviding

    init(capabilityProvider: any ARWorldTrackingCapabilityProviding = ARKitWorldTrackingCapabilityAdapter()) {
        self.capabilityProvider = capabilityProvider
    }

    func makePlan(for request: ARWorldTrackingConfigurationRequest) -> Result<ARWorldTrackingConfigurationPlan, ARWorldTrackingConfigurationFailure> {
        let evidence = capabilityProvider.evidence
        guard evidence.supportsWorldTracking else {
            return .failure(.worldTrackingUnsupported)
        }
        guard evidence.supportsHorizontalPlaneDetection,
              evidence.supportsGravityAlignment else {
            return .failure(.baseConfigurationUnsupported)
        }

        let depth: ARWorldTrackingDepthSelection
        if !request.depthRequested {
            depth = .none
        } else if evidence.supportsSmoothedSceneDepth {
            depth = .smoothedSceneDepth
        } else if evidence.supportsSceneDepth {
            depth = .sceneDepth
        } else {
            depth = .unavailable
        }

        return .success(
            ARWorldTrackingConfigurationPlan(
                depth: depth,
                planeDetectionIsHorizontal: true,
                worldAlignmentIsGravity: true,
                environmentTexturingIsNone: true,
                sceneReconstructionIsNone: true,
                initialWorldMap: request.initialWorldMap
            )
        )
    }

    func makeConfiguration(for plan: ARWorldTrackingConfigurationPlan) -> ARWorldTrackingConfiguration {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = plan.planeDetectionIsHorizontal ? [.horizontal] : []
        configuration.worldAlignment = .gravity
        configuration.environmentTexturing = .none
        configuration.sceneReconstruction = []
        configuration.initialWorldMap = plan.initialWorldMap

        switch plan.depth {
        case .smoothedSceneDepth:
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        case .sceneDepth:
            configuration.frameSemantics.insert(.sceneDepth)
        case .none, .unavailable:
            break
        }
        return configuration
    }
}

/// UIViewRepresentable обёртка для ARView в Scene Generator
struct ARSceneContainer: UIViewRepresentable {
    
    @ObservedObject var viewModel: SceneGeneratorViewModel
    let presentationLocale: Locale

    init(viewModel: SceneGeneratorViewModel, presentationLocale: Locale = .current) {
        self.viewModel = viewModel
        self.presentationLocale = presentationLocale
    }
    
    func makeUIView(context: Context) -> ARView {
        viewModel.setPresentationLocale(presentationLocale)
        // Disable automatic session work before the sole owner attaches.
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)

        context.coordinator.attachSession(to: arView)
        context.coordinator.updateSessionState(
            for: arView,
            request: viewModel.makeARSessionConfigurationRequest(),
            isGenerating: viewModel.isGenerating,
            shouldForwardCapturedImage: viewModel.isRecording || viewModel.isHintsEnabled,
            isSceneGenerated: viewModel.plannedScene != nil,
            isARSessionReady: viewModel.isARSessionReady,
            isARSessionInterrupted: viewModel.isARSessionInterrupted,
            isARSessionRecovering: viewModel.isARSessionRecovering,
            force: true
        )
        
        // Настройки рендеринга
        arView.renderOptions = [
            .disableMotionBlur,
            .disableDepthOfField,
            .disableCameraGrain,
            .disablePersonOcclusion,
            .disableGroundingShadows,
            .disableHDR
        ]
        
        // Добавляем coaching overlay для помощи пользователю
        let coachingOverlay = ARCoachingOverlayView()
        coachingOverlay.session = arView.session
        coachingOverlay.goal = .horizontalPlane
        coachingOverlay.activatesAutomatically = true
        coachingOverlay.translatesAutoresizingMaskIntoConstraints = false
        context.coordinator.coachingOverlay = coachingOverlay
        arView.addSubview(coachingOverlay)
        
        NSLayoutConstraint.activate([
            coachingOverlay.topAnchor.constraint(equalTo: arView.topAnchor),
            coachingOverlay.leadingAnchor.constraint(equalTo: arView.leadingAnchor),
            coachingOverlay.trailingAnchor.constraint(equalTo: arView.trailingAnchor),
            coachingOverlay.bottomAnchor.constraint(equalTo: arView.bottomAnchor)
        ])
        
        // Сохраняем ссылку на ARView в ViewModel
        DispatchQueue.main.async {
            viewModel.attachARView(arView)
        }
        
        // Добавляем жест для отладки
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.35
        arView.addGestureRecognizer(longPressGesture)
        
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        MainActor.assumeIsolated {
            guard !viewModel.isWorkspaceReleased else {
                context.coordinator.releaseSession()
                return
            }
            viewModel.setPresentationLocale(presentationLocale)
            context.coordinator.updateSessionState(
                for: uiView,
                request: viewModel.makeARSessionConfigurationRequest(),
                isGenerating: viewModel.isGenerating,
                shouldForwardCapturedImage: viewModel.isRecording || viewModel.isHintsEnabled,
                isSceneGenerated: viewModel.plannedScene != nil,
                isARSessionReady: viewModel.isARSessionReady,
                isARSessionInterrupted: viewModel.isARSessionInterrupted,
                isARSessionRecovering: viewModel.isARSessionRecovering
            )
        }
    }

    static func dismantleUIView(_ uiView: ARView, coordinator: Coordinator) {
        MainActor.assumeIsolated {
            coordinator.releaseSession()
        }
        coordinator.recordingController = nil
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, ARSessionDelegate, ARSessionOwnerReleaseHandling {
        
        let viewModel: SceneGeneratorViewModel
        private let configurationPolicy: ARWorldTrackingConfigurationPolicy
        private let recordingSourceOwnerID = UUID()
        private var hasClaimedRecordingSource = false
        weak var coachingOverlay: ARCoachingOverlayView?
        private var isGenerationActive = false
        private var isSceneGenerated = false
        private var isSessionPausedForGeneration = false
        private var sessionRuntime: (any ARSessionRuntime)?
        private var appliedConfigurationPlan: ARWorldTrackingConfigurationPlan?
        private var lastProcessedFrameTimestamp: TimeInterval = 0
        private var shouldForwardCapturedImage = false
        /// Cached on the MainActor during representable updates, then used
        /// directly from ARSessionDelegate without a per-frame hop.
        private let recordingControllerLock = NSLock()
        private var recordingControllerStorage: SceneRecordingController?
        fileprivate var recordingController: SceneRecordingController? {
            get {
                recordingControllerLock.lock()
                defer { recordingControllerLock.unlock() }
                return recordingControllerStorage
            }
            set {
                recordingControllerLock.lock()
                recordingControllerStorage = newValue
                recordingControllerLock.unlock()
            }
        }
        private let frameTaskLock = NSLock()
        private var frameTaskInFlight = false
        private let sessionStateLock = NSLock()
        private var activeSessionIdentifier: ObjectIdentifier?
        private var activeSessionGeneration = 0
        private var sessionIsReleased = false
        private var sessionReleaseCount = 0
        private var interruptionSafetyApplied = false
        private var interruptionSafetyApplications = 0
        private var skippedFramesSinceLog = 0
        private var processedFramesSinceLog = 0
        private var lastFrameMetricsLogTimestamp: TimeInterval = 0
        private var lastTrackingStateDescription: String?
        private weak var arView: ARView?
        private var viewportSize: CGSize = .zero
        private var interfaceOrientation: UIInterfaceOrientation = .portrait
        private var lastCameraAnalysisGeometryLogTimestamp: TimeInterval = 0
        private var orientationObserver: NSObjectProtocol?
        private var isGeneratingOrientationNotifications = false
        private var frameProcessingInterval: TimeInterval {
            switch ProcessInfo.processInfo.thermalState {
            case .serious, .critical:
                return 1.0 / 5.0
            case .fair:
                return shouldForwardCapturedImage ? 1.0 / 12.0 : 1.0 / 8.0
            case .nominal:
                return shouldForwardCapturedImage ? 1.0 / 15.0 : (isSceneGenerated ? 1.0 / 8.0 : 1.0 / 10.0)
            @unknown default:
                return 1.0 / 8.0
            }
        }
        
        init(
            viewModel: SceneGeneratorViewModel,
            capabilityProvider: any ARWorldTrackingCapabilityProviding = ARKitWorldTrackingCapabilityAdapter(),
            sessionRuntime: (any ARSessionRuntime)? = nil
        ) {
            self.viewModel = viewModel
            self.configurationPolicy = ARWorldTrackingConfigurationPolicy(capabilityProvider: capabilityProvider)
            self.sessionRuntime = sessionRuntime
            super.init()
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            isGeneratingOrientationNotifications = true
            orientationObserver = NotificationCenter.default.addObserver(
                forName: UIDevice.orientationDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleOrientationRefresh()
            }
        }

        deinit {
            releaseRuntimeForDeinit()
            if let orientationObserver {
                NotificationCenter.default.removeObserver(orientationObserver)
            }
            if isGeneratingOrientationNotifications {
                UIDevice.current.endGeneratingDeviceOrientationNotifications()
            }
        }

        @MainActor
        func attachSession(to arView: ARView) {
            self.arView = arView
            attachSession(runtime: arView.session)
        }

        @MainActor
        func attachSession(runtime: any ARSessionRuntime) {
            guard !sessionIsReleased else { return }
            if let currentRuntime = sessionRuntime,
               currentRuntime.sessionIdentifier == runtime.sessionIdentifier {
                if !hasActiveSession(identifier: runtime.sessionIdentifier) {
                    setActiveSession(identifier: runtime.sessionIdentifier)
                    viewModel.setARSessionOwner(self)
                    viewModel.setExpectedARSessionGeneration(currentSessionGeneration())
                }
                runtime.delegate = self
                return
            }

            if sessionRuntime != nil {
                releaseActiveRuntimeForReplacement()
            }

            sessionRuntime = runtime
            setActiveSession(identifier: runtime.sessionIdentifier)
            interruptionSafetyApplied = false
            runtime.delegate = self
            viewModel.setARSessionOwner(self)
            viewModel.setExpectedARSessionGeneration(currentSessionGeneration())
        }

        @MainActor
        func updateSessionState(for arView: ARView,
                                request: ARWorldTrackingConfigurationRequest,
                                isGenerating: Bool,
                                shouldForwardCapturedImage: Bool,
                                isSceneGenerated: Bool,
                                isARSessionReady: Bool,
                                isARSessionInterrupted: Bool,
                                isARSessionRecovering: Bool,
                                force: Bool = false) {
            updateSessionState(
                runtime: arView.session,
                arView: arView,
                request: request,
                isGenerating: isGenerating,
                shouldForwardCapturedImage: shouldForwardCapturedImage,
                isSceneGenerated: isSceneGenerated,
                isARSessionReady: isARSessionReady,
                isARSessionInterrupted: isARSessionInterrupted,
                isARSessionRecovering: isARSessionRecovering,
                force: force
            )
        }

        /// Runtime-only overload keeps lifecycle call-count tests on the same
        /// owner path without fabricating an ARView or AR tracking result.
        @MainActor
        func updateSessionState(for runtime: any ARSessionRuntime,
                                request: ARWorldTrackingConfigurationRequest,
                                isGenerating: Bool,
                                shouldForwardCapturedImage: Bool,
                                isSceneGenerated: Bool,
                                isARSessionReady: Bool,
                                isARSessionInterrupted: Bool,
                                isARSessionRecovering: Bool,
                                force: Bool = false) {
            updateSessionState(
                runtime: runtime,
                arView: nil,
                request: request,
                isGenerating: isGenerating,
                shouldForwardCapturedImage: shouldForwardCapturedImage,
                isSceneGenerated: isSceneGenerated,
                isARSessionReady: isARSessionReady,
                isARSessionInterrupted: isARSessionInterrupted,
                isARSessionRecovering: isARSessionRecovering,
                force: force
            )
        }

        @MainActor
        private func updateSessionState(runtime: any ARSessionRuntime,
                                        arView: ARView?,
                                        request: ARWorldTrackingConfigurationRequest,
                                        isGenerating: Bool,
                                        shouldForwardCapturedImage: Bool,
                                        isSceneGenerated: Bool,
                                        isARSessionReady: Bool,
                                        isARSessionInterrupted: Bool,
                                        isARSessionRecovering: Bool,
                                        force: Bool) {
            guard !sessionIsReleased else { return }
            if sessionRuntime?.sessionIdentifier != runtime.sessionIdentifier {
                attachSession(runtime: runtime)
            }
            if let arView {
                self.arView = arView
                refreshOrientation(for: arView)
            }
            self.recordingController = viewModel.sceneRecordingController
            self.shouldForwardCapturedImage = shouldForwardCapturedImage && !isGenerating
            self.isSceneGenerated = isSceneGenerated
            updateCoachingOverlay(
                isARSessionReady: isARSessionReady,
                isARSessionInterrupted: isARSessionInterrupted,
                isARSessionRecovering: isARSessionRecovering
            )
            if isGenerating {
                pauseSessionIfNeeded()
                return
            }

            if isSessionPausedForGeneration {
                resumeSessionIfNeeded(request: request)
                return
            }

            isGenerationActive = false
            configureSessionIfNeeded(request: request, force: force)
        }

        private func scheduleOrientationRefresh() {
            DispatchQueue.main.async { [weak self] in
                guard let self, let arView = self.arView else { return }
                self.refreshOrientation(for: arView)
            }
        }

        /// Refreshes only cached presentation geometry. Rotation never reruns
        /// or pauses the AR session, so world tracking and project state stay
        /// continuous while the display transform follows the new viewport.
        private func refreshOrientation(for arView: ARView) {
            viewportSize = arView.bounds.size
            if let orientation = Self.currentInterfaceOrientation(for: arView),
               orientation != .unknown {
                interfaceOrientation = orientation
            }
        }

        @MainActor
        func configureSessionIfNeeded(
            request: ARWorldTrackingConfigurationRequest,
            force: Bool = false
        ) {
            guard let runtime = sessionRuntime,
                  !sessionIsReleased else { return }
            guard let plan = resolvedPlan(for: request) else { return }
            if !force, appliedConfigurationPlan == plan {
                return
            }

            let generation = beginNewSessionGeneration()
            runtime.run(configurationPolicy.makeConfiguration(for: plan), options: [])
            appliedConfigurationPlan = plan
            isSessionPausedForGeneration = false
            viewModel.setExpectedARSessionGeneration(generation)
            publishRecordingSourceFPS(for: runtime)
        }

        @MainActor
        private func pauseSessionIfNeeded() {
            isGenerationActive = true
            shouldForwardCapturedImage = false
            guard !isSessionPausedForGeneration else { return }
            guard let runtime = sessionRuntime else { return }
            let generation = beginNewSessionGeneration()
            runtime.pause()
            isSessionPausedForGeneration = true
            viewModel.setExpectedARSessionGeneration(generation)
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session paused for generation")
        }

        @MainActor
        private func resumeSessionIfNeeded(request: ARWorldTrackingConfigurationRequest) {
            guard isSessionPausedForGeneration else { return }
            guard let runtime = sessionRuntime,
                  let plan = resolvedPlan(for: request) else { return }
            isGenerationActive = false
            let generation = beginNewSessionGeneration()
            runtime.run(configurationPolicy.makeConfiguration(for: plan), options: [])
            publishRecordingSourceFPS(for: runtime)
            appliedConfigurationPlan = plan
            isSessionPausedForGeneration = false
            lastProcessedFrameTimestamp = 0
            lastTrackingStateDescription = nil
            viewModel.setExpectedARSessionGeneration(generation)
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session resumed after generation depthEnabled=\(request.depthRequested)")
        }

        func releaseSession() {
            guard let release = beginTerminalRelease() else { return }
            release.runtime?.pause()
            release.runtime?.delegate = nil
            MainActor.assumeIsolated {
                releaseRecordingSource()
                viewModel.clearARSessionOwner(self)
                viewModel.setExpectedARSessionGeneration(release.generation)
            }
            isGenerationActive = true
            isSessionPausedForGeneration = false
            appliedConfigurationPlan = nil
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session paused and detached for workspace teardown")
        }

        var isReleased: Bool {
            sessionStateLock.lock()
            defer { sessionStateLock.unlock() }
            return sessionIsReleased
        }

        var releaseCount: Int {
            sessionStateLock.lock()
            defer { sessionStateLock.unlock() }
            return sessionReleaseCount
        }

        var interruptionSafetyApplicationCount: Int {
            interruptionSafetyApplications
        }

        var sessionGeneration: Int {
            currentSessionGeneration()
        }

        func testingAcceptsSessionCallback(
            sessionIdentifier: ObjectIdentifier,
            generation: Int
        ) -> Bool {
            acceptsSessionCallback(sessionIdentifier: sessionIdentifier, generation: generation)
        }

        @MainActor
        private func resolvedPlan(for request: ARWorldTrackingConfigurationRequest) -> ARWorldTrackingConfigurationPlan? {
            switch configurationPolicy.makePlan(for: request) {
            case .success(let plan):
                return plan
            case .failure(let failure):
                appliedConfigurationPlan = nil
                releaseRecordingSource()
                viewModel.handleARSessionConfigurationFailure(failure)
                return nil
            }
        }

        @MainActor
        private func releaseActiveRuntimeForReplacement() {
            guard let runtime = sessionRuntime else { return }
            sessionRuntime = nil
            clearActiveSession()
            _ = beginNewSessionGeneration()
            runtime.pause()
            runtime.delegate = nil
            releaseRecordingSource()
            appliedConfigurationPlan = nil
        }

        private func beginTerminalRelease() -> (runtime: (any ARSessionRuntime)?, generation: Int)? {
            sessionStateLock.lock()
            guard !sessionIsReleased else {
                sessionStateLock.unlock()
                return nil
            }
            sessionIsReleased = true
            activeSessionIdentifier = nil
            activeSessionGeneration += 1
            sessionReleaseCount += 1
            let generation = activeSessionGeneration
            let runtime = sessionRuntime
            sessionRuntime = nil
            sessionStateLock.unlock()
            return (runtime, generation)
        }

        private func releaseRuntimeForDeinit() {
            guard let release = beginTerminalRelease() else { return }
            release.runtime?.pause()
            release.runtime?.delegate = nil
            let ownerID = recordingSourceOwnerID
            Task { @MainActor [weak viewModel] in
                viewModel?.releaseRecordingSource(ownerID: ownerID)
            }
        }

        private func setActiveSession(identifier: ObjectIdentifier) {
            sessionStateLock.lock()
            activeSessionIdentifier = identifier
            sessionIsReleased = false
            activeSessionGeneration += 1
            sessionStateLock.unlock()
        }

        private func clearActiveSession() {
            sessionStateLock.lock()
            activeSessionIdentifier = nil
            sessionStateLock.unlock()
        }

        private func hasActiveSession(identifier: ObjectIdentifier) -> Bool {
            sessionStateLock.lock()
            defer { sessionStateLock.unlock() }
            return !sessionIsReleased && activeSessionIdentifier == identifier
        }

        private func beginNewSessionGeneration() -> Int {
            sessionStateLock.lock()
            activeSessionGeneration += 1
            let generation = activeSessionGeneration
            sessionStateLock.unlock()
            return generation
        }

        private func currentSessionGeneration() -> Int {
            sessionStateLock.lock()
            defer { sessionStateLock.unlock() }
            return activeSessionGeneration
        }

        private func acceptsSessionCallback(
            sessionIdentifier: ObjectIdentifier,
            generation: Int
        ) -> Bool {
            sessionStateLock.lock()
            defer { sessionStateLock.unlock() }
            return !sessionIsReleased
                && activeSessionIdentifier == sessionIdentifier
                && activeSessionGeneration == generation
        }

        private func callbackGeneration(for session: ARSession) -> Int? {
            sessionStateLock.lock()
            defer { sessionStateLock.unlock() }
            guard !sessionIsReleased,
                  activeSessionIdentifier == ObjectIdentifier(session) else {
                return nil
            }
            return activeSessionGeneration
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            guard let generation = callbackGeneration(for: session) else { return }
            guard !isGenerationActive else { return }
            logTrackingStateIfNeeded(frame.camera.trackingState)

            let timestamp = frame.timestamp
            let capturedImage = frame.capturedImage
            let sessionIdentifier = ObjectIdentifier(session)
            guard acceptsSessionCallback(sessionIdentifier: sessionIdentifier, generation: generation) else { return }
            recordingController?.enqueueVideo(capturedImage, at: timestamp)
            let cameraTransform = frame.camera.transform
            Task { @MainActor [weak self, weak viewModel, cameraTransform, timestamp, generation, sessionIdentifier] in
                guard let self,
                      self.acceptsSessionCallback(sessionIdentifier: sessionIdentifier, generation: generation) else { return }
                viewModel?.updateARPresentationFrame(
                    cameraTransform: cameraTransform,
                    timestamp: timestamp,
                    generation: generation
                )
            }

            // processARFrame не требует 60 вызовов/сек: в storyboard-only режиме держим AR легче.
            guard timestamp - lastProcessedFrameTimestamp >= frameProcessingInterval else { return }
            lastProcessedFrameTimestamp = timestamp
            guard beginFrameTaskIfPossible(timestamp: timestamp) else { return }

            let planeSnapshots = frame.anchors.compactMap { ($0 as? ARPlaneAnchor).map(ScenePlaneSnapshot.init(anchor:)) }
            let analysisImage: CVPixelBuffer? = shouldForwardCapturedImage ? capturedImage : nil
            let displayTransform = frame.displayTransform(
                for: interfaceOrientation,
                viewportSize: viewportSize == .zero ? CGSize(width: 1, height: 1) : viewportSize
            )
            let currentInterfaceOrientation = interfaceOrientation
            logCameraAnalysisGeometryIfNeeded(
                frame: frame,
                timestamp: timestamp,
                capturedImage: analysisImage,
                displayTransform: displayTransform
            )

            Task { @MainActor [weak self, cameraTransform, planeSnapshots, timestamp, analysisImage, currentInterfaceOrientation, displayTransform, generation, sessionIdentifier] in
                guard let self else { return }
                guard self.acceptsSessionCallback(sessionIdentifier: sessionIdentifier, generation: generation) else {
                    self.completeFrameTask(timestamp: timestamp)
                    return
                }
                viewModel.processARFrameSnapshot(
                    cameraTransform: cameraTransform,
                    planeSnapshots: planeSnapshots,
                    timestamp: timestamp,
                    capturedImage: analysisImage,
                    interfaceOrientation: currentInterfaceOrientation,
                    displayTransform: displayTransform,
                    generation: generation
                )
                self.completeFrameTask(timestamp: timestamp)
            }
        }
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            guard callbackGeneration(for: session) != nil else { return }
            // Плоскость обнаружена - обновление происходит через processARFrame
        }
        
        func session(_ session: ARSession, didFailWithError error: Error) {
            guard let generation = callbackGeneration(for: session) else { return }
            let sessionIdentifier = ObjectIdentifier(session)
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] session failed: \(error.localizedDescription)")
            Task { @MainActor [weak self] in
                guard let self,
                      self.acceptsSessionCallback(sessionIdentifier: sessionIdentifier, generation: generation) else { return }
                self.releaseRecordingSource()
                let prefix = self.viewModel.localizedCopy(.arErrorPrefix)
                self.viewModel.errorMessage = "\(prefix): \(error.localizedDescription)"
            }
        }

        @MainActor
        private func publishRecordingSourceFPS(for runtime: any ARSessionRuntime) {
            let fps = runtime.videoFormatFramesPerSecond
            if hasClaimedRecordingSource {
                viewModel.updateRecordingSourceFPS(fps, ownerID: recordingSourceOwnerID)
            } else if viewModel.claimRecordingSource(ownerID: recordingSourceOwnerID, fps: fps) {
                hasClaimedRecordingSource = true
            }
        }

        @MainActor
        func releaseRecordingSource() {
            viewModel.releaseRecordingSource(ownerID: recordingSourceOwnerID)
            hasClaimedRecordingSource = false
        }
        
        func sessionWasInterrupted(_ session: ARSession) {
            guard callbackGeneration(for: session) != nil else { return }
            let generation = advanceFrameGeneration()
            let sessionIdentifier = ObjectIdentifier(session)
            Task { @MainActor [weak self] in
                guard let self,
                      self.acceptsSessionCallback(sessionIdentifier: sessionIdentifier, generation: generation) else { return }
                self.applyInterruptionSafetyIfNeeded(generation: generation)
                SceneGeneratorDiagnosticsLogger.shared.log("[AR] session interrupted")
            }
        }
        
        func sessionInterruptionEnded(_ session: ARSession) {
            guard callbackGeneration(for: session) != nil else { return }
            let generation = advanceFrameGeneration()
            let sessionIdentifier = ObjectIdentifier(session)
            Task { @MainActor [weak self] in
                guard let self,
                      self.acceptsSessionCallback(sessionIdentifier: sessionIdentifier, generation: generation) else { return }
                // The ended callback may win the MainActor race against the
                // earlier interruption callback. Safety must still run for
                // this accepted generation before recovery is entered.
                self.applyInterruptionSafetyIfNeeded(generation: generation)
                self.viewModel.handleARSessionInterruptionEnded(generation: generation)
                self.interruptionSafetyApplied = false
                SceneGeneratorDiagnosticsLogger.shared.log("[AR] session interruption ended")
            }
        }

        @MainActor
        private func applyInterruptionSafetyIfNeeded(generation: Int) {
            guard !interruptionSafetyApplied else { return }
            interruptionSafetyApplied = true
            interruptionSafetyApplications += 1
            viewModel.handleARSessionInterruption(generation: generation)
        }

        private func advanceFrameGeneration() -> Int {
            beginNewSessionGeneration()
        }

        private func updateCoachingOverlay(isARSessionReady: Bool,
                                           isARSessionInterrupted: Bool,
                                           isARSessionRecovering: Bool) {
            let shouldHide = !isARSessionInterrupted
                && !isARSessionRecovering
                && isARSessionReady
            coachingOverlay?.activatesAutomatically = !shouldHide
            coachingOverlay?.isHidden = shouldHide
            if shouldHide, coachingOverlay?.isActive == true {
                coachingOverlay?.setActive(false, animated: true)
            }
        }

        private func beginFrameTaskIfPossible(timestamp: TimeInterval) -> Bool {
            frameTaskLock.lock()
            defer { frameTaskLock.unlock() }
            guard !frameTaskInFlight else {
                skippedFramesSinceLog += 1
                if skippedFramesSinceLog % 30 == 0 {
                    SceneGeneratorDiagnosticsLogger.shared.log("[AR] skipped frames because MainActor frame task is still in flight: skipped=\(skippedFramesSinceLog)")
                }
                return false
            }
            frameTaskInFlight = true
            return true
        }

        private func completeFrameTask(timestamp: TimeInterval) {
            frameTaskLock.lock()
            frameTaskInFlight = false
            processedFramesSinceLog += 1
            let skipped = skippedFramesSinceLog
            if lastFrameMetricsLogTimestamp == 0 {
                lastFrameMetricsLogTimestamp = timestamp
            }
            let elapsed = timestamp - lastFrameMetricsLogTimestamp
            let shouldLog = elapsed >= 5
            let processed = processedFramesSinceLog
            if shouldLog {
                skippedFramesSinceLog = 0
                processedFramesSinceLog = 0
                lastFrameMetricsLogTimestamp = timestamp
            }
            frameTaskLock.unlock()

            if shouldLog {
                let fps = elapsed > 0 ? Double(processed) / elapsed : 0
                let thermalState = ProcessInfo.processInfo.thermalState
                let memory = SceneGeneratorExecutionSupport.memoryUsageMB().map { String(format: "%.0f", $0) } ?? "nil"
                SceneGeneratorDiagnosticsLogger.shared.log("[AR] processed fps sample=\(String(format: "%.1f", fps)), skipped=\(skipped), thermal=\(thermalState), memoryMB=\(memory)")
            }
        }

        private func logTrackingStateIfNeeded(_ trackingState: ARCamera.TrackingState) {
            let description = trackingStateDescription(trackingState)
            guard description != lastTrackingStateDescription else { return }
            lastTrackingStateDescription = description
            SceneGeneratorDiagnosticsLogger.shared.log("[AR] trackingState=\(description)")
        }

        private func trackingStateDescription(_ trackingState: ARCamera.TrackingState) -> String {
            switch trackingState {
            case .normal:
                return "normal"
            case .notAvailable:
                return "not_available"
            case .limited(let reason):
                return "limited(\(trackingReasonDescription(reason)))"
            }
        }

        private func trackingReasonDescription(_ reason: ARCamera.TrackingState.Reason) -> String {
            switch reason {
            case .excessiveMotion:
                return "excessive_motion"
            case .insufficientFeatures:
                return "insufficient_features"
            case .initializing:
                return "initializing"
            case .relocalizing:
                return "relocalizing"
            @unknown default:
                return "unknown"
            }
        }

        private func logCameraAnalysisGeometryIfNeeded(frame: ARFrame,
                                                       timestamp: TimeInterval,
                                                       capturedImage: CVPixelBuffer?,
                                                       displayTransform: CGAffineTransform) {
            guard capturedImage != nil,
                  timestamp - lastCameraAnalysisGeometryLogTimestamp >= 1.0 else { return }
            lastCameraAnalysisGeometryLogTimestamp = timestamp
            let imageSize = capturedImage.map(Self.pixelBufferSizeDescription) ?? "nil"
            print(
                "[CA_DEBUG][AR_FRAME] ts=\(Self.format(timestamp)) forwardCaptured=\(capturedImage != nil) " +
                "interface=\(Self.interfaceOrientationDescription(interfaceOrientation)) " +
                "viewport=\(Self.sizeDescription(viewportSize)) image=\(imageSize) " +
                "displayTransform=\(Self.transformDescription(displayTransform)) " +
                "tracking=\(trackingStateDescription(frame.camera.trackingState))"
            )
        }

        private static func pixelBufferSizeDescription(_ pixelBuffer: CVPixelBuffer) -> String {
            "\(CVPixelBufferGetWidth(pixelBuffer))x\(CVPixelBufferGetHeight(pixelBuffer))"
        }

        private static func sizeDescription(_ size: CGSize) -> String {
            "\(format(Double(size.width)))x\(format(Double(size.height)))"
        }

        private static func transformDescription(_ transform: CGAffineTransform) -> String {
            "[a=\(format(Double(transform.a))) b=\(format(Double(transform.b))) c=\(format(Double(transform.c))) d=\(format(Double(transform.d))) tx=\(format(Double(transform.tx))) ty=\(format(Double(transform.ty)))]"
        }

        private static func interfaceOrientationDescription(_ orientation: UIInterfaceOrientation) -> String {
            switch orientation {
            case .portrait:
                return "portrait"
            case .portraitUpsideDown:
                return "portraitUpsideDown"
            case .landscapeLeft:
                return "landscapeLeft"
            case .landscapeRight:
                return "landscapeRight"
            case .unknown:
                return "unknown"
            @unknown default:
                return "unknownFuture"
            }
        }

        private static func format(_ value: Double) -> String {
            String(format: "%.3f", value)
        }

        private static func currentInterfaceOrientation(for arView: ARView) -> UIInterfaceOrientation? {
            if let orientation = arView.window?.windowScene?.interfaceOrientation,
               orientation != .unknown {
                return orientation
            }

            return UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .map(\.interfaceOrientation)
                .first { $0 != .unknown }
        }
        
        // MARK: - Gestures
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = gesture.view as? ARView else { return }
            let location = gesture.location(in: arView)
            
            Task { @MainActor in
                SceneGeneratorDiagnosticsLogger.shared.log(
                    "[TOUCH_TRACE] arView tap state=\(Self.gestureStateDescription(gesture.state)) point=(\(Self.format(Double(location.x))), \(Self.format(Double(location.y)))), marking=\(viewModel.isMarkingMode), activeEditor=\(viewModel.activeStoryboardEditDraft?.beatID ?? "nil")"
                )
                // Если включен режим разметки - создаём маркер
                if viewModel.isMarkingMode {
                    viewModel.handleTapForMarker(at: location)
                    return
                }
                
                // Иначе - проверяем попадание по объекту
                if let _ = arView.entity(at: location) {
                    // Можно добавить выделение или другую логику
                }
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard let arView = gesture.view as? ARView else { return }
            let location = gesture.location(in: arView)
            if Self.shouldLogLongPressState(gesture.state) {
                SceneGeneratorDiagnosticsLogger.shared.log(
                    "[AR_GESTURE] longPress state=\(Self.gestureStateDescription(gesture.state)) point=(\(Self.format(Double(location.x))), \(Self.format(Double(location.y))))"
                )
            }

            Task { @MainActor in
                if Self.shouldLogLongPressState(gesture.state) {
                    SceneGeneratorDiagnosticsLogger.shared.log(
                        "[TOUCH_TRACE] arView longPress routed state=\(Self.gestureStateDescription(gesture.state)) point=(\(Self.format(Double(location.x))), \(Self.format(Double(location.y)))), marking=\(viewModel.isMarkingMode), activeEditor=\(viewModel.activeStoryboardEditDraft?.beatID ?? "nil")"
                    )
                }
                viewModel.handleStoryboardActorDragGesture(state: gesture.state, at: location)
            }
        }

        private static func shouldLogLongPressState(_ state: UIGestureRecognizer.State) -> Bool {
            switch state {
            case .began, .ended, .cancelled, .failed:
                return true
            default:
                return false
            }
        }

        private static func gestureStateDescription(_ state: UIGestureRecognizer.State) -> String {
            switch state {
            case .possible:
                return "possible"
            case .began:
                return "began"
            case .changed:
                return "changed"
            case .ended:
                return "ended"
            case .cancelled:
                return "cancelled"
            case .failed:
                return "failed"
            @unknown default:
                return "unknown"
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ARSceneContainer_Previews: PreviewProvider {
    static var previews: some View {
        ARSceneContainer(viewModel: SceneGeneratorViewModel())
            .ignoresSafeArea()
    }
}
#endif
