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

class CameraService: NSObject, AVCaptureFileOutputRecordingDelegate {
    private var captureSession: AVCaptureSession?
    private var movieFileOutput: AVCaptureMovieFileOutput?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var whiteBackgroundLayer: CALayer?
    private var outputURL: URL?
    
    
    func prepareRecorder(arView: ARView) {
        let captureSession = AVCaptureSession()
        captureSession.beginConfiguration()
        
        // Настройка входного устройства для захвата видео
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return
        }
        
        guard let videoDeviceInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoDeviceInput) else {
            return
        }
        captureSession.addInput(videoDeviceInput)
        
        
        //  Настройка вывода превью видео
        let videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.connection?.videoOrientation = .portrait
        arView.layer.addSublayer(videoPreviewLayer)
        videoPreviewLayer.frame = arView.bounds
        
        self.videoPreviewLayer = videoPreviewLayer
        
        captureSession.commitConfiguration()
        self.captureSession = captureSession
    }
    
    func startRecording() {
        guard let captureSession = captureSession, let outputURL = getVideoFileURL() else {
            return
        }
        
        self.outputURL = outputURL
        
        movieFileOutput = AVCaptureMovieFileOutput()
        guard let movieFileOutput = movieFileOutput else { return }
        captureSession.beginConfiguration()
        
        if captureSession.canAddOutput(movieFileOutput) {
            captureSession.addOutput(movieFileOutput)
        }
        
        if let connection = movieFileOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
        }
        
        captureSession.commitConfiguration()
        
        DispatchQueue.global(qos: .background).async {
            self.captureSession?.startRunning()
            movieFileOutput.startRecording(to: outputURL, recordingDelegate: self)
        }
    }
    
    func stopRecording() {
        guard let captureSession = captureSession, let movieFileOutput = movieFileOutput else {
            return
        }
        
        captureSession.stopRunning()
        movieFileOutput.stopRecording()
        
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
    
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        guard let outputURL = self.outputURL else {
            return
        }
        
        // Создаем asset и экспортируем видео без моделей ARKit
        let asset = AVURLAsset(url: outputFileURL)
        let composition = AVMutableComposition()
        let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        let sourceVideoTrack = asset.tracks(withMediaType: .video).first!
        
        do {
            try videoTrack?.insertTimeRange(CMTimeRangeMake(start: .zero, duration: asset.duration), of: sourceVideoTrack, at: .zero)
        } catch {
            print(error.localizedDescription)
            return
        }
        
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            return
        }
        
        let newFileName = "exported_\(outputURL.lastPathComponent)"
        let newFileURL = outputURL.deletingLastPathComponent().appendingPathComponent(newFileName)
        
        exportSession.outputURL = newFileURL
        exportSession.outputFileType = .mov
        exportSession.exportAsynchronously(completionHandler: {
            switch exportSession.status {
            case .completed:
                self.saveVideoToLibrary(videoURL: newFileURL)
            case .failed, .cancelled:
                print("Export failed: \(exportSession.error?.localizedDescription ?? "unknown error")")
            default:
                break
            }
        })
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
