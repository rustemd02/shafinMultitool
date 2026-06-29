//
//  ThermalGovernor.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation
import UIKit

enum ThermalBudgetTier {
    case unrestricted
    case constrained
    case critical
}

final class ThermalGovernor {
    typealias ThermalStateProvider = () -> ProcessInfo.ThermalState
    typealias BatteryLevelProvider = () -> Float

    struct Budget {
        var highPriorityFrequency: Double
        var mediumPriorityFrequency: Double
        var lowPriorityFrequency: Double
        var heavyModelsEnabled: Bool
    }

    private var lastBudget: Budget
    private let thermalStateProvider: ThermalStateProvider
    private let batteryLevelProvider: BatteryLevelProvider

    init(processInfo: ProcessInfo = .processInfo,
         batteryLevelProvider: @escaping BatteryLevelProvider = { UIDevice.current.batteryLevel }) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.thermalStateProvider = { processInfo.thermalState }
        self.batteryLevelProvider = batteryLevelProvider
        self.lastBudget = Self.budget(for: .nominal)
    }

    init(thermalStateProvider: @escaping ThermalStateProvider,
         batteryLevelProvider: @escaping BatteryLevelProvider) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.thermalStateProvider = thermalStateProvider
        self.batteryLevelProvider = batteryLevelProvider
        self.lastBudget = Self.budget(for: .nominal)
    }

    func currentTier() -> ThermalBudgetTier {
        switch thermalStateProvider() {
        case .nominal:
            return .unrestricted
        case .fair, .serious:
            return .constrained
        case .critical:
            return .critical
        @unknown default:
            return .constrained
        }
    }

    func currentBatteryLevel() -> Float {
        batteryLevelProvider()
    }

    func nextBudget() -> Budget {
        let thermalState = thermalStateProvider()
        let battery = batteryLevelProvider()
        let lowBattery = battery >= 0 && battery < 0.2

        let effectiveState: ProcessInfo.ThermalState
        if lowBattery {
            switch thermalState {
            case .critical:
                effectiveState = .critical
            default:
                effectiveState = .serious
            }
        } else {
            effectiveState = thermalState
        }

        lastBudget = Self.budget(for: effectiveState)
        return lastBudget
    }

    private static func budget(for state: ProcessInfo.ThermalState) -> Budget {
        switch state {
        case .nominal:
            return Budget(highPriorityFrequency: 6,
                          mediumPriorityFrequency: 2,
                          lowPriorityFrequency: 0.25,
                          heavyModelsEnabled: true)
        case .fair:
            return Budget(highPriorityFrequency: 4,
                          mediumPriorityFrequency: 1,
                          lowPriorityFrequency: 0,
                          heavyModelsEnabled: false)
        case .serious:
            return Budget(highPriorityFrequency: 2,
                          mediumPriorityFrequency: 0.5,
                          lowPriorityFrequency: 0,
                          heavyModelsEnabled: false)
        case .critical:
            return Budget(highPriorityFrequency: 0.5,
                          mediumPriorityFrequency: 0,
                          lowPriorityFrequency: 0,
                          heavyModelsEnabled: false)
        @unknown default:
            return Budget(highPriorityFrequency: 2,
                          mediumPriorityFrequency: 0.5,
                          lowPriorityFrequency: 0,
                          heavyModelsEnabled: false)
        }
    }
}
