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

    private(set) var shakeLevel: Double = 0.0
    private(set) var motionState: MotionState = .still {
        didSet {
            if oldValue != motionState {
                os_log("🏃 Motion state changed: %{public}@ → %{public}@ (shake=%.2f)", 
                       log: log, type: .info, 
                       String(describing: oldValue), 
                       String(describing: motionState), 
                       shakeLevel)
            }
        }
    }

    var isCameraStable: Bool {
        shakeLevel < 0.35 && motionState == .still
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
        
        // Логируем каждые 120 обновлений (~2 сек при 60Hz)
        if processCount % 120 == 0 {
            os_log("📊 Motion values: shake=%.3f gyro=%.3f accel=%.3f state=%{public}@",
                   log: log, type: .info, shakeLevel, gyro, accel, String(describing: motionState))
        }

        if shakeLevel < 0.2 {
            motionState = .still
        } else if gyro > 0.5 && accel < 0.4 {
            motionState = .panning
        } else {
            motionState = .moving
        }
    }
}



