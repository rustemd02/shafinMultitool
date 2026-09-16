//
//  CameraManager.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import AVFoundation
import AVKit
import Combine
import CoreMotion
import ImageIO
import UIKit

/// Physical camera inventory, not a guessed focal-length catalogue. A device
/// exposes at most one telephoto entry even when product marketing labels that
/// same module differently across models.
enum CameraLens: String, CaseIterable, Equatable, Sendable {
    case ultraWide = "ultra_wide"
    case wide = "wide"
    case telephoto = "tele"
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .telephoto: return .builtInTelephotoCamera
        }
    }
    
    var displayName: String {
        switch self {
        case .ultraWide: return "ULTRA"
        case .wide: return "WIDE"
        case .telephoto: return "TELE"
        }
    }

    var descriptor: CameraLensDescriptor {
        CameraLensDescriptor(
            lens: self,
            identifier: rawValue,
            displayName: displayName,
            physicalDeviceType: String(describing: deviceType),
            displayMetadata: nil
        )
    }
}

enum CameraLensDisplayMetadata: Equatable, Sendable {
    case measuredEquivalentFocalLengthMillimeters(Double)
    case truthfulMagnification(Double)
}

struct CameraLensDescriptor: Equatable, Sendable {
    let lens: CameraLens
    let identifier: String
    let displayName: String
    let physicalDeviceType: String
    /// Hardware metadata is optional because this manager does not fabricate
    /// equivalent focal-length values. A device integration may provide a measured
    /// equivalent focal length or a truthful optical magnification instead.
    let displayMetadata: CameraLensDisplayMetadata?

    var displayLabel: String {
        guard let displayMetadata else { return displayName }
        switch displayMetadata {
        case .measuredEquivalentFocalLengthMillimeters(let millimeters):
            return String(format: "%.0f MM", millimeters)
        case .truthfulMagnification(let magnification):
            return String(format: "%.1f×", magnification)
        }
    }

    init(lens: CameraLens,
         identifier: String,
         displayName: String,
         physicalDeviceType: String,
         displayMetadata: CameraLensDisplayMetadata? = nil) {
        self.lens = lens
        self.identifier = identifier
        self.displayName = displayName
        self.physicalDeviceType = physicalDeviceType
        self.displayMetadata = displayMetadata
    }
}

enum CameraLensSwitchResult: Equatable, Sendable {
    enum FailureReason: Equatable, Sendable {
        case notConfigured
        case unavailable
        case inputConstructionFailed
        case replacementRejected
        case rollbackFailed
        case recordingInProgress
    }

    case success(activeLens: CameraLens)
    case noOp(activeLens: CameraLens)
    case failure(requestedLens: CameraLens,
                 lastKnownActiveLens: CameraLens?,
                 reason: FailureReason)
}

enum CameraManagerError: Error, Equatable, Sendable, CustomStringConvertible {
    case noWideCamera
    case inputConstructionFailed
    case inputAddFailed
    case outputAddFailed
    case startFailed
    case sessionInterrupted
    case runtimeError

    var description: String {
        switch self {
        case .noWideCamera:
            return "The back wide camera is unavailable."
        case .inputConstructionFailed:
            return "The back wide camera input could not be constructed."
        case .inputAddFailed:
            return "The back wide camera input could not be added to the session."
        case .outputAddFailed:
            return "The video output could not be added to the session."
        case .startFailed:
            return "The capture session did not start running."
        case .sessionInterrupted:
            return "The capture session was interrupted."
        case .runtimeError:
            return "The capture session reported a runtime error."
        }
    }
}

/// Shared orientation vocabulary for the Camera Coach capture and AR
/// presentation seams. Keeping the mappings together prevents preview,
/// capture analysis, and display transforms from drifting during rotation.
enum CameraCoachOrientation: CaseIterable, Equatable, Sendable {
    case portrait
    case portraitUpsideDown
    case landscapeLeft
    case landscapeRight

    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        case .unknown:
            return nil
        @unknown default:
            return nil
        }
    }

    init(captureOrientation: AVCaptureVideoOrientation) {
        switch captureOrientation {
        case .portrait:
            self = .portrait
        case .portraitUpsideDown:
            self = .portraitUpsideDown
        case .landscapeLeft:
            self = .landscapeLeft
        case .landscapeRight:
            self = .landscapeRight
        @unknown default:
            self = .portrait
        }
    }

    var interfaceOrientation: UIInterfaceOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        }
    }

    var captureOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeLeft
        case .landscapeRight:
            return .landscapeRight
        }
    }

    var imageOrientation: CGImagePropertyOrientation {
        switch self {
        case .portrait:
            return .right
        case .portraitUpsideDown:
            return .left
        case .landscapeRight:
            return .up
        case .landscapeLeft:
            return .down
        }
    }
}

/// The data-output connection is configured through a tiny seam so the
/// native-buffer contract can be verified without constructing a capture
/// graph. Preview-layer orientation remains a separate owner.
protocol CameraDataOutputMirroringConnectionConfiguring: AnyObject {
    var automaticallyAdjustsVideoMirroring: Bool { get set }
    var isVideoMirroringSupported: Bool { get }
    var isVideoMirrored: Bool { get set }
}

@available(iOS 17.0, *)
protocol CameraDataOutputRotationConnectionConfiguring: CameraDataOutputMirroringConnectionConfiguring {
    func isVideoRotationAngleSupported(_ videoRotationAngle: CGFloat) -> Bool
    var videoRotationAngle: CGFloat { get set }
}

extension AVCaptureConnection: CameraDataOutputMirroringConnectionConfiguring {}

@available(iOS 17.0, *)
extension AVCaptureConnection: CameraDataOutputRotationConnectionConfiguring {}

enum CameraDataOutputConnectionConfigurator {
    static func applyMirroring(to connection: CameraDataOutputMirroringConnectionConfiguring) {
        // Disable automatic changes before setting videoMirrored; AVFoundation
        // rejects a manual mirror assignment while automatic adjustment is on.
        connection.automaticallyAdjustsVideoMirroring = false
        if connection.isVideoMirroringSupported {
            connection.isVideoMirrored = false
        }
    }

    @available(iOS 17.0, *)
    static func applyNativeGeometry(to connection: CameraDataOutputRotationConnectionConfiguring) {
        let nativeRotationAngle: CGFloat = 0
        if connection.isVideoRotationAngleSupported(nativeRotationAngle) {
            connection.videoRotationAngle = nativeRotationAngle
        }
        applyMirroring(to: connection)
    }
}

/// Interface rotation is carried as metadata for Vision/Core Image while the
/// preview layer owns its own display orientation.
enum CameraFrameDeliveryOrientationContract {

    static func imageOrientation(for requestedOrientation: AVCaptureVideoOrientation) -> CGImagePropertyOrientation {
        CameraCoachOrientation(captureOrientation: requestedOrientation).imageOrientation
    }
}

/// Immutable preview geometry captured at the same display orientation as a
/// camera frame. The destination is the actual preview-layer size, not an
/// analysis/source-size placeholder; invalid geometry is unavailable rather
/// than normalized into a plausible crop.
struct CameraPreviewGeometry: Equatable, @unchecked Sendable {
    let destinationSize: CGSize
    let imageOrientation: CGImagePropertyOrientation
    let isMirrored: Bool

    init?(destinationSize: CGSize,
          imageOrientation: CGImagePropertyOrientation,
          isMirrored: Bool) {
        guard destinationSize.width.isFinite,
              destinationSize.height.isFinite,
              destinationSize.width > 0,
              destinationSize.height > 0 else {
            return nil
        }
        self.destinationSize = destinationSize
        self.imageOrientation = imageOrientation
        self.isMirrored = isMirrored
    }
}

