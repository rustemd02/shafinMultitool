//
//  SpeechRecognitionService.swift
//  shafinMultitool
//
//  Created by Рустем on 08.12.2023.
//

import Foundation
import Speech

class SpeechRecognitionService {
    static let shared = SpeechRecognitionService()
    
    let audioEngine = AVAudioEngine()
    let speechRecogniser: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.init(identifier: "ru-RU"))
    var task: SFSpeechRecognitionTask? = nil
    
    // Thread safety and state tracking
    private let recognitionQueue = DispatchQueue(label: "com.shafinMultitool.speechRecognition")
    private var isRecognitionActive = false
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest?
    
    func recognise(completion: @escaping (String) -> ()) {
        recognitionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Prevent multiple concurrent recognition sessions
            guard !self.isRecognitionActive else { return }
            self.isRecognitionActive = true
            
            let node = self.audioEngine.inputNode
            let recordingFormat = node.outputFormat(forBus: 0)
            
            let request = SFSpeechAudioBufferRecognitionRequest()
            self.currentRequest = request
            
            self.audioEngine.prepare()
            let recognitionStart = CACurrentMediaTime()
            do {
                try self.audioEngine.start()
            } catch let error {
                print("SpeechRecognition: Failed to start audio engine - \(error)")
                self.isRecognitionActive = false
                return
            }
            
            node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.currentRequest?.append(buffer)
            }
            
            self.task = self.speechRecogniser?.recognitionTask(with: request, resultHandler: { [weak self] response, error in
                if let response = response {
                    let message = response.bestTranscription.formattedString
                    completion(message)
                    let duration = CACurrentMediaTime() - recognitionStart
                    PerformanceMonitor.shared.recordSpeechLatency(duration)
                }
                
                // Check if recognition was cancelled
                if let error = error {
                    print("SpeechRecognition: Recognition error - \(error.localizedDescription)")
                    let duration = CACurrentMediaTime() - recognitionStart
                    PerformanceMonitor.shared.recordSpeechLatency(duration)
                    self?.stopRecognitionInternal()
                }
            })
        }
    }
    
    func stopRecognition() {
        recognitionQueue.async { [weak self] in
            self?.stopRecognitionInternal()
        }
    }
    
    private func stopRecognitionInternal() {
        guard isRecognitionActive else { return }
        
        // End the recognition request
        currentRequest?.endAudio()
        currentRequest = nil
        
        task?.finish()
        task?.cancel()
        task = nil
        
        // Stop audio engine safely
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        
        // Remove tap safely (only if one exists)
        audioEngine.inputNode.removeTap(onBus: 0)
        
        isRecognitionActive = false
    }
}
