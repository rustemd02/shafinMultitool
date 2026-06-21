//
//  DeviceBenchmarkSupport.swift
//  shafinMultitool
//
//  Created by Codex on 15.06.2026.
//

import Foundation
import UIKit
import Darwin

enum DeviceBenchmarkTier: String, Codable {
    case quick
    case full
}

enum DeviceBenchmarkModule: String, Codable, CaseIterable {
    case camera
    case sceneGenerator
}

enum DeviceBenchmarkSceneGeneratorModelPolicy: String, Codable {
    case explicitOrLatest
}

enum SceneGeneratorBenchmarkRuntimeDefaults {
    static let gpuLayersKey = "device_benchmark_scene_runtime_gpu_layers"
    static let threadsKey = "device_benchmark_scene_runtime_threads"
    static let contextTokensKey = "device_benchmark_scene_runtime_context_tokens"
}

struct SceneGeneratorBenchmarkRuntimeProfile: Equatable {
    let gpuLayers: Int
    let threads: Int
    let contextTokens: Int
}

enum DeviceBenchmarkSceneRuntimePreset: String, Codable, Equatable {
    case baseline
    case efficiency
    case batterySaver

    var profile: SceneGeneratorBenchmarkRuntimeProfile {
        switch self {
        case .baseline:
            return SceneGeneratorBenchmarkRuntimeProfile(gpuLayers: 99, threads: 4, contextTokens: 2048)
        case .efficiency:
            return SceneGeneratorBenchmarkRuntimeProfile(gpuLayers: 48, threads: 2, contextTokens: 2048)
        case .batterySaver:
            return SceneGeneratorBenchmarkRuntimeProfile(gpuLayers: 24, threads: 1, contextTokens: 2048)
        }
    }
}

enum DeviceBenchmarkSceneExecutionMode: String, Codable, Equatable {
    case monolithic
    case chunkedThermalAware

    var runtimeMode: SceneGeneratorExecutionMode {
        switch self {
        case .monolithic:
            return .monolithic
        case .chunkedThermalAware:
            return .chunkedThermalAware
        }
    }
}

struct DeviceBenchmarkSoftThresholds: Codable, Equatable {
    var scenePassRate: Double

    static let `default` = DeviceBenchmarkSoftThresholds(scenePassRate: 0.60)
}

struct DeviceBenchmarkConfig: Codable, Equatable {
    static let environmentKey = "DEVICE_BENCHMARK_CONFIG_BASE64"

    var runId: String
    var tier: DeviceBenchmarkTier
    var enabledModules: [DeviceBenchmarkModule]
    var sceneGeneratorModelPolicy: DeviceBenchmarkSceneGeneratorModelPolicy
    var sceneGeneratorRuntimePreset: DeviceBenchmarkSceneRuntimePreset
    var sceneGeneratorExecutionMode: DeviceBenchmarkSceneExecutionMode
    var sceneGeneratorThermalPolicy: SceneGeneratorMobileExecutionPolicy
    var cameraResourcePackId: String
    var sceneResourcePackId: String
    var guidedLiveEnabled: Bool
    var softThresholds: DeviceBenchmarkSoftThresholds
    var autoStart: Bool
    var liveSequenceEnabled: Bool

    static var defaultQuick: DeviceBenchmarkConfig {
        DeviceBenchmarkConfig(
            runId: "device-benchmark-\(UUID().uuidString.lowercased())",
            tier: .quick,
            enabledModules: DeviceBenchmarkModule.allCases,
            sceneGeneratorModelPolicy: .explicitOrLatest,
            sceneGeneratorRuntimePreset: .baseline,
            sceneGeneratorExecutionMode: .chunkedThermalAware,
            sceneGeneratorThermalPolicy: .chunkedThermalAwareDefault,
            cameraResourcePackId: "camera_device_benchmark_pack_v1",
            sceneResourcePackId: "scene_generator_device_pack_v1",
            guidedLiveEnabled: false,
            softThresholds: .default,
            autoStart: true,
            liveSequenceEnabled: true
        )
    }

