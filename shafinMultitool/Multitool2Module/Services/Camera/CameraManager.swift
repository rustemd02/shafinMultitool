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

final class CameraManager: NSObject {
    private let session = AVCaptureSession()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "CameraManager.Session")

    private let scheduler: RealtimeScheduler
    private let thermalGovernor: ThermalGovernor
    private let motionGate: MotionGate

    private var isConfigured = false
    private var currentInput: AVCaptureDeviceInput?
    private var currentLens: CameraLens = .wide
    private var desiredVideoOrientation: AVCaptureVideoOrientation = .landscapeLeft

    private(set) var availableLenses: [CameraLens] = []

    var captureSession: AVCaptureSession { session }

    init(scheduler: RealtimeScheduler,
         thermalGovernor: ThermalGovernor,
         motionGate: MotionGate) {
        self.scheduler = scheduler
        self.thermalGovernor = thermalGovernor
        self.motionGate = motionGate
        super.init()
    }

    func start() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.configureSession()
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
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

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .high
        
        // Определяем доступные камеры
        discoverAvailableLenses()

        // Настраиваем камеру по умолчанию (wide)
        guard let camera = findCamera(for: .wide),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        currentInput = input
        currentLens = .wide

        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        let outputQueue = DispatchQueue(label: "CameraManager.VideoOutput")
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            session.commitConfiguration()
            return
        }
        session.addOutput(videoOutput)

        if let connection = videoOutput.connection(with: .video) {
            connection.preferredVideoStabilizationMode = .cinematicExtended
            if connection.isVideoOrientationSupported {
                connection.videoOrientation = desiredVideoOrientation
            }
        }

        session.commitConfiguration()
        isConfigured = true
    }
    
    private func discoverAvailableLenses() {
        availableLenses = CameraLens.allCases.filter { lens in
            findCamera(for: lens) != nil
        }
    }
    
    private func findCamera(for lens: CameraLens) -> AVCaptureDevice? {
        return AVCaptureDevice.default(lens.deviceType, for: .video, position: .back)
    }
    
    func switchLens(to lens: CameraLens) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.availableLenses.contains(lens) else { return }
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
            guard let connection = self.videoOutput.connection(with: .video),
                  connection.isVideoOrientationSupported else { return }
            connection.videoOrientation = orientation
        }
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
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
        scheduler.dispatch(context: context, budget: budget)
    }
}

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

