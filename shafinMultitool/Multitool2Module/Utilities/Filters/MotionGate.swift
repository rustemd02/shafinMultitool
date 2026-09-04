//
//  MotionGate.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation
import CoreMotion
import os.log

extension MotionState: @unchecked Sendable {}

struct MotionSnapshot: Equatable, Sendable {
    let motionState: MotionState
    let shakeLevel: Double
    let isStable: Bool
}

/// M2-015: one committed state transition, stamped by the gate's clock.
/// Movement timestamps are retained (bounded history) for WAIT gating and
/// before/after capture.
struct MotionTransition: Equatable, Sendable {
    let state: MotionState
    let timestamp: Date
    let shakeLevel: Double
}

final class MotionGate: @unchecked Sendable {
    private let motionManager = CMMotionManager()
    private var gyroEMA = ExponentialMovingAverage(alpha: 0.3)
    private var accelEMA = ExponentialMovingAverage(alpha: 0.3)
    private let queue = OperationQueue()
    private let log = OSLog(subsystem: "com.multitool2.motion", category: "MotionGate")
    private let stateLock = NSLock()
    private var processCount: Int = 0
    private var pendingState: MotionState?
    private var pendingStateSampleCount: Int = 0
    private var publishedSnapshot = MotionSnapshot(motionState: .still,
                                                   shakeLevel: 0.0,
                                                   isStable: true)

    /// M2-015: injectable clock — deterministic tests drive the gate with a
    /// synthetic time sequence.
    private var clock: () -> Date = { Date() }
    private var transitions: [MotionTransition] = []
    private var stateStartedAt: Date = Date()

    private let stillEnterShakeThreshold = 0.18
    private let stillExitShakeThreshold = 0.42
    private let panningEnterGyroThreshold = 0.85
    private let panningExitGyroThreshold = 0.45
    private let panningMaxAccelThreshold = 0.40

    var shakeLevel: Double {
        snapshot().shakeLevel
    }

    var motionState: MotionState {
        snapshot().motionState
    }

    var isCameraStable: Bool {
        snapshot().isStable
    }

    init() {
        configureQueue()
        startMotionUpdates()
    }

#if DEBUG
    init(startMotionUpdates: Bool, clock: (() -> Date)? = nil) {
        configureQueue()
        if let clock {
            self.clock = clock
            stateStartedAt = clock()
        }
        if startMotionUpdates {
            self.startMotionUpdates()
        }
    }
#endif

    func snapshot() -> MotionSnapshot {
        stateLock.lock()
        defer { stateLock.unlock() }
        return publishedSnapshot
    }

    // MARK: - M2-015 movement timeline

