//
//  SettingsValues.swift
//  shafinMultitool
//
//  Created by Рустем on 31.10.2023.
//

import Foundation

struct SettingsValues {
    var resolution: [(width: Int, height: Int)]
    var fps: Int
    var wb: Int
    var iso: Int
    var speed: Double
}

enum Resolutions: CaseIterable {
    case hd, fhd, uhd
}

enum FPSValues: Int, CaseIterable {
    case fps24 = 24
    case fps25 = 25
    case fps30 = 30
    
}

enum SpeedValues: Double, CaseIterable {
    case speed05 = 0.5
    case speed07 = 0.7
    case speed1 = 1
    case speed15 = 1.5
}

extension CaseIterable where Self: Equatable {
    func next() -> Self {
        let all = Self.allCases
        let idx = all.firstIndex(of: self)!
        let next = all.index(after: idx)
        return all[next == all.endIndex ? all.startIndex : next]
    }
    
    static func withLabel(_ label: String) -> Self? {
        return self.allCases.first{ "\($0)" == label }
    }
}


