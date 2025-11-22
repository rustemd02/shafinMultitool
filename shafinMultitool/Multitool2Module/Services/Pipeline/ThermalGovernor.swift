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
        self.lastBudget = Budget(highPriorityFrequency: 15,
                                 mediumPriorityFrequency: 10,
                                 lowPriorityFrequency: 1,
                                 heavyModelsEnabled: true)
    }

    init(thermalStateProvider: @escaping ThermalStateProvider,
         batteryLevelProvider: @escaping BatteryLevelProvider) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.thermalStateProvider = thermalStateProvider
        self.batteryLevelProvider = batteryLevelProvider
        self.lastBudget = Budget(highPriorityFrequency: 15,
                                 mediumPriorityFrequency: 10,
                                 lowPriorityFrequency: 1,
                                 heavyModelsEnabled: true)
    }

    func currentTier() -> ThermalBudgetTier {
        switch thermalStateProvider() {
        case .nominal, .fair:
            return .unrestricted
        case .serious:
            return .constrained
        case .critical:
            return .critical
        @unknown default:
            return .constrained
        }
    }

    func nextBudget() -> Budget {
        // 🔥 THERMAL OPTIMIZATION DISABLED: всегда максимальная производительность!
        // Игнорируем thermal state и battery level
        
        let tier = currentTier()  // Оставляем для логов
        let battery = batteryLevelProvider()
        let lowBattery = battery >= 0 && battery < 0.2
        
        // Всегда возвращаем максимальный бюджет
        lastBudget = Budget(highPriorityFrequency: 15,
                            mediumPriorityFrequency: 10,
                            lowPriorityFrequency: 2,  // Увеличено с 1 до 2
                            heavyModelsEnabled: true)  // 🔥 ВСЕГДА true!
        
        // Логируем что игнорируем thermal
        if tier != .unrestricted || lowBattery {
            // В продакшене здесь бы были ограничения, но сейчас игнорируем
        }
        
        return lastBudget
    }
}


