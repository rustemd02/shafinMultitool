//
//  PreProductionThermalGovernor.swift
//  shafinMultitool
//
//  Created for performance optimization.
//

import Foundation
import UIKit

/// Manages thermal state and adjusts processing frequency to prevent device throttling
final class PreProductionThermalGovernor {
    
    static let shared = PreProductionThermalGovernor()
    
    // MARK: - Budget Configuration
    struct Budget {
        let visionFrequency: Double      // How many times per second to run Vision
        let speechRecognitionEnabled: Bool
        let warningsEnabled: Bool
    }
    
    // MARK: - Properties
    private var currentThermalState: ProcessInfo.ThermalState = .nominal
    private var lastBudgetUpdate: Date = .distantPast
    private let budgetUpdateInterval: TimeInterval = 2.0
    
    // Callbacks for state changes
    var onThermalStateChange: ((ProcessInfo.ThermalState) -> Void)?
    var onBudgetChange: ((Budget) -> Void)?
    
    // MARK: - Init
    private init() {
        // Register for thermal state notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateDidChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        currentThermalState = ProcessInfo.processInfo.thermalState
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Returns the current processing budget based on thermal state
    func currentBudget() -> Budget {
        let state = ProcessInfo.processInfo.thermalState
        currentThermalState = state
        
        switch state {
        case .nominal:
            // Full performance - 8 FPS for Vision
            return Budget(
                visionFrequency: 8.0,
                speechRecognitionEnabled: true,
                warningsEnabled: true
            )
            
        case .fair:
            // Slightly reduced - 5 FPS for Vision
            return Budget(
                visionFrequency: 5.0,
                speechRecognitionEnabled: true,
                warningsEnabled: true
            )
            
        case .serious:
            // Significantly reduced - 2 FPS for Vision, disable warnings
            return Budget(
                visionFrequency: 2.0,
                speechRecognitionEnabled: true,
                warningsEnabled: false
            )
            
        case .critical:
            // Minimal - 1 FPS for Vision, disable speech recognition
            return Budget(
                visionFrequency: 1.0,
                speechRecognitionEnabled: false,
                warningsEnabled: false
            )
            
        @unknown default:
            return Budget(
                visionFrequency: 4.0,
                speechRecognitionEnabled: true,
                warningsEnabled: true
            )
        }
    }
    
    /// Returns the Vision throttle interval based on current thermal state
    func visionThrottleInterval() -> CFTimeInterval {
        let budget = currentBudget()
        return 1.0 / budget.visionFrequency
    }
    
    /// Returns true if speech recognition should be active
    func shouldEnableSpeechRecognition() -> Bool {
        return currentBudget().speechRecognitionEnabled
    }
    
    /// Returns true if warnings overlay should be shown
    func shouldShowWarnings() -> Bool {
        return currentBudget().warningsEnabled
    }
    
    /// Returns a human-readable thermal state string
    func thermalStateDescription() -> String {
        switch currentThermalState {
        case .nominal: return "Normal"
        case .fair: return "Warm"
        case .serious: return "Hot"
        case .critical: return "Critical"
        @unknown default: return "Unknown"
        }
    }
    
    // MARK: - Private Methods
    
    @objc private func thermalStateDidChange(_ notification: Notification) {
        let newState = ProcessInfo.processInfo.thermalState
        if newState != currentThermalState {
            currentThermalState = newState
            
            // Log thermal state change
            print("⚠️ Thermal state changed to: \(thermalStateDescription())")
            
            // Notify listeners
            onThermalStateChange?(newState)
            onBudgetChange?(currentBudget())
        }
    }
}

