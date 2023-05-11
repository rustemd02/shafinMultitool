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
    private var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var whiteBackgroundLayer: CALayer?
    private var outputURL: URL?
    
    var assetWriter: AVAssetWriter!
    var assetWriterVideoInput: AVAssetWriterInput!
    var audioSession: AVAudioSession!
    var audioCaptureSession: AVCaptureSession!
    var audioCaptureDevice: AVCaptureDevice!
    var audioCaptureDeviceInput: AVCaptureDeviceInput!
    var audioCaptureOutput: AVCaptureAudioDataOutput!
    var audioAssetWriterInput: AVAssetWriterInput!
    var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor!
    private var startTime: CMTime?
    var isRecording = false
    
    
    func prepareRecorder() {
        guard let outputURL = getVideoFileURL() else { return }
        self.outputURL = outputURL
        
        assetWriter = try! AVAssetWriter(outputURL: outputURL, fileType: .mov)
        assetWriter.movieFragmentInterval = CMTime.invalid
        
        // Настраиваем объект AVAssetWriterInput
        
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080,
            AVVideoScalingModeKey: AVVideoScalingModeResizeAspectFill
        ]

        assetWriterVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        assetWriterVideoInput.expectsMediaDataInRealTime = true
        
        // Создаем объект AVAssetWriterInputPixelBufferAdaptor
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080,
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterVideoInput, sourcePixelBufferAttributes: pixelBufferAttributes)
        
        assetWriter.add(assetWriterVideoInput)
        
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 48000
        ]
        audioAssetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioAssetWriterInput.expectsMediaDataInRealTime = true
        
        
        // Добавляем AVAssetWriterInput в AVAssetWriter
        assetWriter.add(audioAssetWriterInput)
        
        
        // Настраиваем объект AVCaptureSession для записи аудио
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
        
        audioCaptureSession.commitConfiguration()
        audioCaptureSession.startRunning()
        
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
    }
    
    func startRecording() {
        isRecording = true
    }
    
    func stopRecording() {
        isRecording = false
        assetWriterVideoInput.markAsFinished()
        assetWriter.finishWriting {
            DispatchQueue.main.async {
                self.saveVideoToLibrary(videoURL: self.outputURL!)
                print("Video saved to \(self.assetWriter.outputURL)")
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
            print("Pixel buffer adaptor is not ready for more media data")
            return
        }
        //pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
        
        if audioAssetWriterInput.isReadyForMoreMediaData {
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
        
        if !audioAssetWriterInput.isReadyForMoreMediaData {
            print("Audio asset writer input is not ready for more media data, dropping frame")
            return
        }
        
        // Синхронизируем время презентации каждого звукового образца с временем начала записи
        var presentationTime = CMTimeSubtract(timestamp, startTime)
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid, presentationTimeStamp: presentationTime, decodeTimeStamp: CMTime.invalid)
        var copiedSampleBuffer: CMSampleBuffer?
        var status = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sampleBuffer, sampleTimingEntryCount: 1, sampleTimingArray: &timingInfo, sampleBufferOut: &copiedSampleBuffer)
        
        guard let syncedBuffer = copiedSampleBuffer else {
            // handle error case here
            return
        }
        
        if audioAssetWriterInput.append(syncedBuffer) {
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
    
}
