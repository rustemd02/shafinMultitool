//
//  SceneExecutionRuntimeContracts.swift
//  shafinMultitool
//
//  Created by Codex on 15.06.2026.
//

import Foundation
import UIKit
import Darwin

enum SceneGeneratorExecutionMode: String, Codable, Equatable {
    case monolithic
    case chunkedThermalAware
}

struct SceneGeneratorMobileExecutionPolicy: Codable, Equatable {
    var mode: SceneGeneratorExecutionMode
    var cooldownOnSeriousMs: Int
    var cooldownOnCriticalMs: Int
    var maxChunkAttempts: Int
    var checkpointEnabled: Bool

    static let chunkedThermalAwareDefault = SceneGeneratorMobileExecutionPolicy(
        mode: .chunkedThermalAware,
        cooldownOnSeriousMs: 15_000,
        cooldownOnCriticalMs: 30_000,
        maxChunkAttempts: 2,
        checkpointEnabled: true
    )

    static let monolithicDefault = SceneGeneratorMobileExecutionPolicy(
        mode: .monolithic,
        cooldownOnSeriousMs: 15_000,
        cooldownOnCriticalMs: 30_000,
        maxChunkAttempts: 1,
        checkpointEnabled: false
    )
}

enum SceneExecutionThermalState: String, Codable, Equatable {
    case nominal
    case fair
    case serious
    case critical
    case unknown

    init(processState: ProcessInfo.ThermalState) {
        switch processState {
        case .nominal:
            self = .nominal
        case .fair:
            self = .fair
        case .serious:
            self = .serious
        case .critical:
            self = .critical
        @unknown default:
            self = .unknown
        }
    }
}

struct SceneExecutionResourceSnapshot: Codable, Equatable {
    var timestamp: Date
    var thermalState: SceneExecutionThermalState
    var batteryLevel: Float?
    var memoryMB: Double?
}

enum SceneExecutionEventKind: String, Codable, Equatable {
    case thermalContinue = "thermal_continue"
    case thermalCooldownStarted = "thermal_cooldown_started"
    case thermalCooldownFinished = "thermal_cooldown_finished"
    case criticalTelemetryObserved = "critical_telemetry_observed"
    case chunkStarted = "chunk_started"
    case chunkCompleted = "chunk_completed"
    case chunkFailed = "chunk_failed"
    case checkpointWritten = "checkpoint_written"
}

struct SceneExecutionEvent: Codable, Equatable, Identifiable {
    var id: String
    var timestamp: Date
    var kind: SceneExecutionEventKind
    var sceneID: String?
    var chunkID: String?
    var chunkIndex: Int?
    var thermalState: SceneExecutionThermalState?
    var batteryLevel: Float?
    var memoryMB: Double?
    var cooldownMs: Int?
    var checkpointFileName: String?
    var note: String?

    init(
        timestamp: Date,
        kind: SceneExecutionEventKind,
        sceneID: String? = nil,
        chunkID: String? = nil,
        chunkIndex: Int? = nil,
        snapshot: SceneExecutionResourceSnapshot? = nil,
        cooldownMs: Int? = nil,
        checkpointFileName: String? = nil,
        note: String? = nil
    ) {
        self.id = [
            kind.rawValue,
            sceneID ?? "scene",
            chunkID ?? "chunk",
            String(chunkIndex ?? -1),
            String(Int(timestamp.timeIntervalSince1970 * 1000)),
        ].joined(separator: "::")
        self.timestamp = timestamp
        self.kind = kind
        self.sceneID = sceneID
        self.chunkID = chunkID
        self.chunkIndex = chunkIndex
        self.thermalState = snapshot?.thermalState
        self.batteryLevel = snapshot?.batteryLevel
        self.memoryMB = snapshot?.memoryMB
        self.cooldownMs = cooldownMs
        self.checkpointFileName = checkpointFileName
        self.note = note
    }
}

struct SceneExecutionCheckpoint: Codable, Equatable, Identifiable {
    var id: String { fileName }
    var fileName: String
    var stage: String
    var sceneID: String?
    var chunkID: String?
    var chunkIndex: Int?
    var timestamp: Date
}

struct SceneExecutionTrace: Codable, Equatable {
    var executionMode: SceneGeneratorExecutionMode
    var policy: SceneGeneratorMobileExecutionPolicy?
    var events: [SceneExecutionEvent]
    var checkpoints: [SceneExecutionCheckpoint]
    var notes: [String]

    init(
        executionMode: SceneGeneratorExecutionMode,
        policy: SceneGeneratorMobileExecutionPolicy? = nil,
        events: [SceneExecutionEvent] = [],
        checkpoints: [SceneExecutionCheckpoint] = [],
        notes: [String] = []
    ) {
        self.executionMode = executionMode
        self.policy = policy
        self.events = events
        self.checkpoints = checkpoints
        self.notes = notes
    }
}

struct SceneGeneratorExecutionSupport {
    var makeSnapshot: () -> SceneExecutionResourceSnapshot
    var sleep: (_ milliseconds: Int) async -> Void
    var writeCheckpoint: (_ fileName: String, _ payload: Data) throws -> Void
    var now: () -> Date

    static let live = SceneGeneratorExecutionSupport(
        makeSnapshot: {
            UIDevice.current.isBatteryMonitoringEnabled = true
            return SceneExecutionResourceSnapshot(
                timestamp: Date(),
                thermalState: SceneExecutionThermalState(processState: ProcessInfo.processInfo.thermalState),
                batteryLevel: UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : nil,
                memoryMB: SceneGeneratorExecutionSupport.memoryUsageMB()
            )
        },
        sleep: { milliseconds in
            let bounded = max(milliseconds, 0)
            guard bounded > 0 else { return }
            try? await Task.sleep(nanoseconds: UInt64(bounded) * 1_000_000)
        },
        writeCheckpoint: { _, _ in },
        now: { Date() }
    )

    static func memoryUsageMB() -> Double? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }
}
