//
//  ThermalGovernor.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation
import UIKit

enum ThermalBudgetTier: String, Equatable, Sendable {
    case unrestricted
    case constrained
    case critical
}

/// The only performance mode the camera surface may expose. The thermal and
/// scheduler owners publish this value; the view never derives it from a
/// fixture identifier, a timer, or a raw thermal reason.
enum CameraEffectivePerformanceMode: String, Equatable, Sendable {
    case nominal
    case eco
}

/// Runtime performance truth shared by CameraManager, AnalysisPipeline and
/// the presentation owner. Keeping this as a small immutable value avoids a
/// per-frame SwiftUI dependency while still making an effective degradation
/// transition observable at the boundary.
struct CameraRuntimePerformanceSnapshot: Equatable, Sendable {
    let mode: CameraEffectivePerformanceMode
    let thermalTier: ThermalBudgetTier
    let budget: ThermalGovernor.Budget

    var isLimited: Bool { mode == .eco }

    static let nominal = Self(
        mode: .nominal,
        thermalTier: .unrestricted,
        budget: .nominal
    )

    init(mode: CameraEffectivePerformanceMode,
         thermalTier: ThermalBudgetTier,
         budget: ThermalGovernor.Budget) {
        self.mode = mode
        self.thermalTier = thermalTier
        self.budget = budget
    }

    init(budget: ThermalGovernor.Budget,
         thermalTier: ThermalBudgetTier = .constrained) {
        self.init(
            mode: budget.heavyModelsEnabled ? .nominal : .eco,
            thermalTier: thermalTier,
            budget: budget
        )
    }
}

/// Notification-backed store is intentionally process-local. CameraManager
/// and AnalysisPipeline already own their governors and scheduler, so this is
/// the narrow bridge that lets CameraViewModel observe their *effective*
/// result without reaching into either private owner or duplicating cadence
/// policy. Publications are deduplicated to avoid layout churn on every frame.
final class CameraRuntimePerformanceStore: @unchecked Sendable {
    static let shared = CameraRuntimePerformanceStore()

    static let notification = Notification.Name("CameraRuntimePerformanceDidChange")
    static let snapshotUserInfoKey = "snapshot"

    private let lock = NSLock()
    private var snapshotStorage = CameraRuntimePerformanceSnapshot.nominal

    var currentSnapshot: CameraRuntimePerformanceSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return snapshotStorage
    }

    @discardableResult
    func publish(_ snapshot: CameraRuntimePerformanceSnapshot,
                 notificationCenter: NotificationCenter = .default) -> Bool {
        lock.lock()
        guard snapshotStorage != snapshot else {
            lock.unlock()
            return false
        }
        snapshotStorage = snapshot
        lock.unlock()

        notificationCenter.post(
            name: Self.notification,
            object: self,
            userInfo: [Self.snapshotUserInfoKey: snapshot]
        )
        return true
    }

#if DEBUG
    func resetForTesting(notificationCenter: NotificationCenter = .default) {
        _ = publish(.nominal, notificationCenter: notificationCenter)
    }
#endif
}

final class ThermalGovernor {
    typealias ThermalStateProvider = () -> ProcessInfo.ThermalState
    typealias BatteryLevelProvider = () -> Float

    struct Budget: Equatable, Sendable {
        let highPriorityFrequency: Double
        let mediumPriorityFrequency: Double
        let lowPriorityFrequency: Double
        let heavyModelsEnabled: Bool

        static let nominal = Self(
            highPriorityFrequency: 6,
            mediumPriorityFrequency: 2,
            lowPriorityFrequency: 0.25,
            heavyModelsEnabled: true
        )

    }

    private let thermalStateProvider: ThermalStateProvider
    private let batteryLevelProvider: BatteryLevelProvider

    init(processInfo: ProcessInfo = .processInfo,
         batteryLevelProvider: @escaping BatteryLevelProvider = { UIDevice.current.batteryLevel }) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.thermalStateProvider = { processInfo.thermalState }
        self.batteryLevelProvider = batteryLevelProvider
    }

    init(thermalStateProvider: @escaping ThermalStateProvider,
         batteryLevelProvider: @escaping BatteryLevelProvider) {
        UIDevice.current.isBatteryMonitoringEnabled = true
        self.thermalStateProvider = thermalStateProvider
        self.batteryLevelProvider = batteryLevelProvider
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

        let budget = Self.budget(for: effectiveState)
        CameraRuntimePerformanceStore.shared.publish(
            CameraRuntimePerformanceSnapshot(
                budget: budget,
                thermalTier: Self.effectiveTier(for: effectiveState)
            )
        )
        return budget
    }

    private static func effectiveTier(for state: ProcessInfo.ThermalState) -> ThermalBudgetTier {
        switch state {
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