    static var defaultFull: DeviceBenchmarkConfig {
        var config = defaultQuick
        config.runId = "device-benchmark-\(UUID().uuidString.lowercased())"
        config.tier = .full
        return config
    }

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> DeviceBenchmarkConfig? {
        guard let encoded = environment[environmentKey], !encoded.isEmpty else {
            return nil
        }
        guard let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return try? JSONDecoder().decode(DeviceBenchmarkConfig.self, from: data)
    }

    func toBase64() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self).base64EncodedString()
    }
}

struct DeviceBenchmarkDeviceSnapshot: Codable, Equatable {
    let timestamp: Date
    let deviceModel: String
    let systemName: String
    let systemVersion: String
    let batteryLevel: Float
    let thermalState: String
    let appVersion: String
    let buildNumber: String
}

struct DeviceBenchmarkDeviceInfo: Codable, Equatable {
    let start: DeviceBenchmarkDeviceSnapshot
    let end: DeviceBenchmarkDeviceSnapshot
}

struct DeviceBenchmarkPerfSample: Codable, Equatable {
    let timestamp: Date
    let module: String
    let phase: String
    let mode: String
    let uiFPS: Double
    let pipelineFPS: Double
    let frameTimeMs: Double
    let droppedFrames: Int
    let cpuUsage: Double
    let memoryMB: Double
    let batteryLevel: Float
    let thermalState: String
    let stageLatenciesMs: [String: Double]
    let note: String?
}

struct DeviceBenchmarkAggregateMetrics: Codable, Equatable {
    let sampleCount: Int
    let uiFPSP50: Double?
    let uiFPSP95: Double?
    let pipelineFPSP50: Double?
    let pipelineFPSP95: Double?
    let frameTimeP95Ms: Double?
    let cpuP95: Double?
    let memoryP95MB: Double?
    let batteryDelta: Float
    let thermalStatesSeen: [String]
    let stageLatencyP95Ms: [String: Double]

    static func from(samples: [DeviceBenchmarkPerfSample], startBattery: Float, endBattery: Float) -> DeviceBenchmarkAggregateMetrics {
        let stageKeys = Set(samples.flatMap { $0.stageLatenciesMs.keys })
        var stageLatencyP95Ms: [String: Double] = [:]
        for key in stageKeys {
            let values = samples.compactMap { $0.stageLatenciesMs[key] }
            stageLatencyP95Ms[key] = percentile(values, p: 0.95)
        }
        return DeviceBenchmarkAggregateMetrics(
            sampleCount: samples.count,
            uiFPSP50: percentile(samples.map(\.uiFPS), p: 0.50),
            uiFPSP95: percentile(samples.map(\.uiFPS), p: 0.95),
            pipelineFPSP50: percentile(samples.map(\.pipelineFPS), p: 0.50),
            pipelineFPSP95: percentile(samples.map(\.pipelineFPS), p: 0.95),
            frameTimeP95Ms: percentile(samples.map(\.frameTimeMs), p: 0.95),
            cpuP95: percentile(samples.map(\.cpuUsage), p: 0.95),
            memoryP95MB: percentile(samples.map(\.memoryMB), p: 0.95),
            batteryDelta: endBattery - startBattery,
            thermalStatesSeen: Array(Set(samples.map(\.thermalState))).sorted(),
            stageLatencyP95Ms: stageLatencyP95Ms
        )
    }
}

struct DeviceBenchmarkSceneCaseExecutionMetrics: Codable, Equatable {
    let parseWallTimeMs: Double
    let chunkCount: Int
    let completedChunkCount: Int
    let checkpointCount: Int
    let thermalPauseCount: Int
    let thermalPauseTotalMs: Double
    let chunkRetryCount: Int
    let chunkFailureCount: Int
}

