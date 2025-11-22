//
//  DebugOverlay.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import SwiftUI

struct DebugMetrics {
    var fps: Double = 0
    var pipelineFPS: Double = 0
    var thermalState: String = "nominal"
    var batteryLevel: Float = 1.0
    var heavyModelsEnabled: Bool = true
    var lastLatencies: [String: TimeInterval] = [:]
    var cameraStable: Bool = false
    var shakeLevel: Double = 0
    var activeModules: Set<String> = []
    var aestheticScore: Double = 0  // 🎨 Aesthetic score (0-10)
}

struct DebugOverlay: View {
    let metrics: DebugMetrics
    let isVisible: Bool
    
    var body: some View {
        if isVisible {
            VStack(alignment: .leading, spacing: 4) {
                // FPS
                HStack {
                    Text("FPS:")
                        .fontWeight(.semibold)
                    Text(String(format: "UI: %.1f | Pipeline: %.1f", metrics.fps, metrics.pipelineFPS))
                        .foregroundColor(fpsColor(metrics.pipelineFPS))
                }
                
                // Thermal & Battery
                HStack {
                    Text("Thermal:")
                        .fontWeight(.semibold)
                    Text(metrics.thermalState)
                        .foregroundColor(thermalColor(metrics.thermalState))
                    
                    Spacer().frame(width: 16)
                    
                    Text("Battery:")
                        .fontWeight(.semibold)
                    Text(String(format: "%.0f%%", metrics.batteryLevel * 100))
                        .foregroundColor(batteryColor(metrics.batteryLevel))
                }
                
                // Heavy models status
                HStack {
                    Text("Heavy:")
                        .fontWeight(.semibold)
                    Circle()
                        .fill(metrics.heavyModelsEnabled ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(metrics.heavyModelsEnabled ? "ON" : "OFF")
                }
                
                // Camera stability
                HStack {
                    Text("Stable:")
                        .fontWeight(.semibold)
                    Circle()
                        .fill(metrics.cameraStable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(String(format: "%.2f", metrics.shakeLevel))
                }
                
                // Aesthetic Score 🎨
                HStack {
                    Text("Aesthetic:")
                        .fontWeight(.semibold)
                    Text(String(format: "%.2f / 10", metrics.aestheticScore))
                        .foregroundColor(aestheticColor(metrics.aestheticScore))
                    
                    // Звёздочки визуализация
                    HStack(spacing: 2) {
                        ForEach(0..<5) { index in
                            Image(systemName: aestheticStarIcon(for: index, score: metrics.aestheticScore))
                                .font(.system(size: 10))
                                .foregroundColor(aestheticStarColor(for: index, score: metrics.aestheticScore))
                        }
                    }
                }
                
                // Active modules закомментировано - вызывало мерцание
                // if !metrics.activeModules.isEmpty {
                //     HStack {
                //         Text("Active:")
                //             .fontWeight(.semibold)
                //         Text(metrics.activeModules.sorted().joined(separator: ", "))
                //             .lineLimit(1)
                //             .truncationMode(.tail)
                //     }
                // }
                
                // Latencies
                if !metrics.lastLatencies.isEmpty {
                    Divider()
                        .background(Color.white.opacity(0.3))
                    
                    Text("Latencies (ms):")
                        .fontWeight(.semibold)
                        .padding(.top, 2)
                    
                    ForEach(Array(metrics.lastLatencies.keys.sorted()), id: \.self) { key in
                        if let latency = metrics.lastLatencies[key] {
                            HStack {
                                Text(key + ":")
                                    .font(.caption)
                                Spacer()
                                Text(String(format: "%.1f", latency * 1000))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(latencyColor(latency))
                            }
                        }
                    }
                }
            }
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.white)
            .padding(12)
            .background(.black.opacity(0.75))
            .cornerRadius(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
        }
    }
    
    private func fpsColor(_ fps: Double) -> Color {
        if fps >= 50 { return .green }
        if fps >= 30 { return .yellow }
        return .red
    }
    
    private func thermalColor(_ state: String) -> Color {
        switch state {
        case "nominal", "fair": return .green
        case "serious": return .orange
        case "critical": return .red
        default: return .white
        }
    }
    
    private func batteryColor(_ level: Float) -> Color {
        if level >= 0.5 { return .green }
        if level >= 0.2 { return .yellow }
        return .red
    }
    
    private func latencyColor(_ latency: TimeInterval) -> Color {
        let ms = latency * 1000
        if ms < 50 { return .green }
        if ms < 100 { return .yellow }
        return .red
    }
    
    private func aestheticColor(_ score: Double) -> Color {
        if score >= 7.0 { return .green }
        if score >= 5.0 { return .yellow }
        if score >= 3.0 { return .orange }
        return .red
    }
    
    private func aestheticStarIcon(for index: Int, score: Double) -> String {
        // Конвертируем score (0-10) в звёзды (0-5)
        let stars = score / 2.0
        let threshold = Double(index)
        
        if stars >= threshold + 1.0 {
            return "star.fill"
        } else if stars >= threshold + 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
    
    private func aestheticStarColor(for index: Int, score: Double) -> Color {
        let stars = score / 2.0
        let threshold = Double(index)
        
        if stars >= threshold + 0.5 {
            return aestheticColor(score)
        } else {
            return Color.white.opacity(0.3)
        }
    }
}

// Обёртка для наблюдения за Telemetry
struct DebugMetricsView: View {
    @ObservedObject private var telemetry = Telemetry.shared
    let isVisible: Bool
    
    var body: some View {
        DebugOverlay(metrics: telemetry.metrics, isVisible: isVisible)
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        DebugOverlay(metrics: DebugMetrics(
            fps: 59.8,
            pipelineFPS: 14.2,
            thermalState: "fair",
            batteryLevel: 0.65,
            heavyModelsEnabled: true,
            lastLatencies: [
                "Vision": 0.012,
                "Horizon": 0.008,
                "DETR": 0.125,
                "Aesthetic": 0.085
            ],
            cameraStable: true,
            shakeLevel: 0.12,
            activeModules: ["Vision", "Horizon", "Lighting"],
            aestheticScore: 7.5
        ), isVisible: true)
    }
}


