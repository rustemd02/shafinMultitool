//
//  DiagnosticsLogger.swift
//  shafinMultitool
//
//  Created to capture long-run performance summaries.
//

import Foundation

final class DiagnosticsLogger {

    static let shared = DiagnosticsLogger()

    private var bufferedEntries: [String] = []
    private let queue = DispatchQueue(label: "diagnostics.logger", qos: .utility)
    private var lastWriteDate: Date = .distantPast

    private init() {}

    func log(metrics: PerformanceMetrics) {
        queue.async {
            let entry = String(
                format: "[%@] FPS: %.1f | Frame: %.2fms | CPU: %.1f%% | MEM: %.0fMB | Therm: %@ | Vision: %.1fms | Speech: %.1fms",
                Self.timestampFormatter.string(from: Date()),
                metrics.fps,
                metrics.frameTime,
                metrics.cpuUsage,
                metrics.memoryUsage,
                metrics.thermalState,
                metrics.visionLatency,
                metrics.speechLatency
            )
            self.bufferedEntries.append(entry)
            if self.bufferedEntries.count >= 20 || Date().timeIntervalSince(self.lastWriteDate) > 120 {
                self.flush()
            }
        }
    }

    func flush() {
        let entriesToWrite = bufferedEntries
        bufferedEntries.removeAll()
        guard !entriesToWrite.isEmpty else { return }

        let logString = entriesToWrite.joined(separator: "\n") + "\n"
        let fileURL = diagnosticsFileURL()
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let handle = try FileHandle(forWritingTo: fileURL)
                handle.seekToEndOfFile()
                if let data = logString.data(using: .utf8) {
                    handle.write(data)
                }
                try handle.close()
            } else {
                try logString.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            lastWriteDate = Date()
        } catch {
            print("DiagnosticsLogger: Failed to write log - \(error)")
        }
    }

    private func diagnosticsFileURL() -> URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsDirectory.appendingPathComponent("preproduction-perf.log")
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

