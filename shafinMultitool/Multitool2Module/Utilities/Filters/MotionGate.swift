//
//  MotionGate.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation
import CoreMotion
import os.log

final class MotionGate {
    private let motionManager = CMMotionManager()
    private var gyroEMA = ExponentialMovingAverage(alpha: 0.3)
    private var accelEMA = ExponentialMovingAverage(alpha: 0.3)
    private let queue = OperationQueue()
    private let log = OSLog(subsystem: "com.multitool2.motion", category: "MotionGate")
    private var processCount: Int = 0
    private var pendingState: MotionState?
    private var pendingStateSampleCount: Int = 0

    private let stillEnterShakeThreshold = 0.18
    private let stillExitShakeThreshold = 0.42
    private let panningEnterGyroThreshold = 0.85
    private let panningExitGyroThreshold = 0.45
    private let panningMaxAccelThreshold = 0.40

    private(set) var shakeLevel: Double = 0.0
    private(set) var motionState: MotionState = .still {
        didSet {
            if CameraLog.motion, oldValue != motionState {
                os_log("🏃 Motion state changed: %{public}@ → %{public}@ (shake=%.2f)", 
                       log: log, type: .debug,
                       String(describing: oldValue), 
                       String(describing: motionState), 
                       shakeLevel)
            }
        }
    }

    var isCameraStable: Bool {
        shakeLevel < stillExitShakeThreshold && motionState == .still
    }

    init() {
        queue.name = "MotionGateQueue"
        startMotionUpdates()
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
        processCount += 1
        let gyroMagnitude = hypot(hypot(motion.rotationRate.x, motion.rotationRate.y), motion.rotationRate.z)
        let accelMagnitude = hypot(hypot(motion.userAcceleration.x, motion.userAcceleration.y), motion.userAcceleration.z)

        let gyro = gyroEMA.addSample(gyroMagnitude)
        let accel = accelEMA.addSample(accelMagnitude)

        shakeLevel = min(1.0, gyro * 0.7 + accel * 0.3)
        
        // Verbose motion diagnostics are opt-in; otherwise they drown live hint logs.
        if CameraLog.motion, processCount % 120 == 0 {
            os_log("📊 Motion values: shake=%.3f gyro=%.3f accel=%.3f state=%{public}@",
                   log: log, type: .debug, shakeLevel, gyro, accel, String(describing: motionState))
        }

        let desiredState = desiredMotionState(gyro: gyro, accel: accel, shake: shakeLevel)
        applyStateWithHysteresis(desiredState)
    }

    private func desiredMotionState(gyro: Double, accel: Double, shake: Double) -> MotionState {
        switch motionState {
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

    private func applyStateWithHysteresis(_ desiredState: MotionState) {
        guard desiredState != motionState else {
            pendingState = nil
            pendingStateSampleCount = 0
            return
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
        guard pendingStateSampleCount >= requiredSamples else { return }

        motionState = desiredState
        pendingState = nil
        pendingStateSampleCount = 0
    }
}
