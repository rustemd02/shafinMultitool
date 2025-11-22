//
//  KalmanFilter.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation

struct ScalarKalmanFilter {
    private var estimate: Double
    private var errorCovariance: Double
    private let processNoise: Double
    private let measurementNoise: Double

    init(initialEstimate: Double = 0,
         initialErrorCovariance: Double = 1,
         processNoise: Double = 1e-3,
         measurementNoise: Double = 1e-2) {
        self.estimate = initialEstimate
        self.errorCovariance = initialErrorCovariance
        self.processNoise = processNoise
        self.measurementNoise = measurementNoise
    }

    mutating func reset(to value: Double) {
        estimate = value
        errorCovariance = 1
    }

    mutating func update(measurement: Double) -> Double {
        // Predict
        errorCovariance += processNoise

        // Update
        let kalmanGain = errorCovariance / (errorCovariance + measurementNoise)
        estimate += kalmanGain * (measurement - estimate)
        errorCovariance = (1 - kalmanGain) * errorCovariance
        return estimate
    }

    var value: Double {
        estimate
    }
}