struct DeviceBenchmarkSceneExecutionAggregate: Codable, Equatable {
    let executionMode: String
    let chunkCount: Int
    let completedChunkCount: Int
    let checkpointCount: Int
    let thermalPauseCount: Int
    let thermalPauseTotalMs: Double
    let timeToSeriousThermalMs: Double?
    let timeInNominalMs: Double
    let timeInFairMs: Double
    let timeInSeriousMs: Double
    let timeInCriticalMs: Double
    let seriousThermalDurationRatio: Double?
    let latencyFirstHalfP50Ms: Double?
    let latencySecondHalfP50Ms: Double?
    let sustainedLatencyDegradationRatio: Double?
    let casesPerMinute: Double?
    let chunkRetryCount: Int
    let chunkFailureRate: Double

    static func from(
        executionMode: DeviceBenchmarkSceneExecutionMode,
        samples: [DeviceBenchmarkPerfSample],
        caseMetrics: [DeviceBenchmarkSceneCaseExecutionMetrics]
    ) -> DeviceBenchmarkSceneExecutionAggregate {
        let sortedSamples = samples.sorted { $0.timestamp < $1.timestamp }
        var timeInNominalMs = 0.0
        var timeInFairMs = 0.0
        var timeInSeriousMs = 0.0
        var timeInCriticalMs = 0.0
        var timeToSeriousThermalMs: Double?

        for (index, sample) in sortedSamples.enumerated() {
            let nextTimestamp = sortedSamples.indices.contains(index + 1) ? sortedSamples[index + 1].timestamp : sample.timestamp
            let deltaMs = max(nextTimestamp.timeIntervalSince(sample.timestamp) * 1000, 0)
            switch sample.thermalState {
            case "nominal":
                timeInNominalMs += deltaMs
            case "fair":
                timeInFairMs += deltaMs
            case "serious":
                timeInSeriousMs += deltaMs
                if timeToSeriousThermalMs == nil, let first = sortedSamples.first?.timestamp {
                    timeToSeriousThermalMs = max(sample.timestamp.timeIntervalSince(first) * 1000, 0)
                }
            case "critical":
                timeInCriticalMs += deltaMs
            default:
                break
            }
        }

        let totalObservedMs = timeInNominalMs + timeInFairMs + timeInSeriousMs + timeInCriticalMs
        let parseLatencies = caseMetrics.map(\.parseWallTimeMs)
        let midpoint = max(parseLatencies.count / 2, 1)
        let firstHalf = Array(parseLatencies.prefix(midpoint))
        let secondHalf = parseLatencies.count > midpoint ? Array(parseLatencies.suffix(parseLatencies.count - midpoint)) : []
        let firstHalfP50 = percentile(firstHalf, p: 0.50)
        let secondHalfP50 = percentile(secondHalf, p: 0.50)
        let degradationRatio: Double?
        if let firstHalfP50, firstHalfP50 > 0, let secondHalfP50 {
            degradationRatio = secondHalfP50 / firstHalfP50
        } else {
            degradationRatio = nil
        }

        let totalParseMs = parseLatencies.reduce(0, +)
        let totalChunkCount = caseMetrics.reduce(0) { $0 + $1.chunkCount }
        let totalFailures = caseMetrics.reduce(0) { $0 + $1.chunkFailureCount }
        return DeviceBenchmarkSceneExecutionAggregate(
            executionMode: executionMode.rawValue,
            chunkCount: totalChunkCount,
            completedChunkCount: caseMetrics.reduce(0) { $0 + $1.completedChunkCount },
            checkpointCount: caseMetrics.reduce(0) { $0 + $1.checkpointCount },
            thermalPauseCount: caseMetrics.reduce(0) { $0 + $1.thermalPauseCount },
            thermalPauseTotalMs: caseMetrics.reduce(0) { $0 + $1.thermalPauseTotalMs },
            timeToSeriousThermalMs: timeToSeriousThermalMs,
            timeInNominalMs: timeInNominalMs,
            timeInFairMs: timeInFairMs,
            timeInSeriousMs: timeInSeriousMs,
            timeInCriticalMs: timeInCriticalMs,
            seriousThermalDurationRatio: totalObservedMs > 0 ? timeInSeriousMs / totalObservedMs : nil,
            latencyFirstHalfP50Ms: firstHalfP50,
            latencySecondHalfP50Ms: secondHalfP50,
            sustainedLatencyDegradationRatio: degradationRatio,
            casesPerMinute: totalParseMs > 0 ? Double(caseMetrics.count) / (totalParseMs / 60_000) : nil,
            chunkRetryCount: caseMetrics.reduce(0) { $0 + $1.chunkRetryCount },
            chunkFailureRate: totalChunkCount > 0 ? Double(totalFailures) / Double(totalChunkCount) : 0
        )
    }
}

