//
//  ThirdsGridOverlay.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

struct ThirdsGridOverlay: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let x1 = w / 3.0
        let x2 = 2.0 * w / 3.0
        let y1 = h / 3.0
        let y2 = 2.0 * h / 3.0

        p.move(to: CGPoint(x: x1, y: 0))
        p.addLine(to: CGPoint(x: x1, y: h))

        p.move(to: CGPoint(x: x2, y: 0))
        p.addLine(to: CGPoint(x: x2, y: h))

        p.move(to: CGPoint(x: 0, y: y1))
        p.addLine(to: CGPoint(x: w, y: y1))

        p.move(to: CGPoint(x: 0, y: y2))
        p.addLine(to: CGPoint(x: w, y: y2))

        return p
    }
}