enum CameraLifecycleState: Equatable, Sendable {
    case idle
    case starting
    case running
    case stopping
    case failed(CameraManagerError)
}

enum CameraConfigurationState: Equatable, Sendable {
    case unconfigured
    case configured
}

protocol CameraSessionRunner: AnyObject {
    var isRunning: Bool { get }
    func startRunning()
    func stopRunning()
}

final class AVCaptureSessionRunner: CameraSessionRunner {
    private let session: AVCaptureSession

    init(session: AVCaptureSession) {
        self.session = session
    }

    var isRunning: Bool {
        session.isRunning
    }

    func startRunning() {
        session.startRunning()
    }

    func stopRunning() {
        session.stopRunning()
    }
}

enum CameraManagerTestConfiguration {
    case ready
#if DEBUG
    case readyWithLens(CameraLens)
#endif
    case failure(CameraManagerError)
}

final class CameraManager: NSObject, @unchecked Sendable {
    let sourceOwnerID = UUID()
    private let recordingBridge = CameraRecordingCaptureBridge()
    private var recordingAudioRequested = false // sessionQueue
    private let session: AVCaptureSession
    private let videoOutput: AVCaptureVideoDataOutput
    /// M9-013: optional audio tap for the truthful meter. Attached only when
    /// microphone permission is granted; detached with the same lifecycle as
    /// the video delegate so no stale audio state survives stop/release.
    private let audioMeterOutput = AVCaptureAudioDataOutput()
    private let audioMeterQueue = DispatchQueue(label: "CameraManager.AudioMeter")
    private let audioMeterLock = NSLock()
    private var storedAudioLevel: Float?
    private var acceptsAudioMeterSamples = false // audioMeterLock
    private var audioMeterAttached = false
    private var audioMeterInput: AVCaptureDeviceInput?
    private var audioMeterRequested = false
    private let sessionQueue = DispatchQueue(label: "CameraManager.Session")
    private let videoOutputQueue = DispatchQueue(label: "CameraManager.VideoOutput")
    private let videoOutputQueueKey = DispatchSpecificKey<Void>()

    private let scheduler: RealtimeScheduler
    private let thermalGovernor: ThermalGovernor
    private let motionGate: MotionGate
    private let sessionRunner: CameraSessionRunner
    private let testConfiguration: CameraManagerTestConfiguration?
    private let notificationCenter: NotificationCenter
    private var notificationTokens: [NSObjectProtocol] = []
    private let failureSubject = PassthroughSubject<CameraManagerError, Never>()
    private let proControlsSubject = CurrentValueSubject<CameraProControlsSnapshot?, Never>(nil)
    private var proControlDevice: CameraProControlDevice?
    private var proControlTestDevice: CameraProControlDevice?
    private struct PendingProControl {
        let id: UUID
        let deviceID: String
        let sessionGeneration: UInt64
        let captureGeneration: UInt64
        let completion: (Result<CameraProControlsSnapshot, CameraProControlError>) -> Void
    }
    private var pendingProControl: PendingProControl?

    var proControlsPublisher: AnyPublisher<CameraProControlsSnapshot?, Never> {
        proControlsSubject.eraseToAnyPublisher()
    }

    private var isConfigured = false
    private var currentInput: AVCaptureDeviceInput?
    private var currentLens: CameraLens?
    private let desiredVideoOrientationLock = NSLock()
    private var desiredVideoOrientation: AVCaptureVideoOrientation = .landscapeLeft

    private let stateLock = NSLock()
    /// Serializes re-enabling frame delivery against stop/release/failure.
    /// Never hold this lock while draining `videoOutputQueue`.
    private let captureBoundaryLock = NSLock()
    private var storedLifecycleState: CameraLifecycleState = .idle
    private var storedConfigurationState: CameraConfigurationState = .unconfigured
    private var storedLifecycleError: CameraManagerError?
    private var configurationCount = 0
    /// M1-003: session generation fences start against stop/release.
    /// stop/release bump it synchronously at call time; a start block
    /// dropped behind a newer generation resumes cancelled instead of
    /// reviving capture after teardown. The serial sessionQueue already
    /// orders execution; this token makes staleness explicit and testable,
    /// and is the shared mechanism for lens/orientation fencing (M1-006).
    private var storedSessionGeneration: UInt64 = 0
    /// Capture-side epoch for the input/lens that produced a frame. This is
    /// intentionally distinct from `storedSessionGeneration` (lifecycle
    /// fencing) and from AnalysisPipeline's lifecycle generation.
    private var storedCaptureGeneration: UInt64 = 0

    private let availableLensesLock = NSLock()
    private var storedAvailableLenses: [CameraLens] = []

    private let activeLensLock = NSLock()
    private var storedActiveLens: CameraLens?

    /// Preview-layer geometry is written by PreviewView only after its
    /// connection and bounds are real. The capture boundary lock makes a
    /// geometry update and a frame provenance snapshot mutually exclusive.
    private let previewGeometryLock = NSLock()
    private var storedPreviewGeometry: CameraPreviewGeometry?
#if DEBUG
    private var previewGeometryMutationsForTestingStorage = 0
#endif

    private let lensDescriptorsLock = NSLock()
    private var storedLensDescriptors: [CameraLens: CameraLensDescriptor] = [:]

    private let frameDeliveryLock = NSLock()
    private var frameDeliveryEnabled = false
#if DEBUG
    /// Deterministic race seam used only by lifecycle tests.
    var beforeFrameDeliveryEnableForTesting: (() -> Void)?
#endif

    var captureSession: AVCaptureSession { session }

    var failurePublisher: AnyPublisher<CameraManagerError, Never> {
        failureSubject.eraseToAnyPublisher()
    }

    var lifecycleState: CameraLifecycleState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedLifecycleState
    }

    var configurationState: CameraConfigurationState {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedConfigurationState
    }

    var lifecycleError: CameraManagerError? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedLifecycleError
    }

    var availableLenses: [CameraLens] {
        availableLensesLock.lock()
        defer { availableLensesLock.unlock() }
        return storedAvailableLenses
    }

    /// Manager-owned physical descriptors stay deduplicated with the lens
    /// inventory. Optional display metadata is only populated when measured
    /// by a device integration; the default physical labels remain WIDE,
    /// ULTRA, and TELE.
    var availableLensDescriptors: [CameraLensDescriptor] {
        let lenses = availableLenses
        lensDescriptorsLock.lock()
        defer { lensDescriptorsLock.unlock() }
        return lenses.compactMap { storedLensDescriptors[$0] ?? $0.descriptor }
    }

    /// Thread-safe projection of the actual input selected on the session
    /// queue. ViewModels read this only after start/resume completes.
    var activeLens: CameraLens? {
        activeLensLock.lock()
        defer { activeLensLock.unlock() }
        return storedActiveLens
    }

    var activeLensDescriptor: CameraLensDescriptor? {
        guard let activeLens else { return nil }
        lensDescriptorsLock.lock()
        defer { lensDescriptorsLock.unlock() }
        return storedLensDescriptors[activeLens] ?? activeLens.descriptor
    }

    /// Updates the manager-owned preview geometry. A nil value means that the
    /// preview is not currently measurable (for example, no window or zero
    /// bounds), so subject-bound verification must not guess a transform.
    func updatePreviewGeometry(_ geometry: CameraPreviewGeometry?) {
#if DEBUG
        beforePreviewGeometryBoundaryForTesting?()
#endif
        captureBoundaryLock.lock()
        defer { captureBoundaryLock.unlock() }
        previewGeometryLock.lock()
        defer { previewGeometryLock.unlock() }
        guard storedPreviewGeometry != geometry else { return }
        storedPreviewGeometry = geometry
#if DEBUG
        previewGeometryMutationsForTestingStorage += 1
#endif
    }

    func clearPreviewGeometry() {
        updatePreviewGeometry(nil)
    }

