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

class CameraService: NSObject {
    private var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var whiteBackgroundLayer: CALayer?
    private var outputURL: URL?
    
    var assetWriter: AVAssetWriter!
    var assetWriterInput: AVAssetWriterInput!
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
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 1920,
            AVVideoHeightKey: 1080
        ]
        assetWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        assetWriterInput.expectsMediaDataInRealTime = true
        
        // Создаем объект AVAssetWriterInputPixelBufferAdaptor
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 1920,
            kCVPixelBufferHeightKey as String: 1080
        ]
        pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: assetWriterInput, sourcePixelBufferAttributes: pixelBufferAttributes)
        
        // Добавляем AVAssetWriterInput в AVAssetWriter
        assetWriter.add(assetWriterInput)
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: CMTime.zero)
    }
    
    func startRecording() {
        isRecording = true
    }
    
    func stopRecording() {
        isRecording = false
        assetWriterInput.markAsFinished()
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
            // Сохраняем начальное время записи для вычисления правильного значения времени презентации каждого кадра
            startTime = cmTime
            assetWriter.startSession(atSourceTime: CMTime.zero)
        }
        
        let presentationTime = CMTimeSubtract(cmTime, startTime!)
        if !assetWriterInput.isReadyForMoreMediaData {
            print("Pixel buffer adaptor is not ready for more media data")
            return
        }
        pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
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