    /// Committed state transitions, oldest first (bounded to the last 32).
    func timeline() -> [MotionTransition] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return transitions
    }

    /// When the current state began.
    func stateStartTimestamp() -> Date? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return stateStartedAt
    }

    /// Seconds spent in the current state as of `asOf`.
    func dwellSeconds(asOf: Date) -> TimeInterval? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard stateStartedAt <= asOf else { return nil }
        return asOf.timeIntervalSince(stateStartedAt)
    }

    private func configureQueue() {
        queue.name = "MotionGateQueue"
        queue.maxConcurrentOperationCount = 1
    }

    deinit {
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        motionManager.stopGyroUpdates()
    }

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.process(motion: motion)
        }
    }

    private func process(motion: CMDeviceMotion) {
        let gyroMagnitude = hypot(hypot(motion.rotationRate.x, motion.rotationRate.y), motion.rotationRate.z)
        let accelMagnitude = hypot(hypot(motion.userAcceleration.x, motion.userAcceleration.y), motion.userAcceleration.z)
        processSample(gyroMagnitude: gyroMagnitude, accelMagnitude: accelMagnitude)
    }

    #if DEBUG
    func processSyntheticSample(gyroMagnitude: Double, accelMagnitude: Double) {
        processSample(gyroMagnitude: gyroMagnitude, accelMagnitude: accelMagnitude)
    }
    #endif

    private func processSample(gyroMagnitude: Double, accelMagnitude: Double) {
        var verboseLog: (shake: Double, gyro: Double, accel: Double, state: MotionState)?
        var stateChangeLog: (oldState: MotionState, newState: MotionState, shake: Double)?

        stateLock.lock()
        processCount += 1
        let gyro = gyroEMA.addSample(gyroMagnitude)
        let accel = accelEMA.addSample(accelMagnitude)
        let shake = min(1.0, gyro * 0.7 + accel * 0.3)
        let currentState = publishedSnapshot.motionState
        let motionLoggingEnabled = CameraLog.motion

        // Verbose motion diagnostics are opt-in; otherwise they drown live hint logs.
        if motionLoggingEnabled, processCount % 120 == 0 {
            verboseLog = (shake: shake,
                          gyro: gyro,
                          accel: accel,
                          state: currentState)
        }

        let desiredState = desiredMotionState(currentState: currentState,
                                               gyro: gyro,
                                               accel: accel,
                                               shake: shake)
        let nextState = applyStateWithHysteresis(desiredState,
                                                 currentState: currentState)
        publishedSnapshot = MotionSnapshot(motionState: nextState,
                                           shakeLevel: shake,
                                           isStable: nextState == .still && shake < stillExitShakeThreshold)
        if nextState != currentState {
            let timestamp = clock()
            transitions.append(MotionTransition(state: nextState,
                                                timestamp: timestamp,
                                                shakeLevel: shake))
            if transitions.count > 32 {
                transitions.removeFirst(transitions.count - 32)
            }
            stateStartedAt = timestamp
        }

        if motionLoggingEnabled, currentState != nextState {
            stateChangeLog = (oldState: currentState,
                              newState: nextState,
                              shake: shake)
        }
        stateLock.unlock()

        if let verboseLog {
            os_log("📊 Motion values: shake=%.3f gyro=%.3f accel=%.3f state=%{public}@",
                   log: log,
                   type: .debug,
                   verboseLog.shake,
                   verboseLog.gyro,
                   verboseLog.accel,
                   String(describing: verboseLog.state))
        }

        if let stateChangeLog {
            os_log("🏃 Motion state changed: %{public}@ → %{public}@ (shake=%.2f)",
                   log: log,
                   type: .debug,
                   String(describing: stateChangeLog.oldState),
                   String(describing: stateChangeLog.newState),
                   stateChangeLog.shake)
        }
    }

    private func desiredMotionState(currentState: MotionState,
                                    gyro: Double,
                                    accel: Double,
                                    shake: Double) -> MotionState {
        switch currentState {
        case .still:
            if shake <= stillExitShakeThreshold {
                return .still
            }
            if gyro > panningEnterGyroThreshold && accel < panningMaxAccelThreshold {
                return .panning
            }
            return .moving
        case .moving:
            if shake < stillEnterShakeThreshold {
                return .still
            }
            if gyro > panningEnterGyroThreshold && accel < panningMaxAccelThreshold {
                return .panning
            }
            return .moving
        case .panning:
            if shake < stillEnterShakeThreshold {
                return .still
            }
            if gyro < panningExitGyroThreshold || accel >= panningMaxAccelThreshold {
                return .moving
            }
            return .panning
        }
    }

    private func applyStateWithHysteresis(_ desiredState: MotionState,
                                          currentState: MotionState) -> MotionState {
        guard desiredState != currentState else {
            pendingState = nil
            pendingStateSampleCount = 0
            return currentState
        }

        if pendingState == desiredState {
            pendingStateSampleCount += 1
        } else {
            pendingState = desiredState
            pendingStateSampleCount = 1
        }

        let requiredSamples: Int
        switch desiredState {
        case .still:
            requiredSamples = 12
        case .moving:
            requiredSamples = 8
        case .panning:
            requiredSamples = 12
        }
        guard pendingStateSampleCount >= requiredSamples else { return currentState }

        pendingState = nil
        pendingStateSampleCount = 0
        return desiredState
    }
}