#if DEBUG
    var previewGeometryForTesting: CameraPreviewGeometry? {
        previewGeometrySnapshot()
    }

    var previewGeometryMutationsForTesting: Int {
        captureBoundaryLock.lock()
        defer { captureBoundaryLock.unlock() }
        return previewGeometryMutationsForTestingStorage
    }

    /// Deterministic race seam used only by lifecycle tests.
    var beforePreviewGeometryBoundaryForTesting: (() -> Void)?
#endif

    init(scheduler: RealtimeScheduler,
         thermalGovernor: ThermalGovernor,
         motionGate: MotionGate,
         notificationCenter: NotificationCenter = .default) {
        let session = AVCaptureSession()
        self.session = session
        self.videoOutput = AVCaptureVideoDataOutput()
        self.scheduler = scheduler
        self.thermalGovernor = thermalGovernor
        self.motionGate = motionGate
        self.sessionRunner = AVCaptureSessionRunner(session: session)
        self.testConfiguration = nil
        self.notificationCenter = notificationCenter
        session.automaticallyConfiguresApplicationAudioSession = false
        super.init()
        videoOutputQueue.setSpecific(key: videoOutputQueueKey, value: ())
        installSessionObservers()
    }

    init(scheduler: RealtimeScheduler,
         thermalGovernor: ThermalGovernor,
         motionGate: MotionGate,
         sessionRunner: CameraSessionRunner,
         configuration: CameraManagerTestConfiguration,
         session: AVCaptureSession = AVCaptureSession(),
         notificationCenter: NotificationCenter = .default,
         proControlDevice: CameraProControlDevice? = nil) {
        self.session = session
        self.videoOutput = AVCaptureVideoDataOutput()
        self.scheduler = scheduler
        self.thermalGovernor = thermalGovernor
        self.motionGate = motionGate
        self.sessionRunner = sessionRunner
        self.testConfiguration = configuration
        self.proControlTestDevice = proControlDevice
        self.notificationCenter = notificationCenter
        session.automaticallyConfiguresApplicationAudioSession = false
        super.init()
        videoOutputQueue.setSpecific(key: videoOutputQueueKey, value: ())
        installSessionObservers()
    }

    deinit {
        notificationTokens.forEach(notificationCenter.removeObserver)
    }

    func startAndWait() async throws {
        let generation = currentSessionGeneration()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraManagerError.startFailed)
                    return
                }
                guard self.isSessionGenerationCurrent(generation) else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                do {
                    try self.startOnSessionQueue(generation: generation)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopAndWait() async {
        closeFrameDeliveryBoundary(advanceSessionGeneration: true)
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.stopOnSessionQueue()
                continuation.resume()
            }
        }
    }

    /// Releases the current configuration. A later start reuses this session object and
    /// reconfigures its input/output exactly once before starting it again.
    func releaseAndWait() async {
        closeFrameDeliveryBoundary(advanceSessionGeneration: true)
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.releaseOnSessionQueue()
                continuation.resume()
            }
        }
    }

    /// M1-003 generation fence accessors. Lock-guarded; safe from any thread.
    /// `sessionGenerationForTesting` is the only read path outside the manager.
    var sessionGenerationForTesting: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedSessionGeneration
    }

    private func currentSessionGeneration() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedSessionGeneration
    }

    private func bumpSessionGeneration() {
        stateLock.lock()
        storedSessionGeneration &+= 1
        stateLock.unlock()
    }

    /// M2-023: the camera epoch changes whenever capture ownership changes.
    /// Never allow wraparound to turn a known generation into the unknown
    /// sentinel (zero).
    private func advanceCaptureGeneration() {
        stateLock.lock()
        storedCaptureGeneration = storedCaptureGeneration == .max
            ? 1
            : storedCaptureGeneration &+ 1
        stateLock.unlock()
    }

    private func currentCaptureGeneration() -> UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedCaptureGeneration
    }

    private func previewGeometrySnapshot() -> CameraPreviewGeometry? {
        previewGeometryLock.lock()
        defer { previewGeometryLock.unlock() }
        return storedPreviewGeometry
    }

    private struct FrameProvenanceSnapshot {
        let orientation: CGImagePropertyOrientation
        let lensID: String?
        let previewGeometry: CameraPreviewGeometry?
        let captureGeneration: UInt64
        let sessionGeneration: UInt64
    }

    /// Takes one capture-bound provenance snapshot. It is intentionally a
    /// lock-only operation: no pixel analysis or UI work may happen under the
    /// capture boundary.
    private func frameProvenanceSnapshot() -> FrameProvenanceSnapshot? {
        captureBoundaryLock.lock()
        defer { captureBoundaryLock.unlock() }
        guard isFrameDeliveryEnabled() else { return nil }

        let requestedOrientation = desiredVideoOrientationSnapshot()
        let imageOrientation = CameraFrameDeliveryOrientationContract.imageOrientation(
            for: requestedOrientation
        )
        let previewGeometry = previewGeometrySnapshot()
            .flatMap { $0.imageOrientation == imageOrientation ? $0 : nil }
        return FrameProvenanceSnapshot(
            orientation: imageOrientation,
            lensID: activeLensSnapshot()?.rawValue,
            previewGeometry: previewGeometry,
            captureGeneration: currentCaptureGeneration(),
            sessionGeneration: currentSessionGeneration()
        )
    }

    private func activeLensSnapshot() -> CameraLens? {
        activeLensLock.lock()
        defer { activeLensLock.unlock() }
        return storedActiveLens
    }

    /// M2-023 test visibility for the camera-owned provenance epoch.
    var captureGenerationForTesting: UInt64 {
        currentCaptureGeneration()
    }

    private func isSessionGenerationCurrent(_ generation: UInt64) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedSessionGeneration == generation
    }

    /// Backgrounding can happen without AVFoundation posting an interruption
    /// notification (notably in simulator-driven lifecycle tests). Keep it on
    /// the same synchronous frame-gate/failure boundary as native callbacks.
    func reportSessionInterrupted() {
        handleSessionFailure(.sessionInterrupted)
    }

    @discardableResult
    func register(consumer: FrameConsumer,
                  priority: SchedulerPriority,
                  targetFrequency: Double,
                  requiresStability: Bool = false) -> UUID {
        scheduler.register(consumer: consumer,
                           priority: priority,
                           targetFrequency: targetFrequency,
                           requiresStability: requiresStability)
    }

    func unregister(id: UUID) {
        scheduler.unregister(id: id)
    }

    func drainSchedulerAndWait() async {
        await scheduler.drainAndWait()
    }

    private func startOnSessionQueue(generation: UInt64) throws {
        if case let .failed(error) = lifecycleState,
           error == .sessionInterrupted || error == .runtimeError {
            throw error
        }

        if sessionRunner.isRunning, isConfigured {
            if !isFrameDeliveryEnabled(), pendingProControl == nil {
                guard attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: generation) else {
                    try handleRejectedStartAttachment(generation: generation)
                    return
                }
            }
            if let failure = finishStartTransitionOnSessionQueue() {
                try stopAndThrowStartFailure(failure)
            }
            publishProControlsOnSessionQueue()
            return
        }

        if sessionRunner.isRunning {
            sessionRunner.stopRunning()
        }

        setLifecycleState(.starting,
                          configuration: isConfigured ? .configured : .unconfigured)

        if !isConfigured {
            do {
                try configureSession()
            } catch let error as CameraManagerError {
                disableDeliveryAndDetachDelegate()
                setLifecycleState(.failed(error), configuration: .unconfigured, error: error)
                throw error
            } catch {
                let typedError = CameraManagerError.startFailed
                disableDeliveryAndDetachDelegate()
                setLifecycleState(.failed(typedError), configuration: .unconfigured, error: typedError)
                throw typedError
            }
        }

        guard attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: generation) else {
            try handleRejectedStartAttachment(generation: generation)
            return
        }
        sessionRunner.startRunning()

        guard sessionRunner.isRunning else {
            disableDeliveryAndDetachDelegate()
            drainVideoOutputQueue()
            let error = CameraManagerError.startFailed
            setLifecycleState(.failed(error),
                              configuration: isConfigured ? .configured : .unconfigured,
                              error: error)
            throw error
        }
        guard isSessionGenerationCurrent(generation) else {
            disableDeliveryAndDetachDelegate()
            sessionRunner.stopRunning()
            drainVideoOutputQueue()
            return
        }

        if let failure = finishStartTransitionOnSessionQueue() {
            try stopAndThrowStartFailure(failure)
        }
        publishProControlsOnSessionQueue()
    }

    private func stopOnSessionQueue() {
        recordingAudioRequested = false
        invalidateProControlsOnSessionQueue()
        let previousError = lifecycleError
        let hasWorkToFence = sessionRunner.isRunning || isConfigured || isFrameDeliveryEnabled()

        guard hasWorkToFence || previousError != nil else {
            setLifecycleState(.idle, configuration: .unconfigured)
            return
        }

        setLifecycleState(.stopping,
                          configuration: isConfigured ? .configured : .unconfigured)
        disableDeliveryAndDetachDelegate()

        if sessionRunner.isRunning {
            sessionRunner.stopRunning()
        }

        drainVideoOutputQueue()

        if let previousError, !isConfigured {
            setLifecycleState(.failed(previousError),
                              configuration: .unconfigured,
                              error: previousError)
        } else {
            setLifecycleState(.idle,
                              configuration: isConfigured ? .configured : .unconfigured)
        }
    }

    private func releaseOnSessionQueue() {
        invalidateProControlsOnSessionQueue()
        proControlDevice = nil
        audioMeterRequested = false
        recordingAudioRequested = false
        let hasResources = sessionRunner.isRunning
            || isConfigured
            || isFrameDeliveryEnabled()
            || lifecycleError != nil
            || !session.inputs.isEmpty
            || !session.outputs.isEmpty
        guard hasResources else {
            setLifecycleState(.idle, configuration: .unconfigured)
            return
        }

        setLifecycleState(.stopping,
                          configuration: isConfigured ? .configured : .unconfigured)
        disableDeliveryAndDetachDelegate()

        if sessionRunner.isRunning {
            sessionRunner.stopRunning()
        }

        drainVideoOutputQueue()

        session.beginConfiguration()
        for output in session.outputs {
            session.removeOutput(output)
        }
        for input in session.inputs {
            session.removeInput(input)
        }
        session.commitConfiguration()

        currentInput = nil
        setCurrentLens(nil)
        clearPreviewGeometry()
        isConfigured = false
        setAvailableLenses([])
        setLensDescriptors([:])
        setLifecycleState(.idle, configuration: .unconfigured)
    }

    private func installSessionObservers() {
        let notifications: [(Notification.Name, CameraManagerError)] = [
            (AVCaptureSession.wasInterruptedNotification, .sessionInterrupted),
            (AVCaptureSession.runtimeErrorNotification, .runtimeError)
        ]
        notificationTokens = notifications.map { name, error in
            notificationCenter.addObserver(
                forName: name,
                object: session,
                queue: nil
            ) { [weak self] notification in
                guard let self,
                      notification.object as AnyObject? === self.session else { return }
                self.handleSessionFailure(error)
            }
        }
    }

    private func handleSessionFailure(_ error: CameraManagerError) {
        guard let claimedError = claimSessionFailure(error) else { return }

        // Close the lock-backed gate before publishing so a callback already
        // queued on the output queue cannot dispatch more analysis after this
        // boundary.
        closeFrameDeliveryBoundary(advanceSessionGeneration: false)
        drainVideoOutputQueue()
        failureSubject.send(claimedError)
    }

    private func closeFrameDeliveryBoundary(advanceSessionGeneration: Bool) {
        recordingBridge.closeAdmission()
        captureBoundaryLock.lock()
        // This boundary is callable off sessionQueue. Capture graph mutations
        // (including the microphone input) stay in queued stop/release work.
        setFrameDeliveryEnabled(false)
        videoOutput.setSampleBufferDelegate(nil, queue: videoOutputQueue)
        clearAudioLevel()
        if advanceSessionGeneration {
            bumpSessionGeneration()
        }
        advanceCaptureGeneration()
        captureBoundaryLock.unlock()
    }

    private func claimSessionFailure(_ error: CameraManagerError) -> CameraManagerError? {
        stateLock.lock()
        switch storedLifecycleState {
        case .starting, .running:
            storedLifecycleState = .failed(error)
            storedLifecycleError = error
            stateLock.unlock()
            return error
        case .idle, .stopping, .failed:
            stateLock.unlock()
            return nil
        }
    }

    private func finishStartTransitionOnSessionQueue() -> CameraManagerError? {
        stateLock.lock()
        defer { stateLock.unlock() }

        switch storedLifecycleState {
        case .starting, .running:
            storedLifecycleState = .running
            storedConfigurationState = .configured
            storedLifecycleError = nil
            return nil
        case .failed(let error):
            return storedLifecycleError ?? error
        case .idle, .stopping:
            return storedLifecycleError ?? .startFailed
        }
    }

    private func handleRejectedStartAttachment(generation: UInt64) throws {
        stateLock.lock()
        // Stop/release may deliberately supersede an in-flight start before
        // attachment. Keep that cancellation distinct from a failed current start.
        guard storedSessionGeneration == generation else {
            stateLock.unlock()
            return
        }

        let failure: CameraManagerError
        if case let .failed(error) = storedLifecycleState {
            failure = storedLifecycleError ?? error
        } else {
            failure = storedLifecycleError ?? .startFailed
            storedLifecycleState = .failed(failure)
            storedLifecycleError = failure
        }
        stateLock.unlock()

        // A runtime/interruption notification can win before the runner starts.
        // Surface its typed failure instead of completing startAndWait successfully.
        try stopAndThrowStartFailure(failure)
    }

    private func stopAndThrowStartFailure(_ error: CameraManagerError) throws -> Never {
        disableDeliveryAndDetachDelegate()
        if sessionRunner.isRunning {
            sessionRunner.stopRunning()
        }
        drainVideoOutputQueue()
        throw error
    }

    private func configureSession() throws {
        if let testConfiguration {
            switch testConfiguration {
            case .ready:
                try configureReadyTestSession()
#if DEBUG
            case .readyWithLens(let lens):
                try configureReadyTestSession(lens: lens)
#endif
            case .failure(let error):
                throw error
            }
            return
        }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        var input: AVCaptureDeviceInput?
        var inputWasAdded = false

        do {
            session.sessionPreset = .high

            discoverAvailableLenses()

            guard let camera = findCamera(for: .wide) else {
                throw CameraManagerError.noWideCamera
            }

            do {
                input = try AVCaptureDeviceInput(device: camera)
            } catch {
                throw CameraManagerError.inputConstructionFailed
            }

            guard let input, session.canAddInput(input) else {
                throw CameraManagerError.inputAddFailed
            }

            session.addInput(input)
            inputWasAdded = true

            configureVideoOutput()

            guard session.canAddOutput(videoOutput) else {
                throw CameraManagerError.outputAddFailed
            }
            session.addOutput(videoOutput)

            configureVideoConnection()
            currentInput = input
            setCurrentLens(.wide)
            advanceCaptureGeneration()
            isConfigured = true
            markConfigured()
        } catch {
            if inputWasAdded, let input {
                session.removeInput(input)
            }
            currentInput = nil
            setCurrentLens(nil)
            setAvailableLenses([])
            setLensDescriptors([:])
            isConfigured = false
            markUnconfigured()
            throw error
        }
    }

    private func configureReadyTestSession(lens: CameraLens = .wide) throws {
        session.beginConfiguration()
        configureVideoOutput()
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        currentInput = nil
        // The fixture owns one installed capture input. Its readback and
        // descriptors must name that same input; mutating only the view model
        // does not represent a hardware lens selection.
        setCurrentLens(lens)
        setAvailableLenses([lens])
        setLensDescriptors([lens: lens.descriptor])
        // Mirror production configuration: the ready fixture represents one
        // installed capture input, so its first delivered frames own epoch 1.
        advanceCaptureGeneration()
        isConfigured = true
        markConfigured()
        session.commitConfiguration()
    }

    private func configureVideoOutput() {
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
    }

    private func configureVideoConnection() {
        if let connection = videoOutput.connection(with: .video) {
            connection.preferredVideoStabilizationMode = .cinematicExtended
            if #available(iOS 17.0, *) {
                CameraDataOutputConnectionConfigurator.applyNativeGeometry(to: connection)
            } else {
                CameraDataOutputConnectionConfigurator.applyMirroring(to: connection)
            }
        }
    }

    @discardableResult
    private func attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: UInt64) -> Bool {
#if DEBUG
        beforeFrameDeliveryEnableForTesting?()
#endif
        captureBoundaryLock.lock()
        defer { captureBoundaryLock.unlock() }
        guard isSessionGenerationCurrent(expectedSessionGeneration) else { return false }
        switch lifecycleState {
        case .starting, .running:
            break
        case .idle, .stopping, .failed:
            return false
        }
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        attachAudioMeterIfPermitted()
        setFrameDeliveryEnabled(true)
        return true
    }

    /// M9-013: attaches the audio tap only when the microphone is granted.
    /// Called on the session queue alongside the video delegate attach, so
    /// the meter lifecycle matches frame delivery exactly.
    private func attachAudioMeterIfPermitted() {
        guard audioMeterRequested || recordingAudioRequested, testConfiguration == nil,
              AVAudioApplication.shared.recordPermission == .granted else {
            detachAudioMeter()
            return
        }
        if audioMeterAttached {
            audioMeterLock.lock()
            acceptsAudioMeterSamples = audioMeterRequested
            if !audioMeterRequested { storedAudioLevel = nil }
            audioMeterLock.unlock()
            return
        }
        guard let microphone = AVCaptureDevice.default(for: .audio),
              let input = try? AVCaptureDeviceInput(device: microphone) else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else { return }
        session.addInput(input)
        guard session.canAddOutput(audioMeterOutput) else {
            session.removeInput(input)
            return
        }
        audioMeterInput = input
        session.addOutput(audioMeterOutput)
        audioMeterLock.lock()
        acceptsAudioMeterSamples = audioMeterRequested
        audioMeterLock.unlock()
        audioMeterOutput.setSampleBufferDelegate(self, queue: audioMeterQueue)
        audioMeterAttached = true
    }

    private func detachAudioMeter() {
        audioMeterLock.lock()
        acceptsAudioMeterSamples = false
        storedAudioLevel = nil
        audioMeterLock.unlock()
        let hasAudioGraph = audioMeterAttached || audioMeterInput != nil
        if hasAudioGraph { session.beginConfiguration() }
        defer { if hasAudioGraph { session.commitConfiguration() } }
        if audioMeterAttached {
            audioMeterOutput.setSampleBufferDelegate(nil, queue: nil)
            session.removeOutput(audioMeterOutput)
            audioMeterAttached = false
        }
        if let input = audioMeterInput {
            session.removeInput(input)
            audioMeterInput = nil
        }
        clearAudioLevel()
    }

    private func clearAudioLevel() {
        audioMeterLock.lock()
        storedAudioLevel = nil
        audioMeterLock.unlock()
    }

    private func disableDeliveryAndDetachDelegate() {
        setFrameDeliveryEnabled(false)
        videoOutput.setSampleBufferDelegate(nil, queue: videoOutputQueue)
        detachAudioMeter()
    }

    private func drainVideoOutputQueue() {
        guard DispatchQueue.getSpecific(key: videoOutputQueueKey) == nil else { return }
        videoOutputQueue.sync { }
    }

    private func setFrameDeliveryEnabled(_ enabled: Bool) {
        frameDeliveryLock.lock()
        frameDeliveryEnabled = enabled
        frameDeliveryLock.unlock()
    }

    private func isFrameDeliveryEnabled() -> Bool {
        frameDeliveryLock.lock()
        defer { frameDeliveryLock.unlock() }
        return frameDeliveryEnabled
    }

    private func setLifecycleState(_ state: CameraLifecycleState,
                                   configuration: CameraConfigurationState? = nil,
                                   error: CameraManagerError? = nil) {
        stateLock.lock()
        storedLifecycleState = state
        if let configuration {
            storedConfigurationState = configuration
        }
        storedLifecycleError = error
        stateLock.unlock()
    }

    private func markConfigured() {
        stateLock.lock()
        storedConfigurationState = .configured
        configurationCount += 1
        stateLock.unlock()
    }

    private func markUnconfigured() {
        stateLock.lock()
        storedConfigurationState = .unconfigured
        stateLock.unlock()
    }

    private func setAvailableLenses(_ lenses: [CameraLens]) {
        availableLensesLock.lock()
        storedAvailableLenses = lenses
        availableLensesLock.unlock()
    }

    private func setLensDescriptors(_ descriptors: [CameraLens: CameraLensDescriptor]) {
        lensDescriptorsLock.lock()
        storedLensDescriptors = descriptors
        lensDescriptorsLock.unlock()
    }

    private func setCurrentLens(_ lens: CameraLens?) {
        currentLens = lens
        activeLensLock.lock()
        storedActiveLens = lens
        activeLensLock.unlock()
    }
    
    private func discoverAvailableLenses() {
        var discovered: [CameraLens] = []
        var descriptors: [CameraLens: CameraLensDescriptor] = [:]
        let wideFieldOfView = findCamera(for: .wide)?.activeFormat.videoFieldOfView
        for lens in CameraLens.allCases where findCamera(for: lens) != nil {
            if !discovered.contains(lens) {
                discovered.append(lens)
                if let device = findCamera(for: lens) {
                    let metadata = truthfulMagnification(
                        for: device,
                        relativeToFieldOfView: wideFieldOfView
                    )
                    descriptors[lens] = CameraLensDescriptor(
                        lens: lens,
                        identifier: lens.rawValue,
                        displayName: lens.displayName,
                        physicalDeviceType: String(describing: lens.deviceType),
                        displayMetadata: metadata
                    )
                }
            }
        }
        setAvailableLenses(discovered)
        setLensDescriptors(descriptors)
    }

    private func truthfulMagnification(
        for device: AVCaptureDevice,
        relativeToFieldOfView referenceFieldOfView: Float?
    ) -> CameraLensDisplayMetadata? {
        guard let referenceFieldOfView,
              referenceFieldOfView > 0,
              device.activeFormat.videoFieldOfView > 0 else { return nil }
        let referenceAngle = Double(referenceFieldOfView) * .pi / 360.0
        let deviceAngle = Double(device.activeFormat.videoFieldOfView) * .pi / 360.0
        let referenceTangent = tan(referenceAngle)
        let deviceTangent = tan(deviceAngle)
        guard referenceTangent > 0,
              deviceTangent > 0,
              referenceTangent.isFinite,
              deviceTangent.isFinite else { return nil }
        let magnification = referenceTangent / deviceTangent
        guard magnification.isFinite, magnification > 0 else { return nil }
        return .truthfulMagnification(magnification)
    }
    
    private func findCamera(for lens: CameraLens) -> AVCaptureDevice? {
        return AVCaptureDevice.default(lens.deviceType, for: .video, position: .back)
    }
    
    func proControlsSnapshotAndWait() async -> CameraProControlsSnapshot? {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                continuation.resume(returning: self?.publishProControlsOnSessionQueue())
            }
        }
    }

    @discardableResult
    private func publishProControlsOnSessionQueue() -> CameraProControlsSnapshot? {
        // A native setter may expose its requested value before its completion
        // timestamp. Retain the last acknowledged observation while applying.
        if pendingProControl != nil { return proControlsSubject.value }
        guard isConfigured, lifecycleState == .running else {
            proControlsSubject.send(nil)
            return nil
        }
        if proControlDevice == nil {
            if let test = proControlTestDevice {
                proControlDevice = test
            } else if let device = currentInput?.device {
                proControlDevice = AVCaptureProControlDevice(device: device, sessionQueue: sessionQueue)
            }
        }
        let snapshot = proControlDevice?.snapshot(generation: currentCaptureGeneration())
        if proControlsSubject.value != snapshot { proControlsSubject.send(snapshot) }
        return snapshot
    }

    func applyProControl(
        _ command: CameraProControlCommand,
        expectedDeviceID: String,
        expectedCaptureGeneration: UInt64
    ) async -> Result<CameraProControlsSnapshot, CameraProControlError> {
        await applyProControl(command, expectedDeviceID: expectedDeviceID,
                              expectedCaptureGeneration: expectedCaptureGeneration,
                              recordingPreparationLease: nil)
    }

    private func applyProControl(
        _ command: CameraProControlCommand,
        expectedDeviceID: String,
        expectedCaptureGeneration: UInt64,
        recordingPreparationLease: CameraRecordingCaptureLease?
    ) async -> Result<CameraProControlsSnapshot, CameraProControlError> {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.isConfigured, self.lifecycleState == .running else {
                    continuation.resume(returning: .failure(.unavailable))
                    return
                }
                guard self.pendingProControl == nil else {
                    continuation.resume(returning: .failure(.busy))
                    return
                }
                if let recordingPreparationLease {
                    guard self.recordingBridge.validates(recordingPreparationLease,
                              sessionGeneration: self.currentSessionGeneration()) else {
                        continuation.resume(returning: .failure(.stale))
                        return
                    }
                } else if command.changesFormat, self.recordingBridge.isReserved {
                    continuation.resume(returning: .failure(.busy))
                    return
                }
                guard let state = self.publishProControlsOnSessionQueue(),
                      state.deviceID == expectedDeviceID,
                      state.captureGeneration == expectedCaptureGeneration,
                      let device = self.proControlDevice else {
                    continuation.resume(returning: .failure(.stale))
                    return
                }
                if command.changesFormat && !self.session.canSetSessionPreset(.inputPriority) {
                    continuation.resume(returning: .failure(.unsupported))
                    return
                }
                let operation = UUID()
                // Preview continues, but analysis must not compare frames
                // across changing exposure/focus/format under one generation.
                self.captureBoundaryLock.lock()
                guard self.currentCaptureGeneration() == expectedCaptureGeneration,
                      self.lifecycleState == .running else {
                    self.captureBoundaryLock.unlock()
                    continuation.resume(returning: .failure(.stale))
                    return
                }
                self.setFrameDeliveryEnabled(false)
                self.advanceCaptureGeneration()
                self.pendingProControl = PendingProControl(
                    id: operation, deviceID: device.deviceID,
                    sessionGeneration: self.currentSessionGeneration(),
                    captureGeneration: self.currentCaptureGeneration(),
                    completion: { continuation.resume(returning: $0) }
                )
                self.captureBoundaryLock.unlock()
                self.drainVideoOutputQueue()
                if command.changesFormat {
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .inputPriority
                }
                device.apply(command) { [weak self] result in
                    self?.sessionQueue.async { [weak self] in
                        self?.completeProControlOnSessionQueue(operation, result: result)
                    }
                }
                if command.changesFormat { self.session.commitConfiguration() }
                self.sessionQueue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    self?.completeProControlOnSessionQueue(operation, result: .failure(.applicationTimeout))
                }
            }
        }
    }

    private func completeProControlOnSessionQueue(
        _ operation: UUID, result: Result<Void, CameraProControlError>
    ) {
        guard let pending = pendingProControl, pending.id == operation else { return }
        pendingProControl = nil
        proControlDevice?.cancelPending()
        guard isSessionGenerationCurrent(pending.sessionGeneration),
              currentCaptureGeneration() == pending.captureGeneration,
              lifecycleState == .running,
              proControlDevice?.deviceID == pending.deviceID else {
            proControlsSubject.send(nil)
            pending.completion(.failure(.stale))
            return
        }
        let snapshot = publishProControlsOnSessionQueue()
        drainVideoOutputQueue()
        _ = attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: pending.sessionGeneration)
        switch result {
        case .success:
            if let snapshot { pending.completion(.success(snapshot)) }
            else { pending.completion(.failure(.unavailable)) }
        case .failure(let error):
            pending.completion(.failure(error))
        }
    }

    private func invalidateProControlsOnSessionQueue() {
        let pending = pendingProControl
        pendingProControl = nil
        proControlDevice?.cancelPending()
        proControlsSubject.send(nil)
        if let pending {
            if isSessionGenerationCurrent(pending.sessionGeneration), lifecycleState == .running {
                _ = attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: pending.sessionGeneration)
            }
            pending.completion(.failure(.stale))
        }
    }

    /// M9-013: current audio level (0...1 RMS) derived from actual audio
    /// buffers. Nil means unavailable: no permission, no audio path, or the
    /// capture owner is not running. No fixture animation exists in Release.
    var audioLevel: Float? {
        audioMeterLock.lock()
        defer { audioMeterLock.unlock() }
        return storedAudioLevel
    }

    /// Meter helper validates actual PCM format and channel/buffer layout.
    private func updateAudioLevel(from sampleBuffer: CMSampleBuffer) {
        let level = isFrameDeliveryEnabled()
            ? CameraAudioMeterMeasurement.normalizedRMS(from: sampleBuffer) : nil
        audioMeterLock.lock()
        storedAudioLevel = acceptsAudioMeterSamples && isFrameDeliveryEnabled() ? level : nil
        audioMeterLock.unlock()
    }

    func switchLens(to lens: CameraLens) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            _ = self.switchLensOnSessionQueue(to: lens)
        }
    }

    func switchLensAndWait(to lens: CameraLens) async -> CameraLensSwitchResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<CameraLensSwitchResult, Never>) in
            sessionQueue.async { [weak self] in
                let result = self?.switchLensOnSessionQueue(to: lens)
                    ?? .failure(requestedLens: lens,
                                lastKnownActiveLens: nil,
                                reason: .notConfigured)
                continuation.resume(returning: result)
            }
        }
    }

    private func switchLensOnSessionQueue(to lens: CameraLens) -> CameraLensSwitchResult {
        guard !recordingBridge.isReserved else {
            return .failure(requestedLens: lens, lastKnownActiveLens: activeLensSnapshot(),
                            reason: .recordingInProgress)
        }
        invalidateProControlsOnSessionQueue()
        let operationGeneration = currentSessionGeneration()
        guard isConfigured,
              let oldInput = currentInput,
              let oldLens = currentLens else {
            return .failure(requestedLens: lens,
                            lastKnownActiveLens: nil,
                            reason: .notConfigured)
        }

        guard lens != oldLens else {
            return .noOp(activeLens: oldLens)
        }

        guard availableLenses.contains(lens),
              let newCamera = findCamera(for: lens) else {
            return .failure(requestedLens: lens,
                            lastKnownActiveLens: oldLens,
                            reason: .unavailable)
        }

        let newInput: AVCaptureDeviceInput
        do {
            newInput = try AVCaptureDeviceInput(device: newCamera)
        } catch {
            return .failure(requestedLens: lens,
                            lastKnownActiveLens: oldLens,
                            reason: .inputConstructionFailed)
        }

        // Quiesce the old delegate queue before changing the input epoch. A
        // callback that starts after the switch must never inherit the new
        // generation for pixels produced by the old input.
        let wasDeliveringFrames = isFrameDeliveryEnabled()
        if wasDeliveringFrames {
            disableDeliveryAndDetachDelegate()
            drainVideoOutputQueue()
        }
        guard isSessionGenerationCurrent(operationGeneration) else {
            return .failure(requestedLens: lens,
                            lastKnownActiveLens: oldLens,
                            reason: .notConfigured)
        }

        let outcome = replaceInputOnSessionQueue(oldInput: oldInput, newInput: newInput)
        switch outcome {
        case .replaced:
            currentInput = newInput
            proControlDevice = nil
            setCurrentLens(lens)
            configureVideoConnection()
            advanceCaptureGeneration()
            if wasDeliveringFrames {
                _ = attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: operationGeneration)
            }
            publishProControlsOnSessionQueue()
            return .success(activeLens: lens)
        case .restored:
            if wasDeliveringFrames {
                _ = attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: operationGeneration)
            }
            publishProControlsOnSessionQueue()
            return .failure(requestedLens: lens,
                            lastKnownActiveLens: oldLens,
                            reason: .replacementRejected)
        case .rollbackFailed:
            currentInput = nil
            setCurrentLens(nil)
            releaseOnSessionQueue()
            return .failure(requestedLens: lens,
                            lastKnownActiveLens: nil,
                            reason: .rollbackFailed)
        }
    }

    private func replaceInputOnSessionQueue(
        oldInput: AVCaptureDeviceInput,
        newInput: AVCaptureDeviceInput
    ) -> CameraInputReplacementTransaction<AVCaptureDeviceInput>.Outcome {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let transaction = CameraInputReplacementTransaction(
            oldInput: oldInput,
            newInput: newInput,
            removeInput: { [session] input in
                session.removeInput(input)
            },
            canAddInput: { [session] input in
                session.canAddInput(input)
            },
            addInput: { [session] input in
                session.addInput(input)
            }
        )
        return transaction.perform()
    }

    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async { [weak self] in
            self?.setVideoOrientationOnSessionQueue(orientation)
        }
    }

    /// Applies an orientation to the existing capture connection and waits for
    /// the session-queue mutation to finish. No capture graph or lifecycle
    /// state is recreated by this operation.
    func setVideoOrientationAndWait(_ orientation: AVCaptureVideoOrientation) async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.setVideoOrientationOnSessionQueue(orientation)
                continuation.resume()
            }
        }
    }

    /// Test/diagnostic read paired with `setVideoOrientationAndWait`.
    func videoOrientationAndWait() async -> AVCaptureVideoOrientation {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                continuation.resume(returning: self?.desiredVideoOrientationSnapshot() ?? .landscapeLeft)
            }
        }
    }

    private func setVideoOrientationOnSessionQueue(_ orientation: AVCaptureVideoOrientation) {
        guard orientation != desiredVideoOrientationSnapshot() else { return }
        let operationGeneration = currentSessionGeneration()
        let wasDeliveringFrames = isFrameDeliveryEnabled()
        if wasDeliveringFrames {
            // Recording pixels remain native and its track orientation is
            // frozen. Only analysis is drained when the preview rotates.
            if recordingBridge.isReserved { setFrameDeliveryEnabled(false) }
            else { disableDeliveryAndDetachDelegate() }
            drainVideoOutputQueue()
        }
        guard isSessionGenerationCurrent(operationGeneration) else { return }
        desiredVideoOrientationLock.lock()
        desiredVideoOrientation = orientation
        desiredVideoOrientationLock.unlock()
        if wasDeliveringFrames {
            _ = attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: operationGeneration)
        }
    }

    private func desiredVideoOrientationSnapshot() -> AVCaptureVideoOrientation {
        desiredVideoOrientationLock.lock()
        defer { desiredVideoOrientationLock.unlock() }
        return desiredVideoOrientation
    }
}

