//
//  SceneExecutionRuntimeContracts.swift
//  shafinMultitool
//
//  Created by Codex on 15.06.2026.
//

import Foundation
import UIKit
import Darwin

/// Request-owned failures are deliberately smaller than the parser/transport
/// diagnostics. The owner maps these stable categories to localized copy.
enum SceneGenerationFailureKind: String, CaseIterable, Codable, Equatable {
    case emptyInput = "empty_input"
    case arNotReady = "ar_not_ready"
    case cameraPosition = "camera_position"
    case parse = "parse"
    case malformed = "malformed"
    case network = "network"
    case quota = "quota"
    case model = "model"
    case persistence = "persistence"
    case compilation = "compilation"
    case timeout = "timeout"
    case cancelled = "cancelled"
    case background = "background"
    case remoteExpired = "remote_expired"
    case remoteDisabled = "remote_disabled"

    var isRetryable: Bool {
        switch self {
        case .arNotReady, .cameraPosition, .network, .quota, .model,
             .persistence, .compilation, .timeout, .background:
            return true
        case .emptyInput, .parse, .malformed, .cancelled, .remoteExpired, .remoteDisabled:
            return false
        }
    }
}

/// The one domain state for a Scene Generator request. Editable input and its
/// sole identityless failure (`emptyInput`) are pre-request states. Every
/// post-submit state, including every retryable/terminal failure, carries both
/// the request UUID and epoch.
struct SceneGenerationRequestState: Codable, Equatable {
    enum Phase: String, CaseIterable, Codable, Equatable {
        case idle
        case input
        case validating
        case clarification
        case accepted
        case leader
        case queued
        case generating
        case cancelling
        case paused
        case backgrounded
        case retryableFailure = "retryable_failure"
        case terminalFailure = "terminal_failure"
        case success
    }

    var phase: Phase
    var requestID: UUID?
    var epoch: UInt?
    var stage: SceneGenerationStage?
    var failure: SceneGenerationFailureKind?
    var clarificationMessage: String?

    init(
        phase: Phase,
        requestID: UUID? = nil,
        epoch: UInt? = nil,
        stage: SceneGenerationStage? = nil,
        failure: SceneGenerationFailureKind? = nil,
        clarificationMessage: String? = nil
    ) {
        self.phase = phase
        self.requestID = requestID
        self.epoch = epoch
        self.stage = stage
        self.failure = failure
        self.clarificationMessage = clarificationMessage
    }

    static let idle = Self(phase: .idle)

    static func input() -> Self {
        Self(phase: .input)
    }

    static func validating(requestID: UUID, epoch: UInt) -> Self {
        Self(phase: .validating, requestID: requestID, epoch: epoch)
    }

    static func clarification(
        requestID: UUID,
        epoch: UInt,
        message: String
    ) -> Self {
        Self(
            phase: .clarification,
            requestID: requestID,
            epoch: epoch,
            clarificationMessage: message
        )
    }

    static func accepted(requestID: UUID, epoch: UInt) -> Self {
        Self(phase: .accepted, requestID: requestID, epoch: epoch)
    }

    static func leader(requestID: UUID, epoch: UInt) -> Self {
        Self(phase: .leader, requestID: requestID, epoch: epoch)
    }

    static func queued(requestID: UUID, epoch: UInt) -> Self {
        Self(phase: .queued, requestID: requestID, epoch: epoch)
    }

    static func generating(
        requestID: UUID,
        epoch: UInt,
        stage: SceneGenerationStage
    ) -> Self {
        Self(phase: .generating, requestID: requestID, epoch: epoch, stage: stage)
    }

    static func cancelling(requestID: UUID, epoch: UInt) -> Self {
        Self(phase: .cancelling, requestID: requestID, epoch: epoch)
    }

    static func paused(requestID: UUID, epoch: UInt) -> Self {
        Self(phase: .paused, requestID: requestID, epoch: epoch)
    }

    static func backgrounded(requestID: UUID, epoch: UInt) -> Self {
        Self(phase: .backgrounded, requestID: requestID, epoch: epoch)
    }

    static func retryableFailure(
        requestID: UUID,
        epoch: UInt,
        failure: SceneGenerationFailureKind
    ) -> Self {
        Self(phase: .retryableFailure, requestID: requestID, epoch: epoch, failure: failure)
    }

    static func terminalFailure(
        requestID: UUID,
        epoch: UInt,
        failure: SceneGenerationFailureKind
    ) -> Self {
        Self(phase: .terminalFailure, requestID: requestID, epoch: epoch, failure: failure)
    }

    /// The only identityless failure: submit-time validation of an empty
    /// draft, before a request UUID/epoch exists.
    static func emptyInputFailure() -> Self {
        Self(phase: .terminalFailure, failure: .emptyInput)
    }

    static func success(requestID: UUID, epoch: UInt) -> Self {
        Self(phase: .success, requestID: requestID, epoch: epoch)
    }

