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
    
    var wbValues: [Int] = []
            

    private override init() {
        super.init()
    }
    
    func prepareRecorder() {
        guard let outputURL = getVideoFileURL() else { return }
        self.outputURL = outputURL
        settingsValues = DBService.shared.fetchSettingsButtonValues()
        generateWBValues()
        
        assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov)
        assetWriter.movieFragmentInterval = CMTime.invalid
                
        audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [])
        try? audioSession.setActive(true, options: [])
        
        audioCaptureSession = AVCaptureSession()
        audioCaptureSession.beginConfiguration()
        
        videoCaptureDevice = AVCaptureDevice.default(for: .video)
        //videoCaptureDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
        
        videoSettingsUpdate()

        audioCaptureDevice = AVCaptureDevice.default(for: .audio)!
        audioCaptureDeviceInput = try! AVCaptureDeviceInput(device: audioCaptureDevice)
        audioCaptureSession.addInput(audioCaptureDeviceInput)
        
        audioCaptureOutput = AVCaptureAudioDataOutput()
        audioCaptureOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "audioCaptureQueue"))
        audioCaptureSession.addOutput(audioCaptureOutput)
        
        DispatchQueue.global(qos: .background).async {
            self.audioCaptureSession.commitConfiguration()
            self.audioCaptureSession.startRunning()
        }
        
        if assetWriter.status != .writing {
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: CMTime.zero)
        }
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
        
        assetWriter.add(assetWriterVideoInput)
        assetWriter.add(assetWriterAudioInput)
        
    }

    
    func startRecording() {
        isRecording = true
    }
    
    func stopRecording() {
        isRecording = false
        assetWriterVideoInput.markAsFinished()
        assetWriterAudioInput.markAsFinished()
        assetWriter.finishWriting {
            DispatchQueue.main.async {
                self.saveVideoToLibrary(videoURL: self.outputURL!)
                self.assetWriter = nil
                self.startTime = nil
                self.prepareRecorder()
            }
        }
        
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard isRecording else {
            return
        }
        
        let pixelBuffer = frame.capturedImage
        let cmTime = CMTimeMakeWithSeconds(frame.timestamp, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        if startTime == nil {
            startTime = cmTime
            assetWriter.startSession(atSourceTime: CMTime.zero)
        }
        
        let presentationTime = CMTimeSubtract(cmTime, startTime!)
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
        guard isRecording, let startTime = startTime else { return }
        
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
        let request = VNDetectFaceCaptureQualityRequest { [weak self] request, error in
            if let error = error {
                print("Error detecting faces: \(error.localizedDescription)")
                return
            }
            
            guard let observation = request.results as? [VNFaceObservation] else { return }
            
            completion(observation)
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        do {
            try handler.perform([request])
        } catch {
            print("Error performing Vision request: \(error.localizedDescription)")
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
