//
//  Converter.swift
//  shafinMultitool
//
//  Created by Рустем on 03.11.2023.
//

import UIKit
import simd

class Converter {
    static let shared = Converter()
    
    func cgFloatValuesFromUIColor(color: UIColor) -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        guard let components = color.cgColor.components else { return (0.0,0.0,0.0,0.0) }
        return (components[0], components[1], components[2], components[3])
    }
    
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
    
    func kelvinToWhiteBalanceGains(kelvin: Double) -> (red: Double, green: Double, blue: Double)? {
        var r = 0
        var g = 0
        var b = 0

        // Температура должна быть в диапазоне от 1000 до 40000 градусов
        var tmpKelvin = kelvin
        if tmpKelvin < 1000 { tmpKelvin = 1000 }
        if tmpKelvin > 40000 { tmpKelvin = 40000 }

        // Все вычисления требуют tmpKelvin / 100, так что можно обойтись однократным преобразованием
        tmpKelvin = tmpKelvin / 100.0

        // Вычисляем красный
        if tmpKelvin <= 66 {
            r = 255
        } else {
            // Примечание: значение R-квадрата для этого приближения 0,988
            var tmpCalc = tmpKelvin - 60.0
            tmpCalc = 329.698727446 * pow(tmpCalc, -0.1332047592)
            r = Int(tmpCalc)
            if r < 0 { r = 0 }
            if r > 255 { r = 255 }
        }

        // Затем зелёный
        if tmpKelvin <= 66 {
            // Примечание: значение R-квадрата для этого приближения 0,996
            var tmpCalc = tmpKelvin
            tmpCalc = 99.4708025861 * log(tmpCalc) - 161.1195681661
            g = Int(tmpCalc)
            if g < 0 { g = 0 }
            if g > 255 { g = 255 }
        } else {
            // Примечание: значение R-квадрата для этого приближения 0,987
            var tmpCalc = tmpKelvin - 60.0
            tmpCalc = 288.1221695283 * pow(tmpCalc, -0.0755148492)
            g = Int(tmpCalc)
            if g < 0 { g = 0 }
            if g > 255 { g = 255 }
        }

        // Наконец, синий
        if tmpKelvin >= 66 {
            b = 255
        } else if tmpKelvin <= 19 {
            b = 0
        } else {
            // Примечание: значение R-квадрата для этого приближения 0,998
            var tmpCalc = tmpKelvin - 10.0
            tmpCalc = 138.5177312231 * log(tmpCalc) - 305.0447927307
            b = Int(tmpCalc)
            if b < 0 { b = 0 }
            if b > 255 { b = 255 }
        }
        let maxColorValue = 255.0
        let minNormalizedValue = 1.0
        let maxNormalizedValue = 4.0
        
        let normalizedRed = minNormalizedValue + ((Double(r) / maxColorValue) * (maxNormalizedValue - minNormalizedValue))
        let normalizedGreen = minNormalizedValue + ((Double(g) / maxColorValue) * (maxNormalizedValue - minNormalizedValue))
        let normalizedBlue = minNormalizedValue + ((Double(b) / maxColorValue) * (maxNormalizedValue - minNormalizedValue))
        
        print(normalizedRed,normalizedGreen,normalizedBlue)
        return (red: normalizedRed, green: normalizedGreen, blue: normalizedBlue)
    }
}

extension simd_float4x4 {
    func toArray() -> [Float] {
        return [
            columns.0.x, columns.0.y, columns.0.z, columns.0.w,
            columns.1.x, columns.1.y, columns.1.z, columns.1.w,
            columns.2.x, columns.2.y, columns.2.z, columns.2.w,
            columns.3.x, columns.3.y, columns.3.z, columns.3.w
        ]
    }

    static func fromArray(_ array: [Float]) -> simd_float4x4 {
        precondition(array.count == 16, "Array must contain exactly 16 elements for simd_float4x4 conversion")

        return simd_float4x4(
            float4(array[0], array[1], array[2], array[3]),
            float4(array[4], array[5], array[6], array[7]),
            float4(array[8], array[9], array[10], array[11]),
            float4(array[12], array[13], array[14], array[15])
        )
    }
}
