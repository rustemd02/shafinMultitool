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
    let request = SFSpeechAudioBufferRecognitionRequest()
    var task: SFSpeechRecognitionTask? = nil
    
    
    func recognise(completion: @escaping (String) -> ()){
        let node = audioEngine.inputNode
        let recordingFormat = node.outputFormat(forBus: 0)
        
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch let error {
            print(error)
        }
        
        node.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.request.append(buffer)
        }
        
        task = speechRecogniser?.recognitionTask(with: request, resultHandler: { response, error in
            guard let response = response else { return }
            let message = response.bestTranscription.formattedString
            completion(message)
        })
    }
    
    func stopRecognition() {
        task?.finish()
        task?.cancel()
        task = nil
        
        request.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
}
