//
//  CameraManager.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import AVFoundation
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
    case failure(CameraManagerError)
}

final class CameraManager: NSObject, @unchecked Sendable {
    private let session: AVCaptureSession
    private let videoOutput: AVCaptureVideoDataOutput
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
         notificationCenter: NotificationCenter = .default) {
        self.session = session
        self.videoOutput = AVCaptureVideoDataOutput()
        self.scheduler = scheduler
        self.thermalGovernor = thermalGovernor
        self.motionGate = motionGate
        self.sessionRunner = sessionRunner
        self.testConfiguration = configuration
        self.notificationCenter = notificationCenter
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
            if !isFrameDeliveryEnabled() {
                guard attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: generation) else { return }
            }
            if let failure = finishStartTransitionOnSessionQueue() {
                try stopAndThrowStartFailure(failure)
            }
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

        guard attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: generation) else { return }
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
    }

    private func stopOnSessionQueue() {
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
        captureBoundaryLock.lock()
        disableDeliveryAndDetachDelegate()
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

    private func configureReadyTestSession() throws {
        session.beginConfiguration()
        configureVideoOutput()
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        currentInput = nil
        // The ready test session represents one installed capture input. Keep
        // its active lens provenance identical to the production wide-camera
        // configuration so downstream episode verification can compare lens
        // identity without inventing it in a test or view model.
        setCurrentLens(.wide)
        setAvailableLenses([.wide])
        setLensDescriptors([.wide: CameraLens.wide.descriptor])
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
        setFrameDeliveryEnabled(true)
        return true
    }

    private func disableDeliveryAndDetachDelegate() {
        setFrameDeliveryEnabled(false)
        videoOutput.setSampleBufferDelegate(nil, queue: videoOutputQueue)
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
            setCurrentLens(lens)
            configureVideoConnection()
            advanceCaptureGeneration()
            if wasDeliveringFrames {
                _ = attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: operationGeneration)
            }
            return .success(activeLens: lens)
        case .restored:
            if wasDeliveringFrames {
                _ = attachVideoDelegateAndEnableDelivery(expectedSessionGeneration: operationGeneration)
            }
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
            disableDeliveryAndDetachDelegate()
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

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let capturedAt = Date()
        guard isFrameDeliveryEnabled() else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation = CameraFrameDeliveryOrientationContract.imageOrientation(
            for: desiredVideoOrientationSnapshot()
        )
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let captureGeneration = currentCaptureGeneration()
        let motionSnapshot = motionGate.snapshot()
        let context = FrameContext(pixelBuffer: pixelBuffer,
                                   timestamp: timestamp,
                                   orientation: orientation,
                                   isStable: motionSnapshot.isStable,
                                   shakeLevel: motionSnapshot.shakeLevel,
                                   motionState: motionSnapshot.motionState,
                                   capturedAt: capturedAt,
                                   captureGeneration: captureGeneration)

        let budget = thermalGovernor.nextBudget()

        frameDeliveryLock.lock()
        guard frameDeliveryEnabled,
              captureGeneration == currentCaptureGeneration() else {
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
