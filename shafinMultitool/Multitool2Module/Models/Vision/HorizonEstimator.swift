//
//  HorizonEstimator.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import CoreMotion
import QuartzCore
import Vision

final class HorizonEstimator {
    private let request = VNDetectHorizonRequest()
    private var filter = ScalarKalmanFilter(processNoise: 5e-3, measurementNoise: 2e-2)
    private let motionManager = CMMotionManager()
    private var ema = ExponentialMovingAverage(alpha: 0.2)
    private var lastOutputDegrees: Double = 0
    private var lastUpdateTime: CFTimeInterval = 0

    init() {
        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0
        motionManager.startDeviceMotionUpdates()
    }

    func estimate(pixelBuffer: CVPixelBuffer,
                  orientation: CGImagePropertyOrientation,
                  isStable: Bool) -> (angle: CGFloat, confidence: CGFloat) {
        let rollFromMotion = motionManager.deviceMotion?.attitude.roll ?? 0

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
            if let observation = request.results?.first {
                let angleDegrees = Double(observation.angle * 180 / .pi)
                let blended = 0.7 * angleDegrees + 0.3 * (rollFromMotion * 180 / .pi)
                let k = filter.update(measurement: blended)
                let smoothed = ema.addSample(k)

                // Ограничим резкие скачки и квантуем до 0.5°; при нестабильности замораживаем выход
                let now = CACurrentMediaTime()
                let dt = max(1.0 / 30.0, now - lastUpdateTime)
                let maxStep = (isStable ? 10.0 : 4.0) * dt // при движении еще жёстче
                let delta = max(-maxStep, min(maxStep, smoothed - lastOutputDegrees))
                var output = isStable ? (lastOutputDegrees + delta) : lastOutputDegrees
                // deadband ±(isStable?0.5:1.0)°
                let dead = isStable ? 0.5 : 1.0
                if abs(output) < dead { output = 0 }
                // квантуем
                output = (output * 2.0).rounded() / 2.0
                lastOutputDegrees = output
                lastUpdateTime = now

                return (angle: CGFloat(output), confidence: CGFloat(observation.confidence))
            }
        } catch {
            return (angle: CGFloat(rollFromMotion * 180 / .pi), confidence: 0.1)
        }

        return (angle: CGFloat(rollFromMotion * 180 / .pi), confidence: 0.1)
    }
}


