//
//  DirectionArrows.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

//
//  DirectionArrows.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

enum ArrowDirection {
    case up, down, left, right
    case rotateLeft, rotateRight
}

struct DirectionArrows: View {
    let directions: [ArrowDirection]
    let magnitude: CGFloat // 0...1
    
    var body: some View {
        ZStack {
            ForEach(Array(directions.enumerated()), id: \.offset) { index, direction in
                arrowView(for: direction)
                    .opacity(Double(magnitude))
                    .animation(.easeInOut(duration: 0.3), value: magnitude)
            }
        }
    }
    
    @ViewBuilder
    private func arrowView(for direction: ArrowDirection) -> some View {
        switch direction {
        case .up:
            VStack {
                arrowShape()
                    .rotationEffect(Angle(degrees: 0))
                Spacer()
            }
            .padding(.top, 80)
            
        case .down:
            VStack {
                Spacer()
                arrowShape()
                    .rotationEffect(Angle(degrees: 180))
            }
            .padding(.bottom, 80)
            
        case .left:
            HStack {
                arrowShape()
                    .rotationEffect(Angle(degrees: -90))
                Spacer()
            }
            .padding(.leading, 40)
            
        case .right:
            HStack {
                Spacer()
                arrowShape()
                    .rotationEffect(Angle(degrees: 90))
            }
            .padding(.trailing, 40)
            
        case .rotateLeft:
            VStack {
                Spacer()
                rotationIndicator(clockwise: false)
            }
            .padding(.bottom, 120)
            
        case .rotateRight:
            VStack {
                Spacer()
                rotationIndicator(clockwise: true)
            }
            .padding(.bottom, 120)
        }
    }
    
    private func arrowShape() -> some View {
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }
    
    private func rotationIndicator(clockwise: Bool) -> some View {
        Image(systemName: clockwise ? "arrow.clockwise.circle.fill" : "arrow.counterclockwise.circle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Helper для конвертации подсказок в направления

extension DirectionArrows {
    static func directions(for suggestion: Suggestion?, features: CoachingFeatures?) -> ([ArrowDirection], CGFloat) {
        guard let suggestion = suggestion, let features = features else {
            return ([], 0)
        }

        var arrows: [ArrowDirection] = []
        var magnitude: CGFloat = 0.5

        switch suggestion.type {
        case .composition:
            let horizontal = features.composition.horizontalOffset
            let vertical = features.composition.verticalOffset
            
            if abs(horizontal) > 0.18 {
                arrows.append(horizontal > 0 ? .left : .right)
                magnitude = min(1.0, abs(horizontal) * 2.0)
            }
            
            if abs(vertical) > 0.18 {
                // vertical > 0 = объект ниже центра → стрелка вниз (опустить камеру)
                // vertical < 0 = объект выше центра → стрелка вверх (поднять камеру)
                arrows.append(vertical > 0 ? .down : .up)
                magnitude = max(magnitude, min(1.0, abs(vertical) * 2.0))
            }
            
        case .lighting:
            // Для освещения можно показать поворот камеры
            if features.lighting.backlightIndex > 0.35 {
                arrows.append(.rotateLeft)
                magnitude = min(1.0, features.lighting.backlightIndex)
            }

        default:
            break
        }
        
        return (arrows, magnitude)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        DirectionArrows(directions: [.up, .right], magnitude: 0.8)
    }
}


