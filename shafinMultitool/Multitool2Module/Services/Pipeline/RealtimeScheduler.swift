//
//  RealtimeScheduler.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation
import AVFoundation

/// Fail-closed analysis signal. The analysis owner can publish this through
/// the scheduler boundary without sending model/debug details to the view.
enum CameraAnalysisFailure: String, Equatable, Sendable {
    case unavailable
    case failed
}

enum CameraAnalysisRuntimeSignal {
    static let failureNotification = Notification.Name("CameraAnalysisDidFail")
    static let failureUserInfoKey = "failure"
    static let generationUserInfoKey = "generation"

    static func publishFailure(_ failure: CameraAnalysisFailure,
                               generation: UInt64? = nil,
                               notificationCenter: NotificationCenter = .default) {
        var userInfo: [AnyHashable: Any] = [failureUserInfoKey: failure]
        if let generation {
            userInfo[generationUserInfoKey] = generation
        }
        notificationCenter.post(
            name: failureNotification,
            object: nil,
            userInfo: userInfo
        )
    }
}

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
    /// Immutable capture-side lens identity. This is the lens that produced
    /// the buffer, not a later mutable CameraManager selection.
    let lensID: String?
    /// Preview geometry captured with the same orientation as the buffer.
    /// Missing geometry remains explicit so subject-bound verification can
    /// fail closed instead of inventing an identity transform.
    let previewGeometry: CameraPreviewGeometry?
    let isStable: Bool
    let shakeLevel: Double
    let motionState: MotionState
    let capturedAt: Date
    /// Capture-side epoch assigned by CameraManager. This is deliberately
    /// separate from AnalysisPipeline's lifecycle generation: a frame keeps
    /// the camera input/lens epoch that actually produced its pixels.
    let captureGeneration: UInt64

    init(pixelBuffer: CVPixelBuffer,
         timestamp: CMTime,
         orientation: CGImagePropertyOrientation,
         lensID: String? = nil,
         previewGeometry: CameraPreviewGeometry? = nil,
         isStable: Bool,
         shakeLevel: Double,
         motionState: MotionState,
         capturedAt: Date = Date(),
         captureGeneration: UInt64 = 0) {
        self.pixelBuffer = pixelBuffer
        self.timestamp = timestamp
        self.orientation = orientation
        self.lensID = lensID
        self.previewGeometry = previewGeometry
        self.isStable = isStable
        self.shakeLevel = shakeLevel
        self.motionState = motionState
        self.capturedAt = capturedAt
        self.captureGeneration = captureGeneration
    }
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
#if DEBUG
    private var drainGateForTesting: DispatchSemaphore?
#endif

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

    /// Completes after every scheduler block enqueued before this fence has run.
    /// The fence does not retain or invoke any consumer by itself.
    func drainAndWait() async {
#if DEBUG
        let drainGate = queue.sync { drainGateForTesting }
#endif
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async {
#if DEBUG
                drainGate?.wait()
#endif
                continuation.resume()
            }
        }
    }

    func dispatch(context: FrameContext, budget: ThermalGovernor.Budget) {
        queue.async { [weak self] in
            self?.dispatchInternal(context: context, budget: budget)
        }
    }

#if DEBUG
    var registrationCountForTesting: Int {
        queue.sync { registrations.count }
    }

    func setDrainGateForTesting(_ gate: DispatchSemaphore?) {
        queue.sync {
            drainGateForTesting = gate
        }
    }

    func dispatchSynchronouslyForTesting(context: FrameContext, budget: ThermalGovernor.Budget) {
        queue.sync {
            dispatchInternal(context: context, budget: budget)
        }
    }
#endif

    private func dispatchInternal(context: FrameContext, budget: ThermalGovernor.Budget) {
        var removals: [UUID] = []
        let now = CFAbsoluteTimeGetCurrent()

        // The scheduler receives the effective budget from CameraManager. It
        // republishes that result so a ViewModel observing this boundary sees
        // the same cadence/availability decision that governs dispatch.
        let tier: ThermalBudgetTier = {
            guard !budget.heavyModelsEnabled else { return .unrestricted }
            return budget.highPriorityFrequency <= 0.5 ? .critical : .constrained
        }()
        _ = CameraRuntimePerformanceStore.shared.publish(
            CameraRuntimePerformanceSnapshot(budget: budget, thermalTier: tier)
        )
        
        Telemetry.shared.setHeavyModelsEnabled(budget.heavyModelsEnabled)

        let sorted = registrations.sorted { lhs, rhs in
            lhs.value.priority < rhs.value.priority
        }

        for (id, var registration) in sorted {
            guard let consumer = registration.consumer else {
                removals.append(id)
                continue
            }

            if registration.requiresStability && !context.isStable {
                continue
            }

            if registration.priority == .low && !budget.heavyModelsEnabled {
                continue
            }

            let minInterval = adjustedInterval(for: registration.priority,
                                               base: registration.minInterval,
                                               budget: budget)
            if now - registration.lastExecution < minInterval {
                continue
            }

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
