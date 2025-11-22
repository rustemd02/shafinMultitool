//
//  RealtimeScheduler.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation
import AVFoundation

enum SchedulerPriority: Comparable {
    case high
    case medium
    case low

    static func < (lhs: SchedulerPriority, rhs: SchedulerPriority) -> Bool {
        lhs.sortWeight < rhs.sortWeight
    }

    private var sortWeight: Int {
        switch self {
        case .high: return 0
        case .medium: return 1
        case .low: return 2
        }
    }
}

struct FrameContext {
    let pixelBuffer: CVPixelBuffer
    let timestamp: CMTime
    let orientation: CGImagePropertyOrientation
    let isStable: Bool
    let shakeLevel: Double
    let motionState: MotionState
}

protocol FrameConsumer: AnyObject {
    func consumeFrame(_ context: FrameContext)
}

final class RealtimeScheduler {
    struct Registration {
        weak var consumer: FrameConsumer?
        let priority: SchedulerPriority
        let minInterval: TimeInterval
        let requiresStability: Bool
        fileprivate var lastExecution: CFAbsoluteTime
    }

    private var registrations: [UUID: Registration] = [:]
    private let queue = DispatchQueue(label: "RealtimeScheduler", qos: .userInitiated)

    func register(consumer: FrameConsumer,
                  priority: SchedulerPriority,
                  targetFrequency: Double,
                  requiresStability: Bool = false) -> UUID {
        let minInterval = targetFrequency > 0 ? 1.0 / targetFrequency : .infinity
        let id = UUID()
        let registration = Registration(consumer: consumer,
                                        priority: priority,
                                        minInterval: minInterval,
                                        requiresStability: requiresStability,
                                        lastExecution: 0)
        queue.sync {
            registrations[id] = registration
        }
        return id
    }

    func unregister(id: UUID) {
        queue.sync {
            registrations[id] = nil
        }
    }

    func dispatch(context: FrameContext, budget: ThermalGovernor.Budget) {
        queue.async { [weak self] in
            self?.dispatchInternal(context: context, budget: budget)
        }
    }

    private func dispatchInternal(context: FrameContext, budget: ThermalGovernor.Budget) {
        var removals: [UUID] = []
        let now = CFAbsoluteTimeGetCurrent()
        
        Telemetry.shared.setHeavyModelsEnabled(budget.heavyModelsEnabled)

        let sorted = registrations.sorted { lhs, rhs in
            lhs.value.priority < rhs.value.priority
        }

        for (id, var registration) in sorted {
            guard let consumer = registration.consumer else {
                removals.append(id)
                continue
            }

            // 🔥 OPTIMIZATION DISABLED: игнорируем требование stability
            // if registration.requiresStability && !context.isStable {
            //     continue
            // }

            let minInterval = adjustedInterval(for: registration.priority,
                                               base: registration.minInterval,
                                               budget: budget)
            if now - registration.lastExecution < minInterval {
                continue
            }

            // 🔥 OPTIMIZATION DISABLED: низкий приоритет всегда выполняется
            // if registration.priority == .low && !budget.heavyModelsEnabled {
            //     continue
            // }

            registration.lastExecution = now
            registrations[id] = registration

            consumer.consumeFrame(context)
        }

        if !removals.isEmpty {
            removals.forEach { registrations[$0] = nil }
        }
    }

    private func adjustedInterval(for priority: SchedulerPriority,
                                  base: TimeInterval,
                                  budget: ThermalGovernor.Budget) -> TimeInterval {
        let maxFrequency: Double
        switch priority {
        case .high:
            maxFrequency = budget.highPriorityFrequency
        case .medium:
            maxFrequency = budget.mediumPriorityFrequency
        case .low:
            maxFrequency = budget.lowPriorityFrequency
        }
        guard maxFrequency > 0 else { return .greatestFiniteMagnitude }
        return max(base, 1.0 / maxFrequency)
    }
}


