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
            SIMD4<Float>(array[0], array[1], array[2], array[3]),
            SIMD4<Float>(array[4], array[5], array[6], array[7]),
            SIMD4<Float>(array[8], array[9], array[10], array[11]),
            SIMD4<Float>(array[12], array[13], array[14], array[15])
        )
    }
}