extension CameraManager: CameraRecordingCaptureSource {
    var isRecordingCaptureReserved: Bool { recordingBridge.isReserved }

    func reserveRecordingCapture() async throws -> CameraRecordingCaptureLease {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.isConfigured, self.lifecycleState == .running else {
                    continuation.resume(throwing: CameraRecordingCaptureError.cameraUnavailable)
                    return
                }
                guard self.pendingProControl == nil else {
                    continuation.resume(throwing: CameraRecordingCaptureError.proControlPending)
                    return
                }
                do {
                    continuation.resume(returning: try self.recordingBridge.reserve(
                        ownerID: self.sourceOwnerID, sessionGeneration: self.currentSessionGeneration()
                    ))
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Permission and the single active AudioSessionCoordinator lease belong
    /// to CameraCoachRecordingCoordinator. This method only prepares the
    /// manager's existing capture graph and waits for a fresh matching buffer.
    func prepareRecordingCapture(lease: CameraRecordingCaptureLease,
                                 audioMode: RecordingAudioMode) async throws -> PreparedCameraRecordingCapture {
        if audioMode == .required {
            guard AVAudioApplication.shared.recordPermission == .granted else {
                throw CameraRecordingCaptureError.microphoneDenied
            }
            try await requireOwnedRecordingAudioSession()
        }
        try Task.checkCancellation()
        let before: CameraProControlsSnapshot = try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.lifecycleState == .running,
                      self.recordingBridge.validates(lease, sessionGeneration: self.currentSessionGeneration()) else {
                    continuation.resume(throwing: CameraRecordingCaptureError.staleLease)
                    return
                }
                guard self.pendingProControl == nil else {
                    continuation.resume(throwing: CameraRecordingCaptureError.proControlPending)
                    return
                }
                guard self.session.canSetSessionPreset(.inputPriority) else {
                    continuation.resume(throwing: CameraRecordingCaptureError.formatUnavailable)
                    return
                }
                // Audio admission cannot let a session preset silently choose
                // a different video format after the take snapshot is frozen.
                self.session.beginConfiguration()
                self.session.sessionPreset = .inputPriority
                self.session.commitConfiguration()
                self.recordingAudioRequested = audioMode == .required
                self.attachAudioMeterIfPermitted()
                guard audioMode != .required || self.audioMeterAttached else {
                    self.recordingAudioRequested = false
                    self.attachAudioMeterIfPermitted()
                    continuation.resume(throwing: CameraRecordingCaptureError.audioUnavailable)
                    return
                }
                guard let snapshot = self.publishProControlsOnSessionQueue() else {
                    continuation.resume(throwing: CameraRecordingCaptureError.formatUnavailable)
                    return
                }
                continuation.resume(returning: snapshot)
            }
        }
        let selection = try CameraRecordingCapturePolicy.formatToApply(before)
        guard let formatID = selection?.id ?? before.readback.formatID else {
            throw CameraRecordingCaptureError.formatUnavailable
        }
        try Task.checkCancellation()
        // The existing serialized setter also disables automatic frame-rate
        // changes on supported iOS versions. It acknowledges actual readback
        // before any recording frame can be admitted.
        let applied = await applyProControl(.format(formatID),
            expectedDeviceID: before.deviceID,
            expectedCaptureGeneration: before.captureGeneration,
            recordingPreparationLease: lease)
        guard case .success = applied else {
            if case .failure(.stale) = applied { throw CameraRecordingCaptureError.staleLease }
            if case .failure(.busy) = applied { throw CameraRecordingCaptureError.proControlPending }
            throw CameraRecordingCaptureError.formatUnavailable
        }
        try Task.checkCancellation()
        let context: CameraRecordingCaptureBridge.Context = try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.lifecycleState == .running,
                      self.recordingBridge.validates(lease, sessionGeneration: self.currentSessionGeneration()),
                      self.pendingProControl == nil,
                      let snapshot = self.publishProControlsOnSessionQueue(),
                      snapshot.deviceID == before.deviceID,
                      snapshot.readback.formatID == formatID,
                      let fps = CameraRecordingCapturePolicy.fixedFramesPerSecond(snapshot.readback.fixedFPS),
                      snapshot.readback.width == before.readback.width,
                      snapshot.readback.height == before.readback.height else {
                    continuation.resume(throwing: CameraRecordingCaptureError.sourceChanged)
                    return
                }
                let orientation: RecordingCaptureOrientation
                switch CameraCoachOrientation(captureOrientation: self.desiredVideoOrientationSnapshot()) {
                case .portrait: orientation = .portrait
                case .portraitUpsideDown: orientation = .portraitUpsideDown
                case .landscapeLeft: orientation = .landscapeLeft
                case .landscapeRight: orientation = .landscapeRight
                }
                let transform = RecordingTrackTransformMetadata(
                    captureOrientation: orientation, isMirrored: false,
                    strategy: .preferredTransformMetadata,
                    pixelOrientationBaseline: .nativeLandscapeRight
                )
                continuation.resume(returning: CameraRecordingCaptureBridge.Context(
                    lease: lease, sessionGeneration: self.currentSessionGeneration(),
                    deviceID: snapshot.deviceID, formatID: formatID,
                    width: snapshot.readback.width, height: snapshot.readback.height,
                    fps: fps, pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                    minimumHostTimestamp: CMClockGetTime(CMClockGetHostTimeClock()).seconds,
                    trackTransform: transform, audioEnabled: audioMode == .required
                ))
            }
        }
        return try await recordingBridge.waitForFirstFrame(context: context)
    }

    func attachRecordingController(_ controller: SceneRecordingController,
                                   lease: CameraRecordingCaptureLease) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self, self.lifecycleState == .running,
                      self.recordingBridge.validates(lease, sessionGeneration: self.currentSessionGeneration()) else {
                    continuation.resume(throwing: CameraRecordingCaptureError.staleLease)
                    return
                }
                do {
                    try self.recordingBridge.attach(controller, lease: lease)
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func closeRecordingFrameAdmission(_ lease: CameraRecordingCaptureLease) async {
        recordingBridge.closeAdmission(lease)
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.drainVideoOutputQueue()
                self?.audioMeterQueue.sync { }
                continuation.resume()
            }
        }
    }

    func releaseRecordingCapture(_ lease: CameraRecordingCaptureLease) async {
        recordingBridge.closeAdmission(lease)
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self, self.recordingBridge.owns(lease) else {
                    continuation.resume()
                    return
                }
                self.drainVideoOutputQueue()
                self.audioMeterQueue.sync { }
                self.recordingBridge.release(lease)
                self.recordingAudioRequested = false
                if self.lifecycleState == .running { self.attachAudioMeterIfPermitted() }
                else { self.detachAudioMeter() }
                continuation.resume()
            }
        }
    }

    /// Called only after an explicit meter action has passed permission and
    /// activated the coordinator lease. Meter changes are unavailable during
    /// a take, so changing the microphone cannot reconfigure a live writer.
    func setRecordingAudioMeterEnabled(_ enabled: Bool) async throws {
        let generation = currentSessionGeneration()
        if enabled {
            guard AVAudioApplication.shared.recordPermission == .granted else {
                throw CameraRecordingCaptureError.microphoneDenied
            }
            try await requireOwnedRecordingAudioSession()
        }
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self, self.isSessionGenerationCurrent(generation),
                      !enabled || self.lifecycleState == .running else {
                    continuation.resume(throwing: CameraRecordingCaptureError.cameraUnavailable)
                    return
                }
                guard !self.recordingBridge.isReserved else {
                    continuation.resume(throwing: CameraRecordingCaptureError.recordingInProgress)
                    return
                }
                self.audioMeterRequested = enabled
                self.attachAudioMeterIfPermitted()
                if enabled && !self.audioMeterAttached {
                    self.audioMeterRequested = false
                    continuation.resume(throwing: CameraRecordingCaptureError.audioUnavailable)
                } else { continuation.resume() }
            }
        }
    }

    private func requireOwnedRecordingAudioSession() async throws {
        guard await AudioSessionCoordinator.shared.activeRecordingLease(ownerID: sourceOwnerID) != nil else {
            throw CameraRecordingCaptureError.audioUnavailable
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        // The one microphone output serves an explicitly requested meter and
        // the current sound-required take. It never enters image analysis.
        if output === audioMeterOutput {
            recordingBridge.forwardAudio(sampleBuffer,
                synchronizationClock: session.synchronizationClock,
                sessionGeneration: currentSessionGeneration())
            updateAudioLevel(from: sampleBuffer)
            return
        }
        let capturedAt = Date()
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // The callback's wall-clock arrival time is useful only for freshness;
        // it cannot establish sample order. A real camera frame must carry a
        // numeric presentation timestamp through the analysis boundary.
        guard timestamp.isNumeric else { return }
        // Recording admission precedes the analysis/thermal gates. Applying
        // EV/focus/WB closes an analysis epoch while the native movie continues.
        if recordingBridge.isReserved, let clock = session.synchronizationClock {
            let hostTime = CMSyncConvertTime(timestamp, from: clock, to: CMClockGetHostTimeClock())
            if hostTime.isNumeric, hostTime.seconds.isFinite,
               recordingBridge.forwardVideo(pixelBuffer, hostTimestamp: hostTime.seconds,
                    sessionGeneration: currentSessionGeneration()) == .sourceChanged {
                handleSessionFailure(.runtimeError)
                return
            }
        }
        guard let provenance = frameProvenanceSnapshot() else { return }
        let orientation = provenance.orientation
        let captureGeneration = provenance.captureGeneration
        let sessionGeneration = provenance.sessionGeneration
        let motionSnapshot = motionGate.snapshot()
        let context = FrameContext(pixelBuffer: pixelBuffer,
                                   timestamp: timestamp,
                                   orientation: orientation,
                                   lensID: provenance.lensID,
                                   previewGeometry: provenance.previewGeometry,
                                   isStable: motionSnapshot.isStable,
                                   shakeLevel: motionSnapshot.shakeLevel,
                                   motionState: motionSnapshot.motionState,
                                   capturedAt: capturedAt,
                                   captureGeneration: captureGeneration,
                                   sessionGeneration: sessionGeneration)

        let budget = thermalGovernor.nextBudget()

        frameDeliveryLock.lock()
        guard frameDeliveryEnabled,
              captureGeneration == currentCaptureGeneration(),
              sessionGeneration == currentSessionGeneration() else {
            frameDeliveryLock.unlock()
            return
        }
        scheduler.dispatch(context: context, budget: budget)
        frameDeliveryLock.unlock()
    }
}

#if DEBUG
extension CameraManager {
    var frameDeliveryEnabledForTesting: Bool {
        isFrameDeliveryEnabled()
    }

    var configurationCountForTesting: Int {
        stateLock.lock()
        defer { stateLock.unlock() }
        return configurationCount
    }
}
#endif
