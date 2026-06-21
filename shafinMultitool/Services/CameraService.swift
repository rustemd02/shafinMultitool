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
    //MARK: - Properties
    static let shared = CameraService()
    
    private var settingsValues: SettingsValues?
    
    private var assetWriter: AVAssetWriter!
    private var assetWriterVideoInput: AVAssetWriterInput!
    
    private var videoCaptureDevice: AVCaptureDevice!
    
    private var audioSession: AVAudioSession!
    private var audioCaptureSession: AVCaptureSession!
    private var audioCaptureDevice: AVCaptureDevice!
    private var audioCaptureDeviceInput: AVCaptureDeviceInput!
    private var audioCaptureOutput: AVCaptureAudioDataOutput!
    private var assetWriterAudioInput: AVAssetWriterInput!
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    private var startTime: CMTime?
    private var isRecording = false
    private var outputURL: URL?
    private(set) var isRecorderPrepared = false
    
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
        isRecorderPrepared = false

        guard let outputURL = getVideoFileURL() else { return }
        self.outputURL = outputURL
        settingsValues = DBService.shared.fetchSettingsButtonValues()
        generateWBValues()
        
        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .mov) else { return }
        assetWriter = writer
        assetWriter.movieFragmentInterval = CMTime.invalid
                
        audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [])
        try? audioSession.setActive(true, options: [])
        
        audioCaptureSession = AVCaptureSession()
        audioCaptureSession.beginConfiguration()
        
        videoCaptureDevice = AVCaptureDevice.default(for: .video)
        
        videoSettingsUpdate()

        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           audioCaptureSession.canAddInput(audioInput) {
            audioCaptureDevice = audioDevice
            audioCaptureDeviceInput = audioInput
            audioCaptureSession.addInput(audioInput)

            let audioOutput = AVCaptureAudioDataOutput()
            audioOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioCaptureQueue"))
            if audioCaptureSession.canAddOutput(audioOutput) {
                audioCaptureOutput = audioOutput
                audioCaptureSession.addOutput(audioOutput)
            }
        }
        
        DispatchQueue.global(qos: .background).async {
            self.audioCaptureSession.commitConfiguration()
            self.audioCaptureSession.startRunning()
        }
        
        if assetWriter.status != .writing {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMTime.zero)
        }

        isRecorderPrepared = assetWriter != nil && assetWriterVideoInput != nil && pixelBufferAdaptor != nil
    }
    
    func videoSettingsUpdate() {
        let existingVideoInput = assetWriter.inputs.first { $0 == assetWriterVideoInput }
        let existingAudioInput = assetWriter.inputs.first { $0 == assetWriterAudioInput }
        guard let settingsValues = settingsValues else { return }
        
        if let existingVideoInput = existingVideoInput {
            existingVideoInput.markAsFinished()
            assetWriterVideoInput = nil
        }
        
        if let existingAudioInput = existingAudioInput {
            existingAudioInput.markAsFinished()
            assetWriterAudioInput = nil
        }
        
        guard let outputURL = getVideoFileURL() else { return }
        guard let resolution = settingsValues.resolution.first else { return }
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: resolution.width,
            AVVideoHeightKey: resolution.height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill,
        ]

        assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        assetWriterVideoInput.expectsMediaDataInRealTime = true

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: resolution.width,
            kCVPixelBufferHeightKey as String: resolution.height,
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: pixelBufferAttributes)
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48000
        ]
        assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        assetWriterAudioInput.expectsMediaDataInRealTime = true
        
        changeFPS(fps: settingsValues.fps)
        
        if assetWriter.canAdd(assetWriterVideoInput) {
            assetWriter.add(assetWriterVideoInput)
        }
        if assetWriter.canAdd(assetWriterAudioInput) {
            assetWriter.add(assetWriterAudioInput)
        }
    }

    
    func startRecording() {
        if !isRecorderPrepared {
            prepareRecorder()
        }
        guard isRecorderPrepared else { return }
        isRecording = true
    }
    
    func stopRecording() {
        guard isRecorderPrepared,
              let assetWriterVideoInput,
              let assetWriterAudioInput,
              let assetWriter else {
            isRecording = false
            isRecorderPrepared = false
            return
        }

        isRecording = false
        assetWriterVideoInput.markAsFinished()
        assetWriterAudioInput.markAsFinished()
        assetWriter.finishWriting {
            DispatchQueue.main.async {
                if let outputURL = self.outputURL {
                    self.saveVideoToLibrary(videoURL: outputURL)
                }
                self.assetWriter = nil
                self.startTime = nil
                self.isRecorderPrepared = false
                self.prepareRecorder()
            }
        }
        
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRecording else {
            return
        }
        appendCapturedPixelBuffer(frame.capturedImage, at: frame.timestamp)
    }

    func appendCapturedPixelBuffer(_ pixelBuffer: CVPixelBuffer, at timestamp: TimeInterval) {
        guard isRecording,
              isRecorderPrepared,
              let assetWriter,
              let assetWriterVideoInput,
              let assetWriterAudioInput,
              let pixelBufferAdaptor else { return }

        let cmTime = CMTimeMakeWithSeconds(timestamp, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        if startTime == nil {
            startTime = cmTime
            assetWriter.startSession(atSourceTime: CMTime.zero)
        }
        
        guard let startTime else { return }
        let presentationTime = CMTimeSubtract(cmTime, startTime)
        if !assetWriterVideoInput.isReadyForMoreMediaData {
            return
        }
        
        if assetWriterAudioInput.isReadyForMoreMediaData {
            if pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
            } else {
                print("Failed to append pixel buffer at time \(cmTime)")
            }
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording,
              isRecorderPrepared,
              let startTime = startTime,
              let assetWriterAudioInput else { return }
        
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        
        if !assetWriterAudioInput.isReadyForMoreMediaData {
            return
        }
        
        let presentationTime = CMTimeSubtract(timestamp, startTime)
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: presentationTime, decodeTimeStamp: CMTime.invalid)
        var copiedSampleBuffer: CMSampleBuffer?
        var _ = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: 1, sampleTimingArray: &timingInfo, sampleBufferOut: &copiedSampleBuffer)
        
        guard let syncedBuffer = copiedSampleBuffer else {
            return
        }
        
        if assetWriterAudioInput.append(syncedBuffer) {
        } else {
            print("Failed to append audio sample buffer at time \(presentationTime)")
        }
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
        try? videoCaptureDevice.lockForConfiguration()
        
        assetWriter = nil
        prepareRecorder()
        
        videoCaptureDevice.unlockForConfiguration()
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let date = dateFormatter.string(from: Date())
        let fileName = "video_\(date).mov"
        let fileURL = documentsDirectory.appendingPathComponent(fileName)
        return fileURL
    }
}