final class DeviceBenchmarkArtifactStore {
    let runId: String
    let rootURL: URL

    init(runId: String) {
        self.runId = runId
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        self.rootURL = caches
            .appendingPathComponent("DeviceBenchmark", isDirectory: true)
            .appendingPathComponent(runId, isDirectory: true)
    }

    func prepare() throws {
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    func fileURL(_ name: String) -> URL {
        rootURL.appendingPathComponent(name, isDirectory: false)
    }

    func directoryURL(_ name: String) -> URL {
        rootURL.appendingPathComponent(name, isDirectory: true)
    }

    func preparePackDirectory(packId: String) throws -> URL {
        let destination = directoryURL("packs").appendingPathComponent(packId, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            return destination
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        if let source = bundledPackURL(packId: packId) {
            try FileManager.default.copyItem(at: source, to: destination)
            return destination
        }
        try materializeFlattenedPack(packId: packId, destination: destination)
        return destination
    }

    private func bundledPackURL(packId: String) -> URL? {
        let subdirectories: [String?] = [
            "DeviceBenchmark",
            "Resources/DeviceBenchmark",
            nil
        ]
        for subdirectory in subdirectories {
            if let url = Bundle.main.url(forResource: packId, withExtension: nil, subdirectory: subdirectory) {
                return url
            }
        }

        let candidatePaths = [
            Bundle.main.bundleURL.appendingPathComponent("DeviceBenchmark/\(packId)", isDirectory: true),
            Bundle.main.bundleURL.appendingPathComponent("Resources/DeviceBenchmark/\(packId)", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("DeviceBenchmark/\(packId)", isDirectory: true),
            Bundle.main.resourceURL?.appendingPathComponent("Resources/DeviceBenchmark/\(packId)", isDirectory: true),
        ].compactMap { $0 }

        return candidatePaths.first(where: { FileManager.default.fileExists(atPath: $0.path) })
    }

    private func materializeFlattenedPack(packId: String, destination: URL) throws {
        switch packId {
        case "camera_device_benchmark_pack_v1":
            try materializeCameraPack(at: destination)
        case "scene_generator_device_pack_v1":
            try materializeSceneGeneratorPack(at: destination)
        default:
            throw NSError(
                domain: "DeviceBenchmarkArtifactStore",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unknown flattened resource pack \(packId)"]
            )
        }
    }

    private func materializeCameraPack(at destination: URL) throws {
        let imagesDirectory = destination.appendingPathComponent("images", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        let staticFiles = [
            "camera_full_labels.jsonl",
            "camera_quick_labels.jsonl",
            "live_sequences.json",
            "guided_live_scenarios.json",
            "camera_device_benchmark_manifest.json"
        ]
        for filename in staticFiles {
            try copyBundledResource(named: filename, to: destination.appendingPathComponent(filename))
        }

        let labelsURL = destination.appendingPathComponent("camera_full_labels.jsonl")
        let labelData = try Data(contentsOf: labelsURL)
        let lines = String(decoding: labelData, as: UTF8.self)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let decoder = JSONDecoder()
        for line in lines {
            let payload = try decoder.decode(DeviceBenchmarkCameraLabelRecord.self, from: Data(line.utf8))
            let destinationURL = imagesDirectory.appendingPathComponent(payload.filename)
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                continue
            }
            try copyBundledResource(named: payload.filename, to: destinationURL)
        }
    }

    private func materializeSceneGeneratorPack(at destination: URL) throws {
        let staticFiles = [
            "core_accepted_source.jsonl",
            "hard_accepted_source.jsonl",
            "scene_generator_device_benchmark_manifest.json"
        ]
        for filename in staticFiles {
            try copyBundledResource(named: filename, to: destination.appendingPathComponent(filename))
        }
    }

    private func copyBundledResource(named filename: String, to destination: URL) throws {
        let sourceURL: URL
        if let directURL = Bundle.main.url(forResource: filename, withExtension: nil) {
            sourceURL = directURL
        } else {
            let nsFilename = filename as NSString
            let basename = nsFilename.deletingPathExtension
            let fileExtension = nsFilename.pathExtension.isEmpty ? nil : nsFilename.pathExtension
            guard let resolvedURL = Bundle.main.url(forResource: basename, withExtension: fileExtension) else {
                throw NSError(
                    domain: "DeviceBenchmarkArtifactStore",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Missing bundled resource \(filename)"]
                )
            }
            sourceURL = resolvedURL
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            return
        }
        try FileManager.default.copyItem(at: sourceURL, to: destination)
    }

    private func ensureParentDirectory(for url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    func writeJSON<T: Encodable>(_ value: T, named name: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let url = fileURL(name)
        try ensureParentDirectory(for: url)
        try encoder.encode(value).write(to: url)
        return url
    }

    func writeLines(_ lines: [String], named name: String) throws -> URL {
        let url = fileURL(name)
        try ensureParentDirectory(for: url)
        let body = lines.joined(separator: "\n") + "\n"
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func writeJSONLines<T: Encodable>(_ values: [T], named name: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let lines = try values.map { value -> String in
            let data = try encoder.encode(value)
            return String(decoding: data, as: UTF8.self)
        }
        return try writeLines(lines, named: name)
    }

    func writeString(_ value: String, named name: String) throws -> URL {
        let url = fileURL(name)
        try ensureParentDirectory(for: url)
        try value.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func makeArtifactsArchiveIfPossible() throws -> URL? {
        guard #available(iOS 16.0, *) else {
            return nil
        }
        return nil
//
//        let temporaryArchiveURL = rootURL
//            .deletingLastPathComponent()
//            .appendingPathComponent("\(runId)-artifacts.zip", isDirectory: false)
//        let destinationURL = fileURL("artifacts.zip")
//        if FileManager.default.fileExists(atPath: temporaryArchiveURL.path) {
//            try? FileManager.default.removeItem(at: temporaryArchiveURL)
//        }
//        if FileManager.default.fileExists(atPath: destinationURL.path) {
//            try? FileManager.default.removeItem(at: destinationURL)
//        }
//        try FileManager.default.zipItem(at: rootURL, to: temporaryArchiveURL, shouldKeepParent: true)
//        try FileManager.default.moveItem(at: temporaryArchiveURL, to: destinationURL)
//        return destinationURL
    }
}

@MainActor
final class DeviceBenchmarkMetricsCollector {
    struct Context {
        var module: String
        var phase: String
        var mode: String
        var note: String?
    }

    private var context: Context
    private var samplingTask: Task<Void, Never>?
    private let intervalNanoseconds: UInt64
    private(set) var samples: [DeviceBenchmarkPerfSample] = []

    init(interval: TimeInterval, module: String, phase: String, mode: String) {
        self.intervalNanoseconds = UInt64(max(0.1, interval) * 1_000_000_000)
        self.context = Context(module: module, phase: phase, mode: mode, note: nil)
    }

    func start() {
        samplingTask?.cancel()
        samplingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                self.captureSample()
                try? await Task.sleep(nanoseconds: self.intervalNanoseconds)
            }
        }
    }

    func update(module: String? = nil, phase: String? = nil, mode: String? = nil, note: String? = nil) {
        if let module {
            context.module = module
        }
        if let phase {
            context.phase = phase
        }
        if let mode {
            context.mode = mode
        }
        if let note {
            context.note = note
        }
    }

    func mark(note: String?) {
        context.note = note
        captureSample()
    }

    func stop() {
        samplingTask?.cancel()
        samplingTask = nil
        captureSample()
    }

    func reset() {
        samples.removeAll()
    }

    private func captureSample() {
        let telemetry = Telemetry.shared.metrics
        let uiFPS = telemetry.fps
        let pipelineFPS = telemetry.pipelineFPS
        let frameTimeMs = uiFPS > 0 ? 1000.0 / uiFPS : 0
        let droppedFrames = pipelineFPS < 60 ? max(0, Int((60.0 - pipelineFPS).rounded())) : 0
        let sample = DeviceBenchmarkPerfSample(
            timestamp: Date(),
            module: context.module,
            phase: context.phase,
            mode: context.mode,
            uiFPS: uiFPS,
            pipelineFPS: pipelineFPS,
            frameTimeMs: frameTimeMs,
            droppedFrames: droppedFrames,
            cpuUsage: Self.cpuUsage(),
            memoryMB: Self.memoryUsageMB(),
            batteryLevel: telemetry.batteryLevel,
            thermalState: telemetry.thermalState,
            stageLatenciesMs: telemetry.lastLatencies.mapValues { $0 * 1000 },
            note: context.note
        )
        samples.append(sample)
        context.note = nil
    }

    private static func cpuUsage() -> Double {
        var totalUsageOfCPU: Double = 0.0
        var threadsList: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsList) {
            $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }

        guard threadsResult == KERN_SUCCESS, let threadsList else {
            return 0
        }

        for index in 0..<Int(threadsCount) {
            var threadInfo = thread_basic_info()
            var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
            let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
                $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                    thread_info(threadsList[index], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
                }
            }
            guard infoResult == KERN_SUCCESS else { continue }
            let basicInfo = threadInfo as thread_basic_info
            if basicInfo.flags & TH_FLAGS_IDLE == 0 {
                totalUsageOfCPU += Double(basicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
            }
        }

        vm_deallocate(
            mach_task_self_,
            vm_address_t(bitPattern: threadsList),
            vm_size_t(threadsCount) * vm_size_t(MemoryLayout<thread_t>.stride)
        )
        return totalUsageOfCPU
    }

    private static func memoryUsageMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return 0
        }
        return Double(info.resident_size) / 1024.0 / 1024.0
    }
}

