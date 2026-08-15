//
//  CameraManager.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import AVFoundation
import CoreMotion

enum CameraLens: CGFloat, CaseIterable {
    case ultraWide = 0.5
    case wide = 1.0
    case telephoto2x = 2.0
    case telephoto3x = 3.0
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
        case .ultraWide: return .builtInUltraWideCamera
        case .wide: return .builtInWideAngleCamera
        case .telephoto2x, .telephoto3x: return .builtInTelephotoCamera
        }
    }
    
    var displayName: String {
        switch self {
        case .ultraWide: return "0.5×"
        case .wide: return "1×"
        case .telephoto2x: return "2×"
        case .telephoto3x: return "3×"
        }
    }
}

enum CameraManagerError: Error, Equatable, Sendable, CustomStringConvertible {
    case noWideCamera
    case inputConstructionFailed
    case inputAddFailed
    case outputAddFailed
    case startFailed

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
        }
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

    private var isConfigured = false
    private var currentInput: AVCaptureDeviceInput?
    private var currentLens: CameraLens = .wide
    private var desiredVideoOrientation: AVCaptureVideoOrientation = .landscapeLeft

    private let stateLock = NSLock()
    private var storedLifecycleState: CameraLifecycleState = .idle
    private var storedConfigurationState: CameraConfigurationState = .unconfigured
    private var storedLifecycleError: CameraManagerError?
    private var configurationCount = 0

    private let availableLensesLock = NSLock()
    private var storedAvailableLenses: [CameraLens] = []

    private let frameDeliveryLock = NSLock()
    private var frameDeliveryEnabled = false

    var captureSession: AVCaptureSession { session }

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

    init(scheduler: RealtimeScheduler,
         thermalGovernor: ThermalGovernor,
         motionGate: MotionGate) {
        let session = AVCaptureSession()
        self.session = session
        self.videoOutput = AVCaptureVideoDataOutput()
        self.scheduler = scheduler
        self.thermalGovernor = thermalGovernor
        self.motionGate = motionGate
        self.sessionRunner = AVCaptureSessionRunner(session: session)
        self.testConfiguration = nil
        super.init()
        videoOutputQueue.setSpecific(key: videoOutputQueueKey, value: ())
    }

    init(scheduler: RealtimeScheduler,
         thermalGovernor: ThermalGovernor,
         motionGate: MotionGate,
         sessionRunner: CameraSessionRunner,
         configuration: CameraManagerTestConfiguration,
         session: AVCaptureSession = AVCaptureSession()) {
        self.session = session
        self.videoOutput = AVCaptureVideoDataOutput()
        self.scheduler = scheduler
        self.thermalGovernor = thermalGovernor
        self.motionGate = motionGate
        self.sessionRunner = sessionRunner
        self.testConfiguration = configuration
        super.init()
        videoOutputQueue.setSpecific(key: videoOutputQueueKey, value: ())
    }

    func startAndWait() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume(throwing: CameraManagerError.startFailed)
                    return
                }

                do {
                    try self.startOnSessionQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stopAndWait() async {
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
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                self?.releaseOnSessionQueue()
                continuation.resume()
            }
        }
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

    private func startOnSessionQueue() throws {
        if sessionRunner.isRunning, isConfigured {
            if !isFrameDeliveryEnabled() {
                attachVideoDelegateAndEnableDelivery()
            }
            setLifecycleState(.running,
                              configuration: isConfigured ? .configured : .unconfigured)
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

        attachVideoDelegateAndEnableDelivery()
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

        setLifecycleState(.running, configuration: .configured)
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
        currentLens = .wide
        isConfigured = false
        setAvailableLenses([])
        setLifecycleState(.idle, configuration: .unconfigured)
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
            currentLens = .wide
            isConfigured = true
            markConfigured()
        } catch {
            if inputWasAdded, let input {
                session.removeInput(input)
            }
            currentInput = nil
            setAvailableLenses([])
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
        currentLens = .wide
        setAvailableLenses([.wide])
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
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = desiredVideoOrientation
            }
        }
    }

    private func attachVideoDelegateAndEnableDelivery() {
        videoOutput.setSampleBufferDelegate(self, queue: videoOutputQueue)
        setFrameDeliveryEnabled(true)
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
    
    private func discoverAvailableLenses() {
        setAvailableLenses(CameraLens.allCases.filter { lens in
            findCamera(for: lens) != nil
        })
    }
    
    private func findCamera(for lens: CameraLens) -> AVCaptureDevice? {
        return AVCaptureDevice.default(lens.deviceType, for: .video, position: .back)
    }
    
    func switchLens(to lens: CameraLens) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isConfigured,
                  self.currentInput != nil,
                  self.availableLenses.contains(lens) else { return }
            guard lens != self.currentLens else { return }
            
            guard let newCamera = self.findCamera(for: lens),
                  let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
                return
            }
            
            self.session.beginConfiguration()
            
            if let oldInput = self.currentInput {
                self.session.removeInput(oldInput)
            }
            
            if self.session.canAddInput(newInput) {
                self.session.addInput(newInput)
                self.currentInput = newInput
                self.currentLens = lens
                
                if let connection = self.videoOutput.connection(with: .video) {
                    connection.preferredVideoStabilizationMode = .cinematicExtended
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = self.desiredVideoOrientation
                    }
                }
            }
            
            self.session.commitConfiguration()
        }
    }

    func setVideoOrientation(_ orientation: AVCaptureVideoOrientation) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.desiredVideoOrientation = orientation
            guard self.isConfigured,
                  let connection = self.videoOutput.connection(with: .video),
                  connection.isVideoOrientationSupported else { return }
            connection.videoOrientation = orientation
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard isFrameDeliveryEnabled() else { return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let orientation = CGImagePropertyOrientation(connection.videoOrientation)
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let isStable = motionGate.isCameraStable
        let shakeLevel = motionGate.shakeLevel
        let motionState = motionGate.motionState
        let context = FrameContext(pixelBuffer: pixelBuffer,
                                   timestamp: timestamp,
                                   orientation: orientation,
                                   isStable: isStable,
                                   shakeLevel: shakeLevel,
                                   motionState: motionState)

        let budget = thermalGovernor.nextBudget()

        frameDeliveryLock.lock()
        guard frameDeliveryEnabled else {
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

private extension CGImagePropertyOrientation {
    init(_ orientation: AVCaptureVideoOrientation) {
        switch orientation {
        case .portrait: self = .right
        case .portraitUpsideDown: self = .left
        case .landscapeRight: self = .up
        case .landscapeLeft: self = .down
        @unknown default: self = .right
        }
    }
}
