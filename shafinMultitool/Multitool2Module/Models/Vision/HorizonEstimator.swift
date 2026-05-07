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
        let rollDegrees = normalizeAngleDegrees(rollFromMotion * 180 / .pi)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
            if let observation = request.results?.first {
                let angleDegrees = normalizeAngleDegrees(Double(observation.angle * 180 / .pi))
                let disagreement = abs(angleDegrees - rollDegrees)
                if disagreement > 12, abs(rollDegrees) < 5 {
                    return stableMotionFallback(rollDegrees: rollDegrees, confidence: 0.12, isStable: isStable)
                }

                let agreementConfidence = max(0.0, 1.0 - (disagreement / 18.0))
                let blended = 0.2 * angleDegrees + 0.8 * rollDegrees
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

                let confidence = min(Double(observation.confidence), agreementConfidence)
                return (angle: CGFloat(output), confidence: CGFloat(confidence))
            }
        } catch {
            return stableMotionFallback(rollDegrees: rollDegrees, confidence: 0.1, isStable: isStable)
        }

        return stableMotionFallback(rollDegrees: rollDegrees, confidence: 0.1, isStable: isStable)
    }

    private func stableMotionFallback(rollDegrees: Double,
                                      confidence: Double,
                                      isStable: Bool) -> (angle: CGFloat, confidence: CGFloat) {
        let now = CACurrentMediaTime()
        lastUpdateTime = now
        let output = isStable && abs(rollDegrees) < 1.5 ? 0 : rollDegrees
        lastOutputDegrees = output
        return (angle: CGFloat(output), confidence: CGFloat(confidence))
    }

    private func normalizeAngleDegrees(_ degrees: Double) -> Double {
        var value = degrees
        while value > 90 { value -= 180 }
        while value < -90 { value += 180 }
        return value
    }
}

