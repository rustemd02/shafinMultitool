//
//  PerformanceMonitor.swift
//  shafinMultitool
//
//  Created by Claude on 22.11.2024.
//

import Foundation
import UIKit
import QuartzCore

struct PerformanceMetrics {
    var fps: Double
    var frameTime: Double // ms
    var cpuUsage: Double // %
    var memoryUsage: Double // MB
    var thermalState: String
    var gpuUtilization: Double // % (estimated)
    var droppedFrames: Int
}

final class PerformanceMonitor {

    static let shared = PerformanceMonitor()

    // MARK: - Properties
    private var displayLink: CADisplayLink?
    private var frameTimestamps: [CFTimeInterval] = []
    private var frameTimes: [Double] = []
    private var lastTimestamp: CFTimeInterval = 0
    private var droppedFramesCount: Int = 0
    private var expectedFrameTime: Double = 1.0 / 60.0

    private let updateInterval: TimeInterval = 5.0
    private var updateTimer: Timer?
    private var onMetricsUpdate: ((PerformanceMetrics) -> Void)?

    private let metricsQueue = DispatchQueue(label: "performanceMonitor.metrics", qos: .utility)

    // MARK: - Init
    private init() {}

    // MARK: - Public Methods
    func startMonitoring(onUpdate: @escaping (PerformanceMetrics) -> Void) {
        self.onMetricsUpdate = onUpdate

        // Start display link for FPS tracking
        displayLink = CADisplayLink(target: self, selector: #selector(displayLinkTick))
        displayLink?.add(to: .main, forMode: .common)

        // Start timer for metrics aggregation every 5 seconds
        updateTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] _ in
            self?.aggregateAndReportMetrics()
        }

        // Register for thermal state notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        displayLink?.invalidate()
        displayLink = nil
        updateTimer?.invalidate()
        updateTimer = nil
        frameTimestamps.removeAll()
        frameTimes.removeAll()
        NotificationCenter.default.removeObserver(self)
    }

    func recordFrame() {
        // Called externally from ARSession delegate for more accurate AR frame tracking
        let now = CACurrentMediaTime()
        if lastTimestamp > 0 {
            let frameTime = (now - lastTimestamp) * 1000 // Convert to ms
            metricsQueue.async { [weak self] in
                self?.frameTimes.append(frameTime)
            }
        }
        lastTimestamp = now
    }

    // MARK: - Private Methods
    @objc private func displayLinkTick(_ link: CADisplayLink) {
        let timestamp = link.timestamp

        metricsQueue.async { [weak self] in
            guard let self = self else { return }
            self.frameTimestamps.append(timestamp)

            // Detect dropped frames
            if self.frameTimestamps.count > 1 {
                let lastIndex = self.frameTimestamps.count - 1
                let delta = self.frameTimestamps[lastIndex] - self.frameTimestamps[lastIndex - 1]
                if delta > self.expectedFrameTime * 1.5 {
                    self.droppedFramesCount += Int(delta / self.expectedFrameTime) - 1
                }
            }

            // Keep only last 5 seconds of data
            let cutoffTime = timestamp - self.updateInterval
            self.frameTimestamps = self.frameTimestamps.filter { $0 > cutoffTime }
        }
    }

    @objc private func thermalStateChanged(_ notification: Notification) {
        // Thermal state change is handled in aggregateAndReportMetrics
    }

    private func aggregateAndReportMetrics() {
        metricsQueue.async { [weak self] in
            guard let self = self else { return }

            let metrics = PerformanceMetrics(
                fps: self.calculateAverageFPS(),
                frameTime: self.calculateAverageFrameTime(),
                cpuUsage: self.getCPUUsage(),
                memoryUsage: self.getMemoryUsage(),
                thermalState: self.getThermalStateString(),
                gpuUtilization: self.estimateGPUUtilization(),
                droppedFrames: self.droppedFramesCount
            )

            // Reset dropped frames counter
            self.droppedFramesCount = 0
            self.frameTimes.removeAll()

            DispatchQueue.main.async { [weak self] in
                self?.onMetricsUpdate?(metrics)
            }
        }
    }

    private func calculateAverageFPS() -> Double {
        guard frameTimestamps.count > 1 else { return 0 }

        let timeSpan = frameTimestamps.last! - frameTimestamps.first!
        guard timeSpan > 0 else { return 0 }

        let frameCount = Double(frameTimestamps.count - 1)
        return frameCount / timeSpan
    }

    private func calculateAverageFrameTime() -> Double {
        guard !frameTimes.isEmpty else {
            // Fallback: calculate from FPS
            let fps = calculateAverageFPS()
            return fps > 0 ? 1000.0 / fps : 0
        }
        return frameTimes.reduce(0, +) / Double(frameTimes.count)
    }

    private func getCPUUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }

        if threadsResult == KERN_SUCCESS, let threadsList = threadsList {
            for index in 0..<threadsCount {
                var threadInfo = thread_basic_info()
                var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
                let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                    $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                        thread_info(threadsList[Int(index)], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                    }
                }

                guard infoResult == KERN_SUCCESS else { continue }

                let threadBasicInfo = threadInfo as thread_basic_info
                if threadBasicInfo.flags & TH_FLAGS_IDLE == 0 {
                    totalUsageOfCPU += Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
                }
            }

            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsList)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }

        return min(totalUsageOfCPU, 100.0)
    }

    private func getMemoryUsage() -> Double {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Double(taskInfo.phys_footprint) / 1024.0 / 1024.0 // Convert to MB
        }
        return 0
    }

    private func getThermalStateString() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "Normal"
        case .fair:
            return "Fair"
        case .serious:
            return "Serious"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }

    private func estimateGPUUtilization() -> Double {
        // iOS doesn't provide direct GPU metrics
        // Estimate based on frame time variance and thermal state
        let avgFrameTime = calculateAverageFrameTime()
        let targetFrameTime = 16.67 // 60 FPS target

        var baseUtilization = min((avgFrameTime / targetFrameTime) * 50.0, 80.0)

        // Adjust based on thermal state
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            break
        case .fair:
            baseUtilization = max(baseUtilization, 50.0)
        case .serious:
            baseUtilization = max(baseUtilization, 70.0)
        case .critical:
            baseUtilization = max(baseUtilization, 90.0)
        @unknown default:
            break
        }

        return min(baseUtilization, 100.0)
    }
}
