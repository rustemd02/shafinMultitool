//
//  CameraService.swift
//  
//
//  Created by Рустем on 04.05.2023.
//

import Foundation
import AVKit

class CameraService: NSObject, AVCaptureFileOutputRecordingDelegate {
    var outputURL: URL?
    
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
                       print("Exported video file: \(newFileURL)")
                   case .failed, .cancelled:
                       print("Export failed: \(exportSession.error?.localizedDescription ?? "unknown error")")
                   default:
                       break
                   }
               })
           }
       }
