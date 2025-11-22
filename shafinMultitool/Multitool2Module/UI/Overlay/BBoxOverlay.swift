//
//  BBoxOverlay.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

struct BBoxOverlay: Shape {
    let boundingBox: CGRect
    let canvasSize: CGSize

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let converted = convert(boundingBox: boundingBox, in: rect.size)
        path.addRoundedRect(in: converted, cornerSize: CGSize(width: 12, height: 12))
        return path
    }

    private func convert(boundingBox: CGRect, in size: CGSize) -> CGRect {
        let width = boundingBox.width * size.width
        let height = boundingBox.height * size.height
        let x = boundingBox.minX * size.width
        let y = (1 - boundingBox.maxY) * size.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}



