//
//  Converter.swift
//  shafinMultitool
//
//  Created by Рустем on 03.11.2023.
//

import Foundation

class Converter {
    static let shared = Converter()
    
    func resolutionEnumToRawValues(Resolution: Resolutions) -> (Int, Int) {
        switch Resolution {
        case .hd:
            return (1280,720)
        case .fhd:
            return (1920,1080)
        case .uhd:
            return (3840,2160)
        }
    }
}
