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

class CameraService: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    //MARK: - Properties
    static let shared = CameraService()
    
    private var assetWriter: AVAssetWriter!
    private var assetWriterVideoInput: AVAssetWriterInput!
    
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
    
    let resolutions: [(width: Int, height: Int)] = [(1280, 720), (1920, 1080), (3840, 2160)]

    
    private override init() {
        super.init()
    }
    
    func prepareRecorder() {
        guard let outputURL = getVideoFileURL() else { return }
        self.outputURL = outputURL
        
        assetWriter = try? AVAssetWriter(outputURL: outputURL, fileType: .mov)
        assetWriter.movieFragmentInterval = CMTime.invalid
        
        videoSettingsUpdate()
        
        audioSession = AVAudioSession.sharedInstance()
        try? audioSession.setCategory(.playAndRecord, mode: .default, options: [])
        try? audioSession.setActive(true, options: [])
        
        audioCaptureSession = AVCaptureSession()
        audioCaptureSession.beginConfiguration()
        
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
        
        if let existingVideoInput = existingVideoInput {
            existingVideoInput.markAsFinished()
            assetWriterVideoInput = nil
        }
        
        if let existingAudioInput = existingAudioInput {
            existingAudioInput.markAsFinished()
            assetWriterAudioInput = nil
        }
        
        guard let outputURL = getVideoFileURL() else { return }
        let width = resolutions[UserDefaults.standard.integer(forKey: "selectedResoultionsRow")].width
        let height = resolutions[UserDefaults.standard.integer(forKey: "selectedResoultionsRow")].height
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
        ]

        assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        assetWriterVideoInput.expectsMediaDataInRealTime = true

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: pixelBufferAttributes)
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48000
        ]
        assetWriterAudioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        assetWriterAudioInput.expectsMediaDataInRealTime = true
        
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
                print("Pixel buffer appended at time \(cmTime)")
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
            print("Audio sample buffer appended at time \(presentationTime)")
        } else {
            print("Failed to append audio sample buffer at time \(presentationTime)")
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
