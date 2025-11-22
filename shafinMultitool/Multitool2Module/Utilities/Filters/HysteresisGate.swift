//
//  HysteresisGate.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation

final class HysteresisGate {
    private let enableThreshold: Double
    private let disableThreshold: Double
    private var state: Bool = false

    init(enableThreshold: Double, disableThreshold: Double) {
        precondition(enableThreshold >= disableThreshold)
        self.enableThreshold = enableThreshold
        self.disableThreshold = disableThreshold
    }

    func update(with value: Double) -> Bool {
        if state {
            if value < disableThreshold {
                state = false
            }
        } else {
            if value > enableThreshold {
                state = true
            }
        }
        return state
    }

    var isEnabled: Bool { state }
}