    var isExecutionInFlight: Bool {
        switch phase {
        case .validating, .accepted, .leader, .queued, .generating,
             .cancelling, .paused, .backgrounded:
            return true
        case .idle, .input, .clarification, .retryableFailure,
             .terminalFailure, .success:
            return false
        }
    }

    var allowedNextPhases: Set<Phase> {
        Self.transitionTable[phase] ?? []
    }

    /// Closed phase-level transition table. Payload and identity rules are
    /// checked by `canTransition` below.
    static let transitionTable: [Phase: Set<Phase>] = [
        .idle: [.input],
        .input: [.validating, .terminalFailure, .idle],
        .validating: [.clarification, .accepted, .cancelling, .retryableFailure, .terminalFailure],
        .clarification: [.input, .accepted, .validating, .idle],
        .accepted: [.queued, .cancelling, .retryableFailure],
        .leader: [.generating, .paused, .backgrounded, .cancelling, .retryableFailure, .terminalFailure],
        .queued: [.leader, .paused, .backgrounded, .cancelling, .retryableFailure, .terminalFailure],
        .generating: [.clarification, .paused, .backgrounded, .cancelling, .retryableFailure, .terminalFailure, .success],
        .cancelling: [.input, .idle, .backgrounded, .terminalFailure],
        .paused: [.queued, .generating, .backgrounded, .cancelling, .retryableFailure, .terminalFailure],
        .backgrounded: [.accepted, .queued, .generating, .paused, .cancelling, .retryableFailure, .terminalFailure, .input, .idle],
        .retryableFailure: [.validating, .input, .idle],
        .terminalFailure: [.input, .idle],
        .success: [.input, .idle],
    ]

    static func canTransition(
        from: SceneGenerationRequestState,
        to: SceneGenerationRequestState
    ) -> Bool {
        guard isWellFormed(from), isWellFormed(to) else { return false }

        if from.phase == to.phase {
            switch from.phase {
            case .input:
                return true
            case .generating:
                guard from.requestID == to.requestID,
                      from.epoch == to.epoch,
                      let fromStage = from.stage,
                      let toStage = to.stage else { return false }
                return stageRank(toStage) >= stageRank(fromStage)
            case .cancelling:
                return from.requestID == to.requestID && from.epoch == to.epoch
            default:
                return false
            }
        }

        guard transitionTable[from.phase]?.contains(to.phase) == true else { return false }

        // Input starts a fresh request identity. The terminal/success/input
        // edges intentionally clear the old identity before the next submit.
        if from.phase == .input, to.phase == .validating {
            return to.requestID != nil && to.epoch != nil
        }
        if to.phase == .idle || (to.phase == .input && to.requestID == nil) {
            return to.epoch == nil && to.requestID == nil
        }

        return from.requestID == to.requestID && from.epoch == to.epoch
    }

    static func validateTransition(
        from: SceneGenerationRequestState,
        to: SceneGenerationRequestState
    ) -> Bool {
        canTransition(from: from, to: to)
    }

    static func transition(
        from: SceneGenerationRequestState,
        to: SceneGenerationRequestState
    ) -> SceneGenerationRequestState? {
        canTransition(from: from, to: to) ? to : nil
    }

    private static func isWellFormed(_ state: SceneGenerationRequestState) -> Bool {
        guard (state.requestID == nil) == (state.epoch == nil) else { return false }

        switch state.phase {
        case .idle:
            return state.requestID == nil
                && state.stage == nil
                && state.failure == nil
                && state.clarificationMessage == nil
        case .input:
            return state.requestID == nil
                && state.epoch == nil
                && state.stage == nil
                && state.failure == nil
                && state.clarificationMessage == nil
        case .validating, .accepted, .leader, .queued, .cancelling,
             .paused, .backgrounded:
            return state.requestID != nil
                && state.stage == nil
                && state.failure == nil
                && state.clarificationMessage == nil
        case .generating:
            return state.requestID != nil
                && state.stage != nil
                && state.failure == nil
                && state.clarificationMessage == nil
        case .clarification:
            return state.requestID != nil
                && state.stage == nil
                && state.failure == nil
                && state.clarificationMessage?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .retryableFailure:
            return state.requestID != nil
                && state.epoch != nil
                && state.stage == nil
                && state.failure?.isRetryable == true
                && state.clarificationMessage == nil
        case .terminalFailure:
            guard let failure = state.failure else { return false }
            let hasIdentity = state.requestID != nil && state.epoch != nil
            let isPreRequestEmptyInput = failure == .emptyInput && !hasIdentity
            let isPostSubmitFailure = failure != .emptyInput && hasIdentity
            return state.stage == nil
                && (isPreRequestEmptyInput || isPostSubmitFailure)
                && failure.isRetryable == false
                && state.clarificationMessage == nil
        case .success:
            return state.requestID != nil
                && state.stage == nil
                && state.failure == nil
                && state.clarificationMessage == nil
        }
    }

    private static func stageRank(_ stage: SceneGenerationStage) -> Int {
        switch stage {
        case .reading: 0
        case .planning: 1
        case .placing: 2
        }
    }
}

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
