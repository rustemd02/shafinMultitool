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
    
    func kelvinToWhiteBalanceGains(kelvin: Double) -> (red: Float, green: Float, blue: Float)? {
        let redGain: Float
        let greenGain: Float
        let blueGain: Float
        
        if kelvin <= 6600 {
            let temperature = (kelvin - 2000) / 4600.0
            redGain = 1.0
            greenGain = Float(max(1.0, min(2.5 - temperature, 1.0)))
            blueGain = Float(2.5 - temperature)
        } else {
            let temperature = (kelvin - 6600) / 3400.0
            redGain = Float(max(1.0, min(3.5 - temperature, 1.0)))
            greenGain = 1.0
            blueGain = 1.0
        }
        return (redGain, greenGain, blueGain)
    }

}
