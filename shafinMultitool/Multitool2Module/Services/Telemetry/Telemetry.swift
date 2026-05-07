//
//  Telemetry.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation
import os.log
import QuartzCore
import Combine
import UIKit

enum CameraLog {
    static let fps = false
    static let suggestions = false
    static let motion = false
    static let vision = false
    static let detr = false
    static let modelLifecycle = false
    static let liveHintDecisions = true
}

final class Telemetry: ObservableObject {
    static let shared = Telemetry()

    @Published private(set) var metrics = DebugMetrics()
    
    private let log = OSLog(subsystem: "com.multitool2.camera", category: "Telemetry")
    private var frameCount: Int = 0
    private var startTime: TimeInterval = CACurrentMediaTime()
    private var lastFPSUpdate: TimeInterval = CACurrentMediaTime()
    private let queue = DispatchQueue(label: "Telemetry")
    
    private var uiFrameCount: Int = 0
    private var uiStartTime: TimeInterval = CACurrentMediaTime()

    init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        startMonitoring()
    }
    
    private func startMonitoring() {
        // Периодическое обновление метрик
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.updateSystemMetrics()
        }
    }
    
    private func updateSystemMetrics() {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let thermalState = ProcessInfo.processInfo.thermalState
            let battery = UIDevice.current.batteryLevel
            
            DispatchQueue.main.async {
                self.metrics.thermalState = self.thermalStateString(thermalState)
                self.metrics.batteryLevel = battery
            }
        }
    }
    
    func recordFrameProcessed() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.frameCount += 1
            let now = CACurrentMediaTime()
            
            if now - self.lastFPSUpdate >= 1.0 {
                let fps = Double(self.frameCount) / (now - self.lastFPSUpdate)
                if CameraLog.fps {
                    os_log("Pipeline FPS: %.2f", log: self.log, type: .debug, fps)
                }
                
                DispatchQueue.main.async {
                    self.metrics.pipelineFPS = fps
                }
                
                self.frameCount = 0
                self.lastFPSUpdate = now
            }
        }
    }
    
    func recordUIFrame() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.uiFrameCount += 1
            let now = CACurrentMediaTime()
            
            if now - self.uiStartTime >= 1.0 {
                let fps = Double(self.uiFrameCount) / (now - self.uiStartTime)
                
                DispatchQueue.main.async {
                    self.metrics.fps = fps
                }
                
                self.uiFrameCount = 0
                self.uiStartTime = now
            }
        }
    }

    func recordLatency(label: String, duration: TimeInterval) {
        // Логирование latency отключено (было слишком много логов)
        // os_log("%{public}@ latency %.2f ms", log: log, type: .debug, label, duration * 1000)
        
        DispatchQueue.main.async { [weak self] in
            self?.metrics.lastLatencies[label] = duration
        }
    }

    func recordSuggestion(_ suggestion: Suggestion?) {
        guard CameraLog.suggestions, let suggestion else { return }
        os_log("Suggestion: %{public}@ [%{public}@]", log: log, type: .debug, suggestion.text, String(describing: suggestion.type))
    }
    
    func setHeavyModelsEnabled(_ enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.metrics.heavyModelsEnabled = enabled
        }
    }
    
    func setCameraStable(_ stable: Bool, shakeLevel: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.metrics.cameraStable = stable
            self?.metrics.shakeLevel = shakeLevel
        }
    }
    
    func setActiveModule(_ module: String, active: Bool) {
        DispatchQueue.main.async { [weak self] in
            if active {
                self?.metrics.activeModules.insert(module)
            } else {
                self?.metrics.activeModules.remove(module)
            }
        }
    }
    
    func setAestheticScore(_ score: Double) {
        DispatchQueue.main.async { [weak self] in
            self?.metrics.aestheticScore = score
        }
    }
    
    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }
}

