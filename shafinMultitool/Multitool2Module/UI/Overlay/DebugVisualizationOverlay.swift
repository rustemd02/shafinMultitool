//
//  DebugVisualizationOverlay.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

struct DebugVisualizationOverlay: View {
    let detrDetections: [DETRDetection]
    let visionSubjects: [VisionSubject]
    let saliencyCenter: CGPoint?
    let canvasSize: CGSize

    var body: some View {
        ZStack {
            // DETR детекции (тонкие зелёные рамки с подписями)
            ForEach(detrDetections) { detection in
                let rect = convertBBox(detection.boundingBox, canvasSize: canvasSize)
                
                Rectangle()
                    .path(in: rect)
                    .stroke(Color.green.opacity(0.7), lineWidth: 1.5)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(detection.label)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                    Text(String(format: "%.0f%%", detection.confidence * 100))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(3)
                .background(Color.green.opacity(0.8))
                .cornerRadius(4)
                .position(x: rect.minX + 4, y: rect.minY - 20)
            }
            
            // Vision субъекты (синие рамки)
            ForEach(visionSubjects) { subject in
                let rect = convertBBox(subject.boundingBox, canvasSize: canvasSize)
                
                Rectangle()
                    .path(in: rect)
                    .stroke(Color.blue.opacity(0.7), lineWidth: 2)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(subject.isFace ? "Face" : "Person")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white)
                    Text(String(format: "%.0f%%", subject.confidence * 100))
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(3)
                .background(Color.blue.opacity(0.8))
                .cornerRadius(4)
                .position(x: rect.minX + 4, y: rect.minY - 20)
            }
            
            // Saliency центр (фиолетовая точка)
            if let center = saliencyCenter {
                let x = center.x * canvasSize.width
                let y = (1 - center.y) * canvasSize.height
                
                Circle()
                    .fill(Color.purple.opacity(0.8))
                    .frame(width: 12, height: 12)
                    .position(x: x, y: y)
                
                Text("Saliency")
                    .font(.system(size: 9))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Color.purple.opacity(0.8))
                    .cornerRadius(3)
                    .position(x: x + 25, y: y)
            }
            
            // Трети (яркие линии в debug)
            ThirdsGridOverlay()
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 2]))
                .foregroundColor(Color.cyan.opacity(0.5))
        }
    }
    
    private func convertBBox(_ bbox: CGRect, canvasSize: CGSize) -> CGRect {
        // Vision bbox: origin в левом нижнем углу, Y растёт вверх
        let x = bbox.origin.x * canvasSize.width
        let y = (1 - bbox.origin.y - bbox.height) * canvasSize.height
        let width = bbox.width * canvasSize.width
        let height = bbox.height * canvasSize.height
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct VisionSubject: Identifiable {
    let id = UUID()
    let boundingBox: CGRect
    let isFace: Bool
    let confidence: Float
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        DebugVisualizationOverlay(
            detrDetections: [
                DETRDetection(boundingBox: CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.3), label: "cup", confidence: 0.92),
                DETRDetection(boundingBox: CGRect(x: 0.6, y: 0.5, width: 0.15, height: 0.2), label: "bottle", confidence: 0.85)
            ],
            visionSubjects: [
                VisionSubject(boundingBox: CGRect(x: 0.1, y: 0.6, width: 0.25, height: 0.35), isFace: true, confidence: 0.95)
            ],
            saliencyCenter: CGPoint(x: 0.5, y: 0.5),
            canvasSize: CGSize(width: 400, height: 600)
        )
    }
}