func deviceBenchmarkSnapshot() -> DeviceBenchmarkDeviceSnapshot {
    let info = Bundle.main.infoDictionary ?? [:]
    let appVersion = info["CFBundleShortVersionString"] as? String ?? "unknown"
    let buildNumber = info["CFBundleVersion"] as? String ?? "unknown"
    return DeviceBenchmarkDeviceSnapshot(
        timestamp: Date(),
        deviceModel: deviceBenchmarkModelIdentifier(),
        systemName: UIDevice.current.systemName,
        systemVersion: UIDevice.current.systemVersion,
        batteryLevel: UIDevice.current.batteryLevel,
        thermalState: deviceBenchmarkThermalStateDescription(ProcessInfo.processInfo.thermalState),
        appVersion: appVersion,
        buildNumber: buildNumber
    )
}

func deviceBenchmarkModelIdentifier() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
            String(cString: $0)
        }
    }
}

func deviceBenchmarkThermalStateDescription(_ state: ProcessInfo.ThermalState) -> String {
    switch state {
    case .nominal:
        return "nominal"
    case .fair:
        return "fair"
    case .serious:
        return "serious"
    case .critical:
        return "critical"
    @unknown default:
        return "unknown"
    }
}

func percentile(_ values: [Double], p: Double) -> Double? {
    let filtered = values.filter { $0.isFinite }
    guard !filtered.isEmpty else {
        return nil
    }
    let sorted = filtered.sorted()
    let clamped = min(max(p, 0), 1)
    let rank = Int((Double(sorted.count - 1) * clamped).rounded())
    return sorted[min(max(rank, 0), sorted.count - 1)]
}
