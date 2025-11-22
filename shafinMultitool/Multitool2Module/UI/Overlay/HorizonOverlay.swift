//
//  HorizonOverlay.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

struct HorizonOverlay: Shape {
    let angle: CGFloat
    let confidence: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = max(rect.width, rect.height)
        let radians = Angle(degrees: angle).radians

        let dx = cos(radians) * radius
        let dy = sin(radians) * radius
        let start = CGPoint(x: center.x - dx, y: center.y + dy)
        let end = CGPoint(x: center.x + dx, y: center.y - dy)
        path.move(to: start)
        path.addLine(to: end)
        return path
    }
}



