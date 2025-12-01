//
//  PerformanceOverlayView.swift
//  shafinMultitool
//
//  Created by Claude on 22.11.2024.
//

import UIKit
import SnapKit

final class PerformanceOverlayView: UIView {

    // MARK: - UI Components
    private let containerStack: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 4
        stack.alignment = .leading
        stack.distribution = .fillEqually
        return stack
    }()

    private let fpsLabel = UILabel()
    private let frameTimeLabel = UILabel()
    private let cpuLabel = UILabel()
    private let memoryLabel = UILabel()
    private let thermalLabel = UILabel()
    private let gpuLabel = UILabel()
    private let droppedFramesLabel = UILabel()

    private var allLabels: [UILabel] {
        [fpsLabel, frameTimeLabel, cpuLabel, memoryLabel, thermalLabel, gpuLabel, droppedFramesLabel]
    }

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }

    // MARK: - Setup
    private func setupView() {
        backgroundColor = UIColor.black.withAlphaComponent(0.5)
        layer.cornerRadius = 8
        layer.masksToBounds = true

        addSubview(containerStack)
        containerStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(8)
        }

        allLabels.forEach { label in
            configureLabel(label)
            containerStack.addArrangedSubview(label)
        }

        // Set initial values
        updateMetrics(PerformanceMetrics(
            fps: 0,
            frameTime: 0,
            cpuUsage: 0,
            memoryUsage: 0,
            thermalState: "---",
            gpuUtilization: 0,
            droppedFrames: 0
        ))
    }

    private func configureLabel(_ label: UILabel) {
        label.font = UIFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.numberOfLines = 1
    }

    // MARK: - Public Methods
    func updateMetrics(_ metrics: PerformanceMetrics) {
        // FPS with color coding
        let fpsColor = colorForFPS(metrics.fps)
        fpsLabel.attributedText = createAttributedText(
            title: "FPS",
            value: String(format: "%.1f", metrics.fps),
            valueColor: fpsColor
        )

        // Frame Time
        let frameTimeColor = colorForFrameTime(metrics.frameTime)
        frameTimeLabel.attributedText = createAttributedText(
            title: "Frame",
            value: String(format: "%.2f ms", metrics.frameTime),
            valueColor: frameTimeColor
        )

        // CPU
        let cpuColor = colorForPercentage(metrics.cpuUsage)
        cpuLabel.attributedText = createAttributedText(
            title: "CPU",
            value: String(format: "%.1f%%", metrics.cpuUsage),
            valueColor: cpuColor
        )

        // Memory
        let memColor = colorForMemory(metrics.memoryUsage)
        memoryLabel.attributedText = createAttributedText(
            title: "MEM",
            value: String(format: "%.0f MB", metrics.memoryUsage),
            valueColor: memColor
        )

        // Thermal State
        let thermalColor = colorForThermalState(metrics.thermalState)
        thermalLabel.attributedText = createAttributedText(
            title: "Thermal",
            value: metrics.thermalState,
            valueColor: thermalColor
        )

        // GPU (estimated)
        let gpuColor = colorForPercentage(metrics.gpuUtilization)
        gpuLabel.attributedText = createAttributedText(
            title: "GPU~",
            value: String(format: "%.0f%%", metrics.gpuUtilization),
            valueColor: gpuColor
        )

        // Dropped Frames
        let droppedColor = metrics.droppedFrames > 0 ? UIColor.systemRed : UIColor.systemGreen
        droppedFramesLabel.attributedText = createAttributedText(
            title: "Dropped",
            value: "\(metrics.droppedFrames)",
            valueColor: droppedColor
        )
    }

    // MARK: - Helpers
    private func createAttributedText(title: String, value: String, valueColor: UIColor) -> NSAttributedString {
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor.lightGray,
            .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)
        ]

        let valueAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: valueColor,
            .font: UIFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        ]

        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: "\(title): ", attributes: titleAttributes))
        result.append(NSAttributedString(string: value, attributes: valueAttributes))

        return result
    }

    private func colorForFPS(_ fps: Double) -> UIColor {
        switch fps {
        case 55...: return .systemGreen
        case 45..<55: return .systemYellow
        case 30..<45: return .systemOrange
        default: return .systemRed
        }
    }

    private func colorForFrameTime(_ frameTime: Double) -> UIColor {
        switch frameTime {
        case 0..<18: return .systemGreen      // < 18ms = 55+ FPS
        case 18..<22: return .systemYellow    // 18-22ms = ~45-55 FPS
        case 22..<33: return .systemOrange    // 22-33ms = ~30-45 FPS
        default: return .systemRed            // > 33ms = < 30 FPS
        }
    }

    private func colorForPercentage(_ percentage: Double) -> UIColor {
        switch percentage {
        case 0..<50: return .systemGreen
        case 50..<75: return .systemYellow
        case 75..<90: return .systemOrange
        default: return .systemRed
        }
    }

    private func colorForMemory(_ memory: Double) -> UIColor {
        switch memory {
        case 0..<200: return .systemGreen
        case 200..<400: return .systemYellow
        case 400..<600: return .systemOrange
        default: return .systemRed
        }
    }

    private func colorForThermalState(_ state: String) -> UIColor {
        switch state {
        case "Normal": return .systemGreen
        case "Fair": return .systemYellow
        case "Serious": return .systemOrange
        case "Critical": return .systemRed
        default: return .white
        }
    }
}
