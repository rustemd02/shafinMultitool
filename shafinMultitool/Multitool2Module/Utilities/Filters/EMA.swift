//
//  EMA.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation

struct ExponentialMovingAverage {
    private let alpha: Double
    private var currentValue: Double?

    init(halfLife: TimeInterval, frameInterval: TimeInterval) {
        precondition(halfLife > 0)
        let decay = pow(0.5, frameInterval / halfLife)
        self.alpha = 1 - decay
    }

    init(alpha: Double) {
        self.alpha = max(0.0, min(alpha, 1.0))
    }

    mutating func reset() {
        currentValue = nil
    }

    mutating func addSample(_ value: Double) -> Double {
        if let current = currentValue {
            let updated = alpha * value + (1 - alpha) * current
            currentValue = updated
            return updated
        } else {
            currentValue = value
            return value
        }
    }

    var value: Double? {
        currentValue
    }
}



