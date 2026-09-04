//
//  HorizonEstimator.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import CoreMotion
import QuartzCore
import Vision

/// M2-013 TechnicalFeatureOwner: explicit horizon result. `isAvailable == false`
/// means no honest horizon claim — consumers must treat the source as
/// unavailable instead of reading the (suppressed) angle.
struct HorizonEstimate: Equatable {
    let angleDegrees: Double
    let confidence: Double
    let isAvailable: Bool
    /// True when the user's intentional tilt suppressed the correction.
    let suppressedByIntent: Bool

    static func unavailable(suppressedByIntent: Bool = false) -> HorizonEstimate {
        HorizonEstimate(angleDegrees: 0, confidence: 0, isAvailable: false,
                        suppressedByIntent: suppressedByIntent)
    }
}

/// Intentional-style override: the user deliberately composed a tilted frame;
/// horizon correction is suppressed while the override is active.
enum HorizonIntentOverride: Equatable, Sendable {
    case none
    case intentional
}

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

    // MARK: - M2-013 pure normalization (unit-tested)

    /// Rotations applied by each capture orientation tag, in degrees (CW).
    static func orientationRotationDegrees(_ orientation: CGImagePropertyOrientation) -> Double {
        switch orientation {
        case .up, .upMirrored: return 0
        case .right, .rightMirrored: return 90
        case .down, .downMirrored: return 180
        case .left, .leftMirrored: return 270
        @unknown default: return 0
        }
    }

    /// Maps a Vision-measured horizon angle (in the ORIENTED image) to a
    /// scene-space angle whose SIGN is stable regardless of the capture
    /// orientation tag: the same physical tilt yields the same scene angle
    /// under every orientation. Line angles are modulo 180°, normalized to
    /// (−90, 90].
    static func normalizedSceneAngle(observationAngleDegrees: Double,
                                     orientation: CGImagePropertyOrientation) -> Double {
        var value = observationAngleDegrees - orientationRotationDegrees(orientation)
        while value > 90 { value -= 180 }
        while value <= -90 { value += 180 }
        return value
    }

    // MARK: - Estimate

    func estimate(pixelBuffer: CVPixelBuffer,
                  orientation: CGImagePropertyOrientation,
                  isStable: Bool,
                  intentOverride: HorizonIntentOverride = .none) -> HorizonEstimate {
        // Intentional override: the user composed the tilt on purpose —
        // suppress correction and report the source as intentionally
        // unavailable rather than advising against it.
        if case .intentional = intentOverride {
            lastUpdateTime = CACurrentMediaTime()
            return HorizonEstimate(angleDegrees: lastOutputDegrees,
                                   confidence: 0,
                                   isAvailable: false,
                                   suppressedByIntent: true)
        }

        let rollFromMotion = motionManager.deviceMotion?.attitude.roll ?? 0
        let rollDegrees = normalizeAngleDegrees(rollFromMotion * 180 / .pi)

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: orientation,
                                            options: [:])
        do {
            try handler.perform([request])
            if let observation = request.results?.first {
                // M2-013: sign-stable scene angle through the capture
                // orientation (the rotation tag no longer flips the sign).
                let angleDegrees = Self.normalizedSceneAngle(
                    observationAngleDegrees: Double(observation.angle * 180 / .pi),
                    orientation: orientation
                )
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
                // M2-013: low-confidence horizon remains unavailable instead
                // of a low-confidence angle claim.
                guard confidence >= 0.2 else {
                    return HorizonEstimate(angleDegrees: output,
                                           confidence: confidence,
                                           isAvailable: false,
                                           suppressedByIntent: false)
                }
                return HorizonEstimate(angleDegrees: output,
                                       confidence: confidence,
                                       isAvailable: true,
                                       suppressedByIntent: false)
            }
        } catch {
            return unavailableFallback(rollDegrees: rollDegrees)
        }

        // Absent horizon observation: explicitly unavailable — no invented
        // angle from the motion fallback.
        return unavailableFallback(rollDegrees: rollDegrees)
    }

    private func unavailableFallback(rollDegrees: Double) -> HorizonEstimate {
        lastUpdateTime = CACurrentMediaTime()
        lastOutputDegrees = 0
        return HorizonEstimate(angleDegrees: 0, confidence: 0, isAvailable: false,
                               suppressedByIntent: false)
    }

    private func stableMotionFallback(rollDegrees: Double,
                                      confidence: Double,
                                      isStable: Bool) -> HorizonEstimate {
        let now = CACurrentMediaTime()
        lastUpdateTime = now
        let output = isStable && abs(rollDegrees) < 1.5 ? 0 : rollDegrees
        lastOutputDegrees = output
        guard confidence >= 0.2 else {
            return HorizonEstimate(angleDegrees: output, confidence: confidence,
                                   isAvailable: false, suppressedByIntent: false)
        }
        return HorizonEstimate(angleDegrees: output, confidence: confidence,
                               isAvailable: true, suppressedByIntent: false)
    }

    private func normalizeAngleDegrees(_ degrees: Double) -> Double {
        var value = degrees
        while value > 90 { value -= 180 }
        while value < -90 { value += 180 }
        return value
    }
}
