//
//  CameraService.swift
//
//
//  Created by Рустем on 04.05.2023.
//

import Foundation
import AVKit
import ARKit
import RealityKit
import Photos
import Vision
import CoreGraphics

class CameraService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    static let recorderDidFailNotification = Notification.Name("CameraService.recorderDidFail")

    //MARK: - Properties
    static let shared = CameraService()
    
    private var settingsValues: SettingsValues?
    
    private var assetWriter: AVAssetWriter?
    private var assetWriterVideoInput: AVAssetWriterInput?
    
    private var videoCaptureDevice: AVCaptureDevice!
    
    private var audioSession: AVAudioSession!
    private var audioCaptureSession: AVCaptureSession!
    private var audioCaptureDevice: AVCaptureDevice!
    private var audioCaptureDeviceInput: AVCaptureDeviceInput!
    private var audioCaptureOutput: AVCaptureAudioDataOutput!
    private var assetWriterAudioInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    /// M1-010: recording truth is the serialized writer state; this is a
    /// derived projection instead of a parallel flag. Read under recorderLock.
    private var isRecording: Bool { recorderStateStorage == .recording }
    private var outputURL: URL?
    private let recorderLock = NSLock()
    private var recorderStateStorage: RecorderState = .idle
    private var isPreparingRecorder = false

    var recorderState: RecorderState {
        recorderLock.lock()
        defer { recorderLock.unlock() }
        return recorderStateStorage
    }

    /// Legacy callers use this as a compatibility projection. It is true only
    /// while a writer is actually prepared or accepting frames.
    var isRecorderPrepared: Bool {
        switch recorderState {
        case .prepared, .recording:
            return true
        default:
            return false
        }
    }
    
    var wbValues: [Int] = []
    
    private let metalPreprocessor = MetalPreprocessor()
    private let visionTargetSize = CGSize(width: 512, height: 512)
    private let auxiliaryFrameSkipper = FrameSkipController(sourceFPS: 60, targetFPS: 12)
    
    // MARK: - Cached Vision Request (performance optimization)
    private var cachedFaceRequest: VNDetectFaceCaptureQualityRequest?
    private var isVisionRequestInProgress = false
    private let visionQueue = DispatchQueue(label: "com.shafinMultitool.visionQueue", qos: .userInitiated)
            

    private override init() {
        super.init()
    }
    
    func prepareRecorder() {
        recorderLock.lock()
        guard recorderStateStorage != .recording,
              recorderStateStorage != .finishing,
              !isPreparingRecorder else {
            recorderLock.unlock()
            return
        }
        isPreparingRecorder = true
        let previousResources = detachRecorderResourcesLocked()
        recorderLock.unlock()

        if Thread.isMainThread,
           previousResources.captureSession != nil || previousResources.audioSession != nil {
            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.prepareRecorder(afterDetaching: previousResources)
            }
            return
        }

        prepareRecorder(afterDetaching: previousResources)
    }

    private func prepareRecorder(afterDetaching previousResources: (writer: AVAssetWriter?,
                                                                     captureSession: AVCaptureSession?,
                                                                     audioSession: AVAudioSession?,
                                                                     audioOutput: AVCaptureAudioDataOutput?)) {
        stopDetachedResources(previousResources)

        let preparedAudioSession = AVAudioSession.sharedInstance()
        do {
            try preparedAudioSession.setCategory(.playAndRecord, mode: .default, options: [])
            try preparedAudioSession.setActive(true, options: [])
        } catch {
            try? preparedAudioSession.setActive(false, options: .notifyOthersOnDeactivation)
            recorderLock.lock()
            recorderStateStorage = .failed
            isPreparingRecorder = false
            recorderLock.unlock()
            return
        }

        recorderLock.lock()
        audioSession = preparedAudioSession
        let failedResources = prepareRecorderLocked()
        let sessionToStart = recorderStateStorage == .prepared ? audioCaptureSession : nil
        let audioOutputToAttach = recorderStateStorage == .prepared ? audioCaptureOutput : nil
        recorderLock.unlock()

        stopDetachedResources(failedResources)
        audioOutputToAttach?.setSampleBufferDelegate(
            self,
            queue: DispatchQueue(label: "audioCaptureQueue")
        )

        recorderLock.lock()
        let didPrepare = sessionToStart != nil
            && audioCaptureOutput === audioOutputToAttach
            && recorderStateStorage == .prepared
        isPreparingRecorder = false
        recorderLock.unlock()

        if !didPrepare, failedResources.audioSession == nil {
            try? preparedAudioSession.setActive(false, options: .notifyOthersOnDeactivation)
        }
        guard didPrepare, let sessionToStart else {
            return
        }

        DispatchQueue.global(qos: .utility).async { [weak self, sessionToStart] in
            guard let self else { return }
            self.recorderLock.lock()
            let canStart = self.audioCaptureSession === sessionToStart
                && (self.recorderStateStorage == .prepared || self.recorderStateStorage == .recording)
            self.recorderLock.unlock()

            guard canStart else {
                return
            }

            sessionToStart.startRunning()
            self.recorderLock.lock()
            let isStillCurrent = self.audioCaptureSession === sessionToStart
                && (self.recorderStateStorage == .prepared || self.recorderStateStorage == .recording)
            self.recorderLock.unlock()

            if !isStillCurrent {
                sessionToStart.stopRunning()
            }
        }
    }

    private func prepareRecorderLocked() -> (writer: AVAssetWriter?,
                                              captureSession: AVCaptureSession?,
                                              audioSession: AVAudioSession?,
                                              audioOutput: AVCaptureAudioDataOutput?) {
        guard recorderStateStorage != .recording,
              recorderStateStorage != .finishing else { return (nil, nil, nil, nil) }

        if recorderStateStorage == .prepared,
           assetWriter?.status == .writing,
           assetWriterVideoInput != nil,
           assetWriterAudioInput != nil,
           pixelBufferAdaptor != nil {
            return (nil, nil, nil, nil)
        }

        recorderStateStorage = .idle
        startTime = nil

        guard let outputURL = getVideoFileURL() else {
            recorderStateStorage = .failed
            return (nil, nil, nil, nil)
        }
        self.outputURL = outputURL
        settingsValues = DBService.shared.fetchSettingsButtonValues()
        generateWBValues()

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else {
            recorderStateStorage = .failed
            return (nil, nil, nil, nil)
        }
        assetWriter = writer
        writer.movieFragmentInterval = CMTime.invalid

        audioCaptureSession = AVCaptureSession()
        audioCaptureSession.beginConfiguration()
        videoCaptureDevice = AVCaptureDevice.default(for: .video)

        guard videoSettingsUpdate(),
              let audioDevice = AVCaptureDevice.default(for: .audio),
              let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
              audioCaptureSession.canAddInput(audioInput) else {
            let resources = detachRecorderResourcesLocked()
            recorderStateStorage = .failed
            return resources
        }

        audioCaptureDevice = audioDevice
        audioCaptureDeviceInput = audioInput
        audioCaptureSession.addInput(audioInput)

        let audioOutput = AVCaptureAudioDataOutput()
        guard audioCaptureSession.canAddOutput(audioOutput) else {
            let resources = detachRecorderResourcesLocked()
            recorderStateStorage = .failed
            return resources
        }
        audioCaptureOutput = audioOutput
        audioCaptureSession.addOutput(audioOutput)
        audioCaptureSession.commitConfiguration()

        guard writer.startWriting(), writer.status == .writing else {
            let resources = detachRecorderResourcesLocked()
            recorderStateStorage = .failed
            return resources
        }

        recorderStateStorage = .prepared
        return (nil, nil, nil, nil)
    }

    @discardableResult
    func videoSettingsUpdate() -> Bool {
        guard let writer = assetWriter,
              let settingsValues,
              let resolution = settingsValues.resolution.first,
              resolution.width > 0,
              resolution.height > 0,
              settingsValues.fps > 0 else { return false }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: resolution.width,
            AVVideoHeightKey: resolution.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: resolution.width,
            kCVPixelBufferHeightKey as String: resolution.height,
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48000
        ]
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { return false }
        writer.add(videoInput)
        writer.add(audioInput)
        guard writer.inputs.contains(where: { $0 === videoInput }),
              writer.inputs.contains(where: { $0 === audioInput }) else { return false }

        assetWriterVideoInput = videoInput
        assetWriterAudioInput = audioInput
        self.pixelBufferAdaptor = pixelBufferAdaptor
        changeFPS(fps: settingsValues.fps)
        return true
    }

    @discardableResult
    func startRecording() -> Bool {
        recorderLock.lock()
        let isBlocked = recorderStateStorage == .recording
            || recorderStateStorage == .finishing
            || isPreparingRecorder
        let needsPreparation = recorderStateStorage != .prepared
        recorderLock.unlock()

        guard !isBlocked else { return false }
        if needsPreparation {
            prepareRecorder()
        }

        recorderLock.lock()
        defer { recorderLock.unlock() }
        guard recorderStateStorage == .prepared,
              !isPreparingRecorder,
              let writer = assetWriter,
              writer.status == .writing,
              assetWriterVideoInput != nil,
              assetWriterAudioInput != nil,
              pixelBufferAdaptor != nil else {
            recorderStateStorage = .failed
            return false
        }

        recorderStateStorage = .recording
        return true
    }

    func stopRecording(completion: (() -> Void)? = nil) {
        recorderLock.lock()
        guard recorderStateStorage == .recording,
              let writer = assetWriter,
              let videoInput = assetWriterVideoInput else {
            recorderLock.unlock()
            completion?()
            return
        }

        recorderStateStorage = .finishing
        let finishedOutputURL = outputURL
        videoInput.markAsFinished()
        assetWriterAudioInput?.markAsFinished()
        let audioOutput = audioCaptureOutput
        audioCaptureOutput = nil
        recorderLock.unlock()

        DispatchQueue.global(qos: .utility).async {
            audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        }
        writer.finishWriting { [weak self] in
            DispatchQueue.main.async {
                self?.finishRecording(
                    writer: writer,
                    outputURL: finishedOutputURL,
                    completion: completion
                )
            }
        }
    }

    private func finishRecording(writer: AVAssetWriter,
                                  outputURL: URL?,
                                  completion: (() -> Void)?) {
        recorderLock.lock()
        guard recorderStateStorage == .finishing,
              assetWriter === writer else {
            recorderLock.unlock()
            completion?()
            return
        }

        let didFinish = writer.status == .completed
        isPreparingRecorder = true
        let detachedResources = detachRecorderResourcesLocked()
        recorderStateStorage = didFinish ? .finished : .failed
        recorderLock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            self.stopDetachedResources(detachedResources)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.recorderLock.lock()
                let isStillCurrent = self.isPreparingRecorder
                    && self.recorderStateStorage == (didFinish ? .finished : .failed)
                    && self.assetWriter == nil
                if isStillCurrent {
                    self.isPreparingRecorder = false
                }
                self.recorderLock.unlock()

                guard isStillCurrent else {
                    completion?()
                    return
                }

                if didFinish {
                    if let outputURL {
                        self.saveVideoToLibrary(videoURL: outputURL)
                    }
                } else {
                    NotificationCenter.default.post(name: Self.recorderDidFailNotification, object: self)
                }
                completion?()
            }
        }
    }

    private func detachRecorderResourcesLocked() -> (writer: AVAssetWriter?,
                                                      captureSession: AVCaptureSession?,
                                                      audioSession: AVAudioSession?,
                                                      audioOutput: AVCaptureAudioDataOutput?) {
        let resources = (
            writer: assetWriter,
            captureSession: audioCaptureSession,
            audioSession: audioSession,
            audioOutput: audioCaptureOutput
        )
        audioCaptureOutput = nil
        audioCaptureSession = nil
        audioSession = nil
        audioCaptureDeviceInput = nil
        audioCaptureDevice = nil
        assetWriter = nil
        assetWriterVideoInput = nil
        assetWriterAudioInput = nil
        pixelBufferAdaptor = nil
        outputURL = nil
        startTime = nil
        recorderStateStorage = .idle
        return resources
    }

    private func stopDetachedResources(_ resources: (writer: AVAssetWriter?,
                                                       captureSession: AVCaptureSession?,
                                                       audioSession: AVAudioSession?,
                                                       audioOutput: AVCaptureAudioDataOutput?)) {
        resources.audioOutput?.setSampleBufferDelegate(nil, queue: nil)
        resources.captureSession?.stopRunning()
        try? resources.audioSession?.setActive(false, options: .notifyOthersOnDeactivation)
        if let writer = resources.writer, writer.status == .writing {
            writer.cancelWriting()
        }
    }

    private func failRecorderLocked() -> (writer: AVAssetWriter?,
                                           captureSession: AVCaptureSession?,
                                           audioSession: AVAudioSession?,
                                           audioOutput: AVCaptureAudioDataOutput?) {
        let resources = detachRecorderResourcesLocked()
        recorderStateStorage = .failed
        isPreparingRecorder = true
        return resources
    }

    private func publishRecorderFailureAndCleanup(
        _ resources: (writer: AVAssetWriter?,
                      captureSession: AVCaptureSession?,
                      audioSession: AVAudioSession?,
                      audioOutput: AVCaptureAudioDataOutput?)
    ) {
        NotificationCenter.default.post(name: Self.recorderDidFailNotification, object: self)
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            self.stopDetachedResources(resources)
            self.recorderLock.lock()
            self.isPreparingRecorder = false
            self.recorderLock.unlock()
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        appendCapturedPixelBuffer(frame.capturedImage, at: frame.timestamp)
    }

    func appendCapturedPixelBuffer(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        recorderLock.lock()
        guard recorderStateStorage == .recording,
              isRecording,
              let assetWriter,
              let assetWriterVideoInput,
              let pixelBufferAdaptor else {
            recorderLock.unlock()
            return
        }

        guard assetWriter.status == .writing else {
            let failedResources = failRecorderLocked()
            recorderLock.unlock()
            publishRecorderFailureAndCleanup(failedResources)
            return
        }

        guard assetWriterVideoInput.isReadyForMoreMediaData else {
            recorderLock.unlock()
            return
        }

        let cmTime = CMTimeMakeWithSeconds(timestamp, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        if startTime == nil {
            startTime = cmTime
            assetWriter.startSession(atSourceTime: .zero)
        }

        guard let startTime else {
            recorderLock.unlock()
            return
        }
        let presentationTime = CMTimeSubtract(cmTime, startTime)
        if !pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            print("Failed to append pixel buffer at time \(cmTime)")
            let failedResources = failRecorderLocked()
            recorderLock.unlock()
            publishRecorderFailureAndCleanup(failedResources)
            return
        }
        recorderLock.unlock()
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        recorderLock.lock()
        guard let currentAudioOutput = audioCaptureOutput,
              output === currentAudioOutput,
              recorderStateStorage == .recording,
              isRecording,
              let assetWriter,
              let assetWriterAudioInput else {
            recorderLock.unlock()
            return
        }

        guard assetWriter.status == .writing else {
            let failedResources = failRecorderLocked()
            recorderLock.unlock()
            publishRecorderFailureAndCleanup(failedResources)
            return
        }

        guard let startTime else {
            recorderLock.unlock()
            return
        }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if !assetWriterAudioInput.isReadyForMoreMediaData {
            recorderLock.unlock()
            return
        }
        
        let presentationTime = CMTimeSubtract(timestamp, startTime)
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: presentationTime, decodeTimeStamp: CMTime.invalid)
        var copiedSampleBuffer: CMSampleBuffer?
        var _ = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: 1, sampleTimingArray: &timingInfo, sampleBufferOut: &copiedSampleBuffer)
        
        guard let syncedBuffer = copiedSampleBuffer else {
            recorderLock.unlock()
            return
        }
        
        if assetWriterAudioInput.append(syncedBuffer) {
        } else {
            print("Failed to append audio sample buffer at time \(presentationTime)")
            let failedResources = failRecorderLocked()
            recorderLock.unlock()
            publishRecorderFailureAndCleanup(failedResources)
            return
        }
        recorderLock.unlock()
    }
     
    func gazeDetection(pixelBuffer: CVPixelBuffer, completion: @escaping ([VNFaceObservation]) -> ()) {
        // Prevent concurrent Vision requests to reduce CPU/GPU load
        guard !isVisionRequestInProgress else { return }
        isVisionRequestInProgress = true
        
        visionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create or reuse the cached request
            let request: VNDetectFaceCaptureQualityRequest
            if let cached = self.cachedFaceRequest {
                request = cached
            } else {
                request = VNDetectFaceCaptureQualityRequest()
                self.cachedFaceRequest = request
            }
            
            let resizedBuffer = self.metalPreprocessor.resizedPixelBuffer(from: pixelBuffer,
                                                                           targetSize: self.visionTargetSize) ?? pixelBuffer
            // Use minimal options for performance
            let handler = VNImageRequestHandler(cvPixelBuffer: resizedBuffer, options: [:])
            
            do {
                try handler.perform([request])
                
                let observations = request.results ?? []
                completion(observations)
            } catch {
                print("Error performing Vision request: \(error.localizedDescription)")
            }
            
            self.isVisionRequestInProgress = false
        }
    }
    
    func switchFlashlight() {
        try? videoCaptureDevice.lockForConfiguration()
        switch videoCaptureDevice.isTorchActive {
        case true:
            videoCaptureDevice.torchMode = .off
        case false:
            videoCaptureDevice.torchMode = .on
        }
        
        videoCaptureDevice.unlockForConfiguration()
    }
    
    func changeResolution(width: Int, height: Int) {
        prepareRecorder()
    }
    
    func changeISO(iso: Int) {
        try? videoCaptureDevice.lockForConfiguration()
        
        videoCaptureDevice.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: Float(iso), completionHandler: nil)
        
        videoCaptureDevice.unlockForConfiguration()
        
    }
    
    func changeWB(wb: Int) {
        try? videoCaptureDevice.lockForConfiguration()
        
        let newWhiteBalanceValue = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(wb), tint: 0.0)
        videoCaptureDevice.setWhiteBalanceModeLocked(with: videoCaptureDevice.deviceWhiteBalanceGains(for: newWhiteBalanceValue))
        
        videoCaptureDevice.unlockForConfiguration()
    }
    
    func changeFPS(fps: Int) {
        guard fps > 0, let videoCaptureDevice else { return }
        try? videoCaptureDevice.lockForConfiguration()

        videoCaptureDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
        videoCaptureDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))

        videoCaptureDevice.unlockForConfiguration()
    
    }
    
    func focusOnTap(focusPoint: CGPoint) {
        try? videoCaptureDevice.lockForConfiguration()
        
        videoCaptureDevice.focusPointOfInterest = focusPoint
        videoCaptureDevice.focusMode = .autoFocus
        
        videoCaptureDevice.exposurePointOfInterest = focusPoint
        videoCaptureDevice.exposureMode = .autoExpose
        
        videoCaptureDevice.unlockForConfiguration()
    }
    
    func getIsoValues() -> [Int] {
        return [50,100,200,400,800]
    }
    
    func getWBValues() -> [Int] {
        return wbValues
    }
    
    func shouldProcessAuxiliaryFrame() -> Bool {
        return auxiliaryFrameSkipper.shouldProcessFrame()
    }

    func updateAuxiliaryTargetFPS(_ targetFPS: Int) {
        auxiliaryFrameSkipper.updateTarget(sourceFPS: 60, targetFPS: max(1, targetFPS))
    }
    
    func generateWBValues() {
        wbValues.removeAll(keepingCapacity: true)
        wbValues.append(2400)
        while wbValues.last != 8000 {
            wbValues.append((wbValues.last ?? 2400) + 100)
        }
    }
    
    func saveVideoToLibrary(videoURL: URL) {
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: videoURL)
        }) { saved, error in
            if let error = error {
                print("Error saving video to library: \(error.localizedDescription)")
            } else {
                print("Video saved to library!")
            }
        }
    }
        
    
    private func getVideoFileURL() -> URL? {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileManager = FileManager.default
        var fileURL: URL
        repeat {
            fileURL = documentsDirectory.appendingPathComponent("video_\(UUID().uuidString).mov")
        } while fileManager.fileExists(atPath: fileURL.path)
        return fileURL
    }
}
