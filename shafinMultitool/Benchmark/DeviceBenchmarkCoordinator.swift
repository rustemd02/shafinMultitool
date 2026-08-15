//
//  DeviceBenchmarkCoordinator.swift
//  shafinMultitool
//
//  Created by Codex on 15.06.2026.
//

#if DEBUG

import Foundation
import SwiftUI
import ImageIO
import CoreVideo

struct DeviceBenchmarkRunManifest: Codable {
    let runId: String
    let tier: String
    let enabledModules: [String]
    let startedAt: Date
    let finishedAt: Date
    let cameraPackId: String
    let scenePackId: String
    let guidedLiveEnabled: Bool
    let liveSequenceEnabled: Bool
}

struct DeviceBenchmarkRunResult {
    let artifactStore: DeviceBenchmarkArtifactStore
    let manifestURL: URL
    let deviceInfoURL: URL
    let perfSamplesURL: URL
    let cameraSummaryURL: URL?
    let sceneSummaryURL: URL?
    let combinedSummaryURL: URL
    let combinedMarkdownURL: URL
    let artifactsArchiveURL: URL?
}

struct DeviceBenchmarkCameraLabelRecord: Codable, Equatable {
    let recordId: String
    let filename: String
    let imagePath: String
    let sourceBucket: String
    let confidenceTarget: String
    let demoPriority: Bool

    enum CodingKeys: String, CodingKey {
        case recordId = "record_id"
        case filename
        case imagePath = "image_path"
        case sourceBucket = "source_bucket"
        case confidenceTarget = "confidence_target"
        case demoPriority = "demo_priority"
    }
}

struct DeviceBenchmarkLiveSequenceClip: Codable, Equatable, Identifiable {
    let id: String
    let mode: String
    let framePaths: [String]
    let interFrameDelayMs: Int
}

struct DeviceBenchmarkLiveSequenceManifest: Codable, Equatable {
    let quick: [DeviceBenchmarkLiveSequenceClip]
    let full: [DeviceBenchmarkLiveSequenceClip]
}

struct DeviceBenchmarkGuidedScenario: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let instructions: [String]
    let durationSeconds: Int
}

struct DeviceBenchmarkGuidedScenarioManifest: Codable, Equatable {
    let quick: [DeviceBenchmarkGuidedScenario]
    let full: [DeviceBenchmarkGuidedScenario]
}

struct DeviceBenchmarkCameraPhaseSummary: Codable, Equatable {
    let phase: String
    let caseCount: Int
    let rowCount: Int
    let durationMs: Double
    let outputFile: String
}

struct DeviceBenchmarkGuidedLiveSummary: Codable, Equatable {
    let scenarioId: String
    let title: String
    let status: String
    let durationMs: Double
}

struct DeviceBenchmarkCameraSummary: Codable, Equatable {
    let packId: String
    let stillReplay: DeviceBenchmarkCameraPhaseSummary?
    let liveSequenceReplay: DeviceBenchmarkCameraPhaseSummary?
    let guidedLive: [DeviceBenchmarkGuidedLiveSummary]
    let mobileMetrics: DeviceBenchmarkAggregateMetrics
    let status: String
    let limitations: [String]
}

struct DeviceBenchmarkSceneCaseResult: Codable, Equatable {
    let sampleId: String
    let patternName: String
    let difficultyBucket: String
    let coldStart: Bool
    let parseWallTimeMs: Double
    let actorCount: Int
    let beatCount: Int
    let actionCount: Int
    let confidence: Float
    let route: String?
    let reasonCodes: [String]
    let hardIssues: [String]
    let softIssues: [String]
    let passed: Bool
}

struct DeviceBenchmarkSceneExecutionEvent: Codable, Equatable {
    let timestamp: Date
    let sampleId: String
    let executionMode: String
    let chunkIndex: Int
    let chunkCount: Int
    let status: String
    let thermalState: String
    let batteryLevel: Float
    let note: String?
}

struct DeviceBenchmarkSceneCheckpointRecord: Codable, Equatable {
    let sampleId: String
    let executionMode: String
    let chunkIndex: Int
    let sourceLength: Int
    let thermalState: String
    let checkpointFile: String
    let timestamp: Date
}

struct DeviceBenchmarkSceneSummary: Codable, Equatable {
    let packId: String
    let modelPath: String
    let runtimePreset: String
    let runtimeGpuLayers: Int
    let runtimeThreads: Int
    let runtimeContextTokens: Int
    let loadingState: String
    let executionMode: String
    let caseCount: Int
    let passRate: Double
    let successfulCaseCount: Int
    let firstPassSuccessRate: Double
    let retryCaseRate: Double
    let meanRetryCountPerCase: Double
    let maxTokensReachedCaseRate: Double
    let inputCanonicalizationRate: Double
    let coldStartLoadMs: Double
    let parseP50Ms: Double?
    let parseP95Ms: Double?
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
    let successfulCasesPerMinute: Double?
    let batteryDrainPer100Cases: Double?
    let chunkRetryCount: Int
    let chunkFailureRate: Double
    let cpuP95: Double?
    let memoryP95MB: Double?
    let warnings: [String]
    let hardFailures: [String]
    let outputFile: String
    let executionEventsFile: String?
    let checkpointManifestFile: String?
    let finalDocumentStateFile: String?
    let mobileMetrics: DeviceBenchmarkAggregateMetrics
}

struct DeviceBenchmarkCombinedSummary: Codable, Equatable {
    let runId: String
    let tier: String
    let enabledModules: [String]
    let startedAt: Date
    let finishedAt: Date
    let cameraSummaryFile: String?
    let sceneSummaryFile: String?
    let overallStatus: String
    let failureReason: String?
}

struct DeviceBenchmarkSceneRecord: Decodable {
    struct GraphConstraints: Decodable {
        struct MarkedObjectConstraint: Decodable {
            let canonicalName: String

            enum CodingKeys: String, CodingKey {
                case canonicalName = "canonical_name"
            }
        }

        let markedObjects: [MarkedObjectConstraint]
        let ordinalBindings: [String: String]
        let sameTypeMarkerConflict: Bool

        enum CodingKeys: String, CodingKey {
            case markedObjects = "marked_objects"
            case ordinalBindings = "ordinal_bindings"
            case sameTypeMarkerConflict = "same_type_marker_conflict"
        }
    }

    struct ValidationReport: Decodable {
        let criticVerdict: String?
        let criticDetectedFailures: [String]

        enum CodingKeys: String, CodingKey {
            case criticVerdict = "critic_verdict"
            case criticDetectedFailures = "critic_detected_failures"
        }
    }

    let patternName: String
    let difficultyBucket: String
    let sampleId: String
    let sourceText: String
    let graphConstraints: GraphConstraints
    let validationReport: ValidationReport?

    enum CodingKeys: String, CodingKey {
        case patternName = "pattern_name"
        case difficultyBucket = "difficulty_bucket"
        case sampleId = "sample_id"
        case sourceText = "source_text"
        case graphConstraints = "graph_constraints"
        case validationReport = "validation_report"
    }
}

private struct DeviceBenchmarkSceneExpectation {
    let actorFloor: Int
    let requiresDialogue: Bool
    let requiredActionTypes: [SceneAction.ActionType]
    let markedObjectFloor: Int
    let expectsSameTypeConflict: Bool
}

private struct DeviceBenchmarkSeededGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }

    mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(next() % UInt64(upperBound))
    }
}

private struct DeviceBenchmarkSceneCaseRun {
    let result: SceneBundleParsingResult
    let metrics: DeviceBenchmarkSceneCaseExecutionMetrics
    let events: [DeviceBenchmarkSceneExecutionEvent]
    let checkpoints: [DeviceBenchmarkSceneCheckpointRecord]
    let finalDocumentStateFile: String?
}

@MainActor
final class DeviceBenchmarkCoordinator: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var statusText = "Ready"
    @Published private(set) var combinedSummaryMarkdown = ""
    @Published private(set) var activeGuidedScenario: DeviceBenchmarkGuidedScenario?

    private let config: DeviceBenchmarkConfig
    private let artifactStore: DeviceBenchmarkArtifactStore
    private var hasAutoStarted = false
    private var guidedContinuation: CheckedContinuation<Void, Never>?

    init(config: DeviceBenchmarkConfig) {
        self.config = config
        self.artifactStore = DeviceBenchmarkArtifactStore(runId: config.runId)
    }

    func startIfNeeded(interactive: Bool) {
        guard config.autoStart, !hasAutoStarted else { return }
        hasAutoStarted = true
        start(interactive: interactive)
    }

    func start(interactive: Bool) {
        Task {
            _ = try? await run(interactive: interactive)
        }
    }

    func run(interactive: Bool) async throws -> DeviceBenchmarkRunResult {
        guard !isRunning else {
            throw NSError(
                domain: "DeviceBenchmarkCoordinator",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Device benchmark is already running."]
            )
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        isRunning = true
        statusText = "Preparing artifact store"
        defer { isRunning = false }

        try artifactStore.prepare()
        let startedAt = Date()
        let startSnapshot = deviceBenchmarkSnapshot()

        let perfCollector = DeviceBenchmarkMetricsCollector(
            interval: config.tier == .quick ? 1.0 : 0.5,
            module: "bootstrap",
            phase: "prepare",
            mode: "bootstrap"
        )
        perfCollector.start()

        var cameraSummaryURL: URL?
        var sceneSummaryURL: URL?
        var overallStatus = "pass"
        var failureReason: String?

        do {
            if config.enabledModules.contains(.camera) {
                let summary = try await runCameraBenchmarks(interactive: interactive, perfCollector: perfCollector)
                cameraSummaryURL = try artifactStore.writeJSON(summary, named: "camera_summary.json")
                if summary.status != "pass" {
                    overallStatus = summary.status
                }
            }

            if config.enabledModules.contains(.sceneGenerator) {
                let summary = try await runSceneGeneratorBenchmarks(perfCollector: perfCollector)
                sceneSummaryURL = try artifactStore.writeJSON(summary, named: "scene_summary.json")
                if !summary.hardFailures.isEmpty {
                    overallStatus = "fail"
                } else if !summary.warnings.isEmpty && overallStatus == "pass" {
                    overallStatus = "warn"
                }
            }
        } catch {
            overallStatus = "fail"
            failureReason = error.localizedDescription
            statusText = "Failed: \(error.localizedDescription)"
        }

        perfCollector.stop()
        let perfURL = try artifactStore.writeJSONLines(perfCollector.samples, named: "perf_samples.jsonl")
        let endSnapshot = deviceBenchmarkSnapshot()
        let deviceInfoURL = try artifactStore.writeJSON(
            DeviceBenchmarkDeviceInfo(start: startSnapshot, end: endSnapshot),
            named: "device_info.json"
        )
        let finishedAt = Date()
        let manifestURL = try artifactStore.writeJSON(
            DeviceBenchmarkRunManifest(
                runId: config.runId,
                tier: config.tier.rawValue,
                enabledModules: config.enabledModules.map(\.rawValue),
                startedAt: startedAt,
                finishedAt: finishedAt,
                cameraPackId: config.cameraResourcePackId,
                scenePackId: config.sceneResourcePackId,
                guidedLiveEnabled: config.guidedLiveEnabled,
                liveSequenceEnabled: config.liveSequenceEnabled
            ),
            named: "run_manifest.json"
        )

        let combinedSummary = DeviceBenchmarkCombinedSummary(
            runId: config.runId,
            tier: config.tier.rawValue,
            enabledModules: config.enabledModules.map(\.rawValue),
            startedAt: startedAt,
            finishedAt: finishedAt,
            cameraSummaryFile: cameraSummaryURL?.lastPathComponent,
            sceneSummaryFile: sceneSummaryURL?.lastPathComponent,
            overallStatus: overallStatus,
            failureReason: failureReason
        )
        let combinedSummaryURL = try artifactStore.writeJSON(combinedSummary, named: "combined_summary.json")
        let markdown = makeMarkdownSummary(
            combined: combinedSummary,
            deviceStart: startSnapshot,
            deviceEnd: endSnapshot
        )
        combinedSummaryMarkdown = markdown
        let combinedMarkdownURL = try artifactStore.writeString(markdown, named: "combined_summary.md")
        let artifactsArchiveURL = try artifactStore.makeArtifactsArchiveIfPossible()
        if failureReason == nil {
            statusText = "Completed with status \(overallStatus)"
        }

        let result = DeviceBenchmarkRunResult(
            artifactStore: artifactStore,
            manifestURL: manifestURL,
            deviceInfoURL: deviceInfoURL,
            perfSamplesURL: perfURL,
            cameraSummaryURL: cameraSummaryURL,
            sceneSummaryURL: sceneSummaryURL,
            combinedSummaryURL: combinedSummaryURL,
            combinedMarkdownURL: combinedMarkdownURL,
            artifactsArchiveURL: artifactsArchiveURL
        )
        if let failureReason {
            throw NSError(
                domain: "DeviceBenchmarkCoordinator",
                code: 6,
                userInfo: [
                    NSLocalizedDescriptionKey: failureReason,
                    "partialResult": result
                ]
            )
        }
        return result
    }

    func completeGuidedScenario() {
        activeGuidedScenario = nil
        guidedContinuation?.resume()
        guidedContinuation = nil
    }

    private func runCameraBenchmarks(interactive: Bool,
                                     perfCollector: DeviceBenchmarkMetricsCollector) async throws -> DeviceBenchmarkCameraSummary {
        statusText = "Preparing camera resource pack"
        let packDirectory = try artifactStore.preparePackDirectory(packId: config.cameraResourcePackId)
        let labelFile = config.tier == .quick ? "camera_quick_labels.jsonl" : "camera_full_labels.jsonl"
        let labelURL = packDirectory.appendingPathComponent(labelFile)
        let labels = try loadJSONLines(DeviceBenchmarkCameraLabelRecord.self, from: labelURL)
        let pipeline = AnalysisPipeline(reasoningProvider: nil)

        perfCollector.update(module: "camera", phase: "still_replay", mode: "full_runtime_still")
        statusText = "Camera: still replay \(labels.count) cases"
        let stillStartedAt = Date()
        var rows: [SemanticEvalCandidateOutput] = []
        rows.reserveCapacity(labels.count * 2)
        for label in labels {
            let imageURL = packDirectory.appendingPathComponent(label.imagePath)
            let pixelBuffer = try makePixelBuffer(from: imageURL)
            let replay = await pipeline.testingReplayStillImageForSemanticEval(
                recordId: label.recordId,
                filename: label.filename,
                pixelBuffer: pixelBuffer,
                orientation: .up,
                capturedAt: Date(timeIntervalSince1970: 1_768_500_000),
                options: .fullRuntime
            )
            rows.append(contentsOf: replay.rows)
        }
        let stillURL = try writeSemanticRows(rows, named: "camera_still_rows.jsonl")
        let stillDuration = Date().timeIntervalSince(stillStartedAt) * 1000
        let stillSummary = DeviceBenchmarkCameraPhaseSummary(
            phase: "still_replay",
            caseCount: labels.count,
            rowCount: rows.count,
            durationMs: stillDuration,
            outputFile: stillURL.lastPathComponent
        )

        var liveSequenceSummary: DeviceBenchmarkCameraPhaseSummary?
        var limitations: [String] = []
        if config.liveSequenceEnabled {
            perfCollector.update(module: "camera", phase: "live_sequence_replay", mode: "live_sequence")
            statusText = "Camera: live-sequence replay"
            let manifest = try loadJSON(DeviceBenchmarkLiveSequenceManifest.self,
                                        from: packDirectory.appendingPathComponent("live_sequences.json"))
            let clips = config.tier == .quick ? manifest.quick : manifest.full
            let sequenceStartedAt = Date()
            var sequenceRows: [SemanticEvalCandidateOutput] = []
            for clip in clips {
                for (index, framePath) in clip.framePaths.enumerated() {
                    let frameURL = packDirectory.appendingPathComponent(framePath)
                    let pixelBuffer = try makePixelBuffer(from: frameURL)
                    let replay = await pipeline.testingReplayStillImageForSemanticEval(
                        recordId: "\(clip.id)-frame-\(index + 1)",
                        filename: URL(fileURLWithPath: framePath).lastPathComponent,
                        pixelBuffer: pixelBuffer,
                        orientation: .up,
                        capturedAt: Date(),
                        options: .fullRuntime
                    )
                    sequenceRows.append(contentsOf: replay.rows)
                    perfCollector.mark(note: "live_sequence_clip=\(clip.id)")
                    try? await Task.sleep(nanoseconds: UInt64(max(clip.interFrameDelayMs, 50)) * 1_000_000)
                }
            }
            let sequenceURL = try writeSemanticRows(sequenceRows, named: "camera_live_sequence_rows.jsonl")
            let sequenceDuration = Date().timeIntervalSince(sequenceStartedAt) * 1000
            liveSequenceSummary = DeviceBenchmarkCameraPhaseSummary(
                phase: "live_sequence_replay",
                caseCount: clips.count,
                rowCount: sequenceRows.count,
                durationMs: sequenceDuration,
                outputFile: sequenceURL.lastPathComponent
            )
            limitations.append("live_sequence_replay_v1_uses_still_replay_api_not_true_live_camera_loop")
        }

        var guidedLiveSummaries: [DeviceBenchmarkGuidedLiveSummary] = []
        if config.guidedLiveEnabled {
            let manifest = try loadJSON(DeviceBenchmarkGuidedScenarioManifest.self,
                                        from: packDirectory.appendingPathComponent("guided_live_scenarios.json"))
            let scenarios = config.tier == .quick ? manifest.quick : manifest.full
            for scenario in scenarios {
                perfCollector.update(module: "camera", phase: "guided_live", mode: "interactive_camera")
                statusText = "Camera: guided live \(scenario.title)"
                let scenarioStartedAt = Date()
                if interactive {
                    activeGuidedScenario = scenario
                    await withCheckedContinuation { continuation in
                        guidedContinuation = continuation
                    }
                    guidedLiveSummaries.append(
                        DeviceBenchmarkGuidedLiveSummary(
                            scenarioId: scenario.id,
                            title: scenario.title,
                            status: "completed",
                            durationMs: Date().timeIntervalSince(scenarioStartedAt) * 1000
                        )
                    )
                } else {
                    limitations.append("guided_live_requested_but_noninteractive_runner_skipped_operator_flow")
                    guidedLiveSummaries.append(
                        DeviceBenchmarkGuidedLiveSummary(
                            scenarioId: scenario.id,
                            title: scenario.title,
                            status: "skipped_interactive_unavailable",
                            durationMs: 0
                        )
                    )
                }
            }
        }

        let cameraSamples = perfCollector.samples.filter { $0.module == "camera" }
        let mobileMetrics = DeviceBenchmarkAggregateMetrics.from(
            samples: cameraSamples,
            startBattery: cameraSamples.first?.batteryLevel ?? UIDevice.current.batteryLevel,
            endBattery: cameraSamples.last?.batteryLevel ?? UIDevice.current.batteryLevel
        )
        let status: String
        if config.guidedLiveEnabled && guidedLiveSummaries.contains(where: { $0.status != "completed" }) {
            status = "research_only"
        } else {
            status = "pass"
        }
        return DeviceBenchmarkCameraSummary(
            packId: config.cameraResourcePackId,
            stillReplay: stillSummary,
            liveSequenceReplay: liveSequenceSummary,
            guidedLive: guidedLiveSummaries,
            mobileMetrics: mobileMetrics,
            status: status,
            limitations: limitations
        )
    }

    private func runSceneGeneratorBenchmarks(perfCollector: DeviceBenchmarkMetricsCollector) async throws -> DeviceBenchmarkSceneSummary {
        statusText = "Preparing scene generator resource pack"
        let packDirectory = try artifactStore.preparePackDirectory(packId: config.sceneResourcePackId)
        let modelPath = try resolveSceneModelPath()
        let parser = SceneParserService.shared
        let llmParser = LLMParserService.shared
        let previousModelOverride = UserDefaults.standard.string(forKey: "scene_generator_llm_model_path")
        let runtimePreset = config.sceneGeneratorRuntimePreset
        let runtimeProfile = runtimePreset.profile
        let runtimeOverrideKeys = [
            SceneGeneratorBenchmarkRuntimeDefaults.gpuLayersKey,
            SceneGeneratorBenchmarkRuntimeDefaults.threadsKey,
            SceneGeneratorBenchmarkRuntimeDefaults.contextTokensKey,
        ]
        let previousRuntimeOverrides = runtimeOverrideKeys.reduce(into: [String: Any]()) { partialResult, key in
            if let value = UserDefaults.standard.object(forKey: key) {
                partialResult[key] = value
            }
        }
        UserDefaults.standard.set(modelPath, forKey: "scene_generator_llm_model_path")
        UserDefaults.standard.set(runtimeProfile.gpuLayers, forKey: SceneGeneratorBenchmarkRuntimeDefaults.gpuLayersKey)
        UserDefaults.standard.set(runtimeProfile.threads, forKey: SceneGeneratorBenchmarkRuntimeDefaults.threadsKey)
        UserDefaults.standard.set(runtimeProfile.contextTokens, forKey: SceneGeneratorBenchmarkRuntimeDefaults.contextTokensKey)
        defer {
            if let previousModelOverride {
                UserDefaults.standard.set(previousModelOverride, forKey: "scene_generator_llm_model_path")
            } else {
                UserDefaults.standard.removeObject(forKey: "scene_generator_llm_model_path")
            }
            for key in runtimeOverrideKeys {
                if let value = previousRuntimeOverrides[key] {
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }

        perfCollector.update(module: "scene_generator", phase: "cold_start_load", mode: "local_model")
        statusText = "Scene Generator: model load"
        let loadStartedAt = Date()
        await llmParser.loadModelIfNeeded()
        let coldStartLoadMs = Date().timeIntervalSince(loadStartedAt) * 1000
        let loadingState = loadingStateDescription(llmParser.loadingState)
        let hardFailures: [String]
        if llmParser.isAvailable {
            hardFailures = []
        } else {
            hardFailures = ["model_unavailable"]
        }

        let sampledRecords = try sampledSceneRecords(from: packDirectory)
        var results: [DeviceBenchmarkSceneCaseResult] = []
        var caseExecutionMetrics: [DeviceBenchmarkSceneCaseExecutionMetrics] = []
        var executionEvents: [DeviceBenchmarkSceneExecutionEvent] = []
        var checkpointRecords: [DeviceBenchmarkSceneCheckpointRecord] = []
        var finalDocumentStateFile: String?
        results.reserveCapacity(sampledRecords.count)
        perfCollector.update(module: "scene_generator", phase: "warm_corpus", mode: config.sceneGeneratorExecutionMode.rawValue)
        statusText = "Scene Generator: \(sampledRecords.count) runtime cases"

        for (index, record) in sampledRecords.enumerated() {
            parser.resetRuntimeContext()
            let markedObjects = makeMarkedObjects(from: record)
            let caseRun: DeviceBenchmarkSceneCaseRun
            switch config.sceneGeneratorExecutionMode {
            case .monolithic:
                caseRun = try await runMonolithicSceneBenchmarkCase(
                    parser: parser,
                    record: record,
                    markedObjects: markedObjects,
                    perfCollector: perfCollector
                )
            case .chunkedThermalAware:
                caseRun = try await runChunkedSceneBenchmarkCase(
                    parser: parser,
                    record: record,
                    markedObjects: markedObjects,
                    perfCollector: perfCollector
                )
            }
            let evaluation = evaluateSceneRecord(
                record: record,
                result: caseRun.result,
                trace: parser.lastRuntimeTrace,
                parseWallTimeMs: caseRun.metrics.parseWallTimeMs,
                coldStart: index == 0
            )
            results.append(evaluation)
            caseExecutionMetrics.append(caseRun.metrics)
            executionEvents.append(contentsOf: caseRun.events)
            checkpointRecords.append(contentsOf: caseRun.checkpoints)
            finalDocumentStateFile = caseRun.finalDocumentStateFile ?? finalDocumentStateFile
            perfCollector.mark(note: "scene_case_completed=\(record.sampleId)")
        }

        let resultURL = try artifactStore.writeJSON(results, named: "scene_case_results.json")
        let eventsURL = executionEvents.isEmpty ? nil : try artifactStore.writeJSONLines(
            executionEvents,
            named: "scene_execution_events.jsonl"
        )
        let checkpointManifestURL = checkpointRecords.isEmpty ? nil : try artifactStore.writeJSONLines(
            checkpointRecords,
            named: "scene_checkpoint_manifest.jsonl"
        )
        let passRate = Double(results.filter(\.passed).count) / Double(max(results.count, 1))
        let successfulCaseCount = results.filter(\.passed).count
        let retryTaggedPairs = zip(results, caseExecutionMetrics).map { result, metrics in
            (
                result: result,
                metrics: metrics,
                hasRetry: metrics.chunkRetryCount > 0 || result.reasonCodes.contains(where: { $0.contains("retry") })
            )
        }
        let firstPassSuccessCount = retryTaggedPairs.filter { $0.result.passed && !$0.hasRetry }.count
        let retryCaseCount = retryTaggedPairs.filter { $0.hasRetry }.count
        let totalRetryCount = caseExecutionMetrics.reduce(0) { $0 + $1.chunkRetryCount }
        let maxTokensReachedCaseCount = results.filter { result in
            result.reasonCodes.contains { $0.contains("max_tokens") }
        }.count
        let inputCanonicalizedCaseCount = results.filter { result in
            result.reasonCodes.contains { $0.contains("input_canonicalized") }
        }.count
        let parseLatencies = results.map(\.parseWallTimeMs)
        let warnings = passRate < config.softThresholds.scenePassRate ? ["pass_rate_below_threshold"] : []
        let sceneSamples = perfCollector.samples.filter { $0.module == "scene_generator" }
        let mobileMetrics = DeviceBenchmarkAggregateMetrics.from(
            samples: sceneSamples,
            startBattery: sceneSamples.first?.batteryLevel ?? UIDevice.current.batteryLevel,
            endBattery: sceneSamples.last?.batteryLevel ?? UIDevice.current.batteryLevel
        )
        let executionMetrics = DeviceBenchmarkSceneExecutionAggregate.from(
            executionMode: config.sceneGeneratorExecutionMode,
            samples: sceneSamples,
            caseMetrics: caseExecutionMetrics
        )
        return DeviceBenchmarkSceneSummary(
            packId: config.sceneResourcePackId,
            modelPath: modelPath,
            runtimePreset: runtimePreset.rawValue,
            runtimeGpuLayers: runtimeProfile.gpuLayers,
            runtimeThreads: runtimeProfile.threads,
            runtimeContextTokens: runtimeProfile.contextTokens,
            loadingState: loadingState,
            executionMode: executionMetrics.executionMode,
            caseCount: results.count,
            passRate: passRate,
            successfulCaseCount: successfulCaseCount,
            firstPassSuccessRate: Double(firstPassSuccessCount) / Double(max(results.count, 1)),
            retryCaseRate: Double(retryCaseCount) / Double(max(results.count, 1)),
            meanRetryCountPerCase: Double(totalRetryCount) / Double(max(results.count, 1)),
            maxTokensReachedCaseRate: Double(maxTokensReachedCaseCount) / Double(max(results.count, 1)),
            inputCanonicalizationRate: Double(inputCanonicalizedCaseCount) / Double(max(results.count, 1)),
            coldStartLoadMs: coldStartLoadMs,
            parseP50Ms: percentile(parseLatencies, p: 0.50),
            parseP95Ms: percentile(parseLatencies, p: 0.95),
            chunkCount: executionMetrics.chunkCount,
            completedChunkCount: executionMetrics.completedChunkCount,
            checkpointCount: executionMetrics.checkpointCount,
            thermalPauseCount: executionMetrics.thermalPauseCount,
            thermalPauseTotalMs: executionMetrics.thermalPauseTotalMs,
            timeToSeriousThermalMs: executionMetrics.timeToSeriousThermalMs,
            timeInNominalMs: executionMetrics.timeInNominalMs,
            timeInFairMs: executionMetrics.timeInFairMs,
            timeInSeriousMs: executionMetrics.timeInSeriousMs,
            timeInCriticalMs: executionMetrics.timeInCriticalMs,
            seriousThermalDurationRatio: executionMetrics.seriousThermalDurationRatio,
            latencyFirstHalfP50Ms: executionMetrics.latencyFirstHalfP50Ms,
            latencySecondHalfP50Ms: executionMetrics.latencySecondHalfP50Ms,
            sustainedLatencyDegradationRatio: executionMetrics.sustainedLatencyDegradationRatio,
            casesPerMinute: executionMetrics.casesPerMinute,
            successfulCasesPerMinute: executionMetrics.casesPerMinute.map { $0 * passRate },
            batteryDrainPer100Cases: results.isEmpty
                ? nil
                : Double(max(0, -mobileMetrics.batteryDelta)) * 100 / Double(results.count),
            chunkRetryCount: executionMetrics.chunkRetryCount,
            chunkFailureRate: executionMetrics.chunkFailureRate,
            cpuP95: mobileMetrics.cpuP95,
            memoryP95MB: mobileMetrics.memoryP95MB,
            warnings: warnings,
            hardFailures: hardFailures,
            outputFile: resultURL.lastPathComponent,
            executionEventsFile: eventsURL?.lastPathComponent,
            checkpointManifestFile: checkpointManifestURL?.lastPathComponent,
            finalDocumentStateFile: finalDocumentStateFile,
            mobileMetrics: mobileMetrics
        )
    }

    private func runMonolithicSceneBenchmarkCase(
        parser: SceneParserService,
        record: DeviceBenchmarkSceneRecord,
        markedObjects: [MarkedObject],
        perfCollector: DeviceBenchmarkMetricsCollector
    ) async throws -> DeviceBenchmarkSceneCaseRun {
        let sourceText = normalizedSceneSourceText(record.sourceText)
        let startedAt = Date()
        perfCollector.update(
            module: "scene_generator",
            phase: "scene_case_monolithic",
            mode: config.sceneGeneratorExecutionMode.rawValue,
            note: "scene_case_started=\(record.sampleId)"
        )
        let eventStart = makeSceneExecutionEvent(
            sampleId: record.sampleId,
            chunkIndex: 1,
            chunkCount: 1,
            status: "chunk_started",
            note: "monolithic_case_start"
        )
        let result = await parser.parseBundleAsync(sourceText, markedObjects: markedObjects)
        let finalStateRelativePath = finalDocumentStateRelativePath(sampleId: record.sampleId)
        _ = try artifactStore.writeJSON(result.documentState, named: finalStateRelativePath)
        let durationMs = Date().timeIntervalSince(startedAt) * 1000
        let failureCount = result.activeSceneScript == nil ? 1 : 0
        let eventEnd = makeSceneExecutionEvent(
            sampleId: record.sampleId,
            chunkIndex: 1,
            chunkCount: 1,
            status: failureCount == 0 ? "chunk_completed" : "chunk_completed_without_active_scene",
            note: "monolithic_case_end"
        )
        return DeviceBenchmarkSceneCaseRun(
            result: result,
            metrics: DeviceBenchmarkSceneCaseExecutionMetrics(
                parseWallTimeMs: durationMs,
                chunkCount: 1,
                completedChunkCount: 1,
                checkpointCount: 0,
                thermalPauseCount: 0,
                thermalPauseTotalMs: 0,
                chunkRetryCount: retryCount(in: result),
                chunkFailureCount: failureCount
            ),
            events: [eventStart, eventEnd],
            checkpoints: [],
            finalDocumentStateFile: finalStateRelativePath
        )
    }

    private func runChunkedSceneBenchmarkCase(
        parser: SceneParserService,
        record: DeviceBenchmarkSceneRecord,
        markedObjects: [MarkedObject],
        perfCollector: DeviceBenchmarkMetricsCollector
    ) async throws -> DeviceBenchmarkSceneCaseRun {
        let sourceText = normalizedSceneSourceText(record.sourceText)
        let progressiveDescriptions = progressiveSceneDescriptions(from: sourceText)
        let policy = config.sceneGeneratorThermalPolicy
        let startedAt = Date()
        let chunkCount = max(progressiveDescriptions.count, 1)
        var completedChunkCount = 0
        var thermalPauseCount = 0
        var thermalPauseTotalMs = 0.0
        var chunkRetryCount = 0
        var chunkFailureCount = 0
        var previousState: ScriptDocumentState?
        var finalResult: SceneBundleParsingResult?
        var events: [DeviceBenchmarkSceneExecutionEvent] = []
        var checkpoints: [DeviceBenchmarkSceneCheckpointRecord] = []

        for (chunkIndex, descriptionPrefix) in progressiveDescriptions.enumerated() {
            if chunkIndex > 0 {
                let cooldownOutcome = await performThermalCooldownIfNeeded(
                    sampleId: record.sampleId,
                    chunkIndex: chunkIndex + 1,
                    chunkCount: chunkCount,
                    policy: policy,
                    perfCollector: perfCollector
                )
                thermalPauseCount += cooldownOutcome.pauseCount
                thermalPauseTotalMs += cooldownOutcome.pauseMs
                events.append(contentsOf: cooldownOutcome.events)
            }

            let parseMode: SceneBundleParseMode = previousState == nil ? .full : .append
            var attempt = 0
            var lastAttemptResult: SceneBundleParsingResult?

            repeat {
                attempt += 1
                let status = attempt == 1 ? "chunk_started" : "chunk_retry_started"
                events.append(
                    makeSceneExecutionEvent(
                        sampleId: record.sampleId,
                        chunkIndex: chunkIndex + 1,
                        chunkCount: chunkCount,
                        status: status,
                        note: "attempt=\(attempt);mode=\(parseMode.rawValue)"
                    )
                )
                perfCollector.update(
                    module: "scene_generator",
                    phase: "scene_case_chunk_\(chunkIndex + 1)",
                    mode: config.sceneGeneratorExecutionMode.rawValue,
                    note: "scene_case=\(record.sampleId);chunk=\(chunkIndex + 1)/\(chunkCount);attempt=\(attempt)"
                )
                let candidate = await parser.parseBundleAsync(
                    descriptionPrefix,
                    markedObjects: markedObjects,
                    mode: parseMode,
                    previousState: previousState
                )
                lastAttemptResult = candidate
                if shouldRetryChunkResult(candidate), attempt < max(1, policy.maxChunkAttempts) {
                    chunkRetryCount += 1
                    events.append(
                        makeSceneExecutionEvent(
                            sampleId: record.sampleId,
                            chunkIndex: chunkIndex + 1,
                            chunkCount: chunkCount,
                            status: "chunk_retry_scheduled",
                            note: "attempt=\(attempt)"
                        )
                    )
                    perfCollector.mark(note: "scene_case=\(record.sampleId);chunk_retry=\(chunkIndex + 1)")
                } else {
                    break
                }
            } while true

            guard let chunkResult = lastAttemptResult else { continue }
            previousState = chunkResult.documentState
            finalResult = chunkResult
            completedChunkCount += 1
            if chunkResult.activeSceneScript == nil {
                chunkFailureCount += 1
            }
            let completionStatus = chunkResult.activeSceneScript == nil
                ? "chunk_completed_without_active_scene"
                : "chunk_completed"
            events.append(
                makeSceneExecutionEvent(
                    sampleId: record.sampleId,
                    chunkIndex: chunkIndex + 1,
                    chunkCount: chunkCount,
                    status: completionStatus,
                    note: "attempts=\(attempt)"
                )
            )
            perfCollector.mark(note: "scene_case=\(record.sampleId);chunk_completed=\(chunkIndex + 1)/\(chunkCount)")

            if policy.checkpointEnabled {
                let relativePath = checkpointRelativePath(sampleId: record.sampleId, chunkIndex: chunkIndex + 1)
                _ = try artifactStore.writeJSON(chunkResult.documentState, named: relativePath)
                checkpoints.append(
                    DeviceBenchmarkSceneCheckpointRecord(
                        sampleId: record.sampleId,
                        executionMode: config.sceneGeneratorExecutionMode.rawValue,
                        chunkIndex: chunkIndex + 1,
                        sourceLength: descriptionPrefix.count,
                        thermalState: deviceBenchmarkThermalStateDescription(ProcessInfo.processInfo.thermalState),
                        checkpointFile: relativePath,
                        timestamp: Date()
                    )
                )
                events.append(
                    makeSceneExecutionEvent(
                        sampleId: record.sampleId,
                        chunkIndex: chunkIndex + 1,
                        chunkCount: chunkCount,
                        status: "checkpoint_written",
                        note: relativePath
                    )
                )
            }
        }

        let result: SceneBundleParsingResult
        if let finalResult {
            result = finalResult
        } else {
            result = await parser.parseBundleAsync(sourceText, markedObjects: markedObjects)
        }
        let finalStateRelativePath = finalDocumentStateRelativePath(sampleId: record.sampleId)
        _ = try artifactStore.writeJSON(result.documentState, named: finalStateRelativePath)
        let durationMs = Date().timeIntervalSince(startedAt) * 1000
        return DeviceBenchmarkSceneCaseRun(
            result: result,
            metrics: DeviceBenchmarkSceneCaseExecutionMetrics(
                parseWallTimeMs: durationMs,
                chunkCount: chunkCount,
                completedChunkCount: completedChunkCount,
                checkpointCount: checkpoints.count,
                thermalPauseCount: thermalPauseCount,
                thermalPauseTotalMs: thermalPauseTotalMs,
                chunkRetryCount: chunkRetryCount + retryCount(in: result),
                chunkFailureCount: chunkFailureCount
            ),
            events: events,
            checkpoints: checkpoints,
            finalDocumentStateFile: finalStateRelativePath
        )
    }

    private func normalizedSceneSourceText(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func performThermalCooldownIfNeeded(
        sampleId: String,
        chunkIndex: Int,
        chunkCount: Int,
        policy: SceneGeneratorMobileExecutionPolicy,
        perfCollector: DeviceBenchmarkMetricsCollector
    ) async -> (pauseCount: Int, pauseMs: Double, events: [DeviceBenchmarkSceneExecutionEvent]) {
        let initialState = ProcessInfo.processInfo.thermalState
        var budgetMs = thermalCooldownBudget(for: initialState, policy: policy)
        guard budgetMs > 0 else {
            return (0, 0, [])
        }

        let pollingIntervalMs = 1_000
        var waitedMs = 0
        var currentState = initialState
        var events: [DeviceBenchmarkSceneExecutionEvent] = [
            makeSceneExecutionEvent(
                sampleId: sampleId,
                chunkIndex: chunkIndex,
                chunkCount: chunkCount,
                status: "thermal_pause_started",
                note: "thermal_start=\(deviceBenchmarkThermalStateDescription(initialState));budget_ms=\(budgetMs)"
            )
        ]

        perfCollector.update(
            module: "scene_generator",
            phase: "thermal_cooldown",
            mode: config.sceneGeneratorExecutionMode.rawValue,
            note: "scene_case=\(sampleId);chunk=\(chunkIndex)/\(chunkCount);thermal_start=\(deviceBenchmarkThermalStateDescription(initialState));budget_ms=\(budgetMs)"
        )
        perfCollector.mark(note: "scene_case=\(sampleId);cooldown_started")

        while waitedMs < budgetMs {
            let sleepMs = min(pollingIntervalMs, budgetMs - waitedMs)
            try? await Task.sleep(nanoseconds: UInt64(sleepMs) * 1_000_000)
            waitedMs += sleepMs
            currentState = ProcessInfo.processInfo.thermalState
            budgetMs = max(budgetMs, thermalCooldownBudget(for: currentState, policy: policy))
            if thermalCooldownBudget(for: currentState, policy: policy) == 0 {
                break
            }
        }

        let completionReason = thermalCooldownBudget(for: currentState, policy: policy) == 0
            ? "cooled"
            : "budget_exhausted"
        events.append(
            makeSceneExecutionEvent(
                sampleId: sampleId,
                chunkIndex: chunkIndex,
                chunkCount: chunkCount,
                status: "thermal_pause_completed",
                note: "actual_wait_ms=\(waitedMs);thermal_start=\(deviceBenchmarkThermalStateDescription(initialState));thermal_end=\(deviceBenchmarkThermalStateDescription(currentState));result=\(completionReason)"
            )
        )
        perfCollector.mark(
            note: "scene_case=\(sampleId);cooldown_completed;wait_ms=\(waitedMs);thermal_end=\(deviceBenchmarkThermalStateDescription(currentState));result=\(completionReason)"
        )

        return waitedMs > 0 ? (1, Double(waitedMs), events) : (0, 0, [])
    }

    private func thermalCooldownBudget(
        for thermalState: ProcessInfo.ThermalState,
        policy: SceneGeneratorMobileExecutionPolicy
    ) -> Int {
        switch thermalState {
        case .critical:
            return policy.cooldownOnCriticalMs
        case .serious:
            return policy.cooldownOnSeriousMs
        default:
            return 0
        }
    }

    private func progressiveSceneDescriptions(from description: String) -> [String] {
        let normalized = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return [description]
        }

        let segments = semanticSceneSegments(from: normalized)
        guard segments.count > 1 else {
            return [description]
        }
        let segmentEndIndices = semanticSegmentEndIndices(in: normalized, segments: segments)
        guard segmentEndIndices.count == segments.count else {
            return [description]
        }

        let maxPrefixCount = config.tier == .quick ? 3 : 4
        let targetPrefixCount = min(maxPrefixCount, segments.count)
        var prefixes: [String] = []
        for prefixOrdinal in 1..<targetPrefixCount {
            let cutoffSegmentIndex = Int(ceil(Double(prefixOrdinal * segments.count) / Double(targetPrefixCount))) - 1
            let clampedIndex = min(max(cutoffSegmentIndex, 0), segments.count - 2)
            let prefix = String(normalized[..<segmentEndIndices[clampedIndex]])
            let trimmedPrefix = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedPrefix.isEmpty, prefixes.last != trimmedPrefix {
                prefixes.append(trimmedPrefix)
            }
        }

        if prefixes.isEmpty {
            return [description]
        }
        if prefixes.last != normalized {
            prefixes.append(normalized)
        }
        return prefixes
    }

    private func semanticSceneSegments(from description: String) -> [String] {
        let lineSegments = description
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lineSegments.isEmpty else {
            return []
        }

        var segments: [String] = []
        for line in lineSegments {
            for sentence in sentenceLikeSegments(from: line) {
                let transitionSegments = splitBySceneTransitionMarkers(sentence)
                for segment in transitionSegments {
                    let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        segments.append(trimmed)
                    }
                }
            }
        }
        return segments.isEmpty ? [description] : segments
    }

    private func semanticSegmentEndIndices(in text: String, segments: [String]) -> [String.Index] {
        var searchStart = text.startIndex
        var endIndices: [String.Index] = []

        for segment in segments {
            guard let range = text.range(of: segment, options: [], range: searchStart..<text.endIndex) else {
                return []
            }
            endIndices.append(range.upperBound)
            searchStart = range.upperBound
        }

        return endIndices
    }

    private func sentenceLikeSegments(from text: String) -> [String] {
        let pattern = #"[^.!?…;]+[.!?…;]?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        let segments = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            let candidate = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return candidate.isEmpty ? nil : candidate
        }
        return segments.isEmpty ? [text] : segments
    }

    private func splitBySceneTransitionMarkers(_ text: String) -> [String] {
        let markers = [
            " а потом ",
            " а затем ",
            " затем ",
            " потом ",
            " после этого ",
            " далее ",
            " afterwards ",
        ]
        let lowercase = text.lowercased()
        var cutIndices: [String.Index] = []

        for marker in markers {
            var searchStart = lowercase.startIndex
            while searchStart < lowercase.endIndex,
                  let range = lowercase.range(of: marker, options: [], range: searchStart..<lowercase.endIndex) {
                cutIndices.append(range.lowerBound)
                searchStart = range.upperBound
            }
        }

        let sortedCuts = Array(Set(cutIndices)).sorted()
        guard !sortedCuts.isEmpty else {
            return [text]
        }

        var segments: [String] = []
        var start = text.startIndex
        for cut in sortedCuts where cut > start {
            let segment = String(text[start..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !segment.isEmpty {
                segments.append(segment)
            }
            start = cut
        }

        let tail = String(text[start...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            segments.append(tail)
        }
        return segments.isEmpty ? [text] : segments
    }

    private func shouldRetryChunkResult(_ result: SceneBundleParsingResult) -> Bool {
        guard result.activeSceneScript == nil else { return false }
        return true
    }

    private func retryCount(in result: SceneBundleParsingResult) -> Int {
        result.chunkDiagnostics.reduce(0) { partial, diagnostics in
            partial + diagnostics.reasonCodes.filter { $0.contains("retry") }.count
        }
    }

    private func makeSceneExecutionEvent(
        sampleId: String,
        chunkIndex: Int,
        chunkCount: Int,
        status: String,
        note: String?
    ) -> DeviceBenchmarkSceneExecutionEvent {
        DeviceBenchmarkSceneExecutionEvent(
            timestamp: Date(),
            sampleId: sampleId,
            executionMode: config.sceneGeneratorExecutionMode.rawValue,
            chunkIndex: chunkIndex,
            chunkCount: chunkCount,
            status: status,
            thermalState: deviceBenchmarkThermalStateDescription(ProcessInfo.processInfo.thermalState),
            batteryLevel: UIDevice.current.batteryLevel,
            note: note
        )
    }

    private func checkpointRelativePath(sampleId: String, chunkIndex: Int) -> String {
        let safeSampleId = sanitizedArtifactComponent(sampleId)
        let chunkLabel = String(format: "%02d", chunkIndex)
        return "scene_checkpoints/\(safeSampleId)/chunk_\(chunkLabel)_document_state.json"
    }

    private func finalDocumentStateRelativePath(sampleId: String) -> String {
        let safeSampleId = sanitizedArtifactComponent(sampleId)
        return "scene_checkpoints/\(safeSampleId)/final_document_state.json"
    }

    private func sanitizedArtifactComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "_"
        }
        return String(scalars)
    }

    private func makeMarkdownSummary(combined: DeviceBenchmarkCombinedSummary,
                                     deviceStart: DeviceBenchmarkDeviceSnapshot,
                                     deviceEnd: DeviceBenchmarkDeviceSnapshot) -> String {
        [
            "# Device Benchmark Summary",
            "",
            "- `run_id`: \(combined.runId)",
            "- `tier`: \(combined.tier)",
            "- `modules`: \(combined.enabledModules.joined(separator: ", "))",
            "- `status`: \(combined.overallStatus)",
            "- `device`: \(deviceStart.deviceModel) / \(deviceStart.systemName) \(deviceStart.systemVersion)",
            "- `battery`: \(String(format: "%.0f%%", deviceStart.batteryLevel * 100)) -> \(String(format: "%.0f%%", deviceEnd.batteryLevel * 100))",
            "- `thermal`: \(deviceStart.thermalState) -> \(deviceEnd.thermalState)",
            combined.failureReason.map { "- `failure_reason`: \($0)" },
            "",
            "Artifacts:",
            "- `run_manifest.json`",
            "- `device_info.json`",
            "- `perf_samples.jsonl`",
            combined.cameraSummaryFile.map { "- `\($0)`" } ?? "- `camera summary`: not requested",
            combined.sceneSummaryFile.map { "- `\($0)`" } ?? "- `scene summary`: not requested",
            "- `combined_summary.json`"
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }

    private func loadJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(type, from: data)
    }

    private func loadJSONLines<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        let data = try Data(contentsOf: url)
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let decoder = JSONDecoder()
        return try lines.map { line in
            try decoder.decode(type, from: Data(line.utf8))
        }
    }

    private func writeSemanticRows(_ rows: [SemanticEvalCandidateOutput], named name: String) throws -> URL {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let lines = try rows.map { row -> String in
            let data = try encoder.encode(row)
            return String(decoding: data, as: UTF8.self)
        }
        return try artifactStore.writeLines(lines, named: name)
    }

    private func makePixelBuffer(from imageURL: URL) throws -> CVPixelBuffer {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(
                domain: "DeviceBenchmarkCoordinator",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Could not load image at \(imageURL.path)"]
            )
        }

        let width = image.width
        let height = image.height
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw NSError(
                domain: "DeviceBenchmarkCoordinator",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Could not create pixel buffer for \(imageURL.lastPathComponent)"]
            )
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else {
            throw NSError(
                domain: "DeviceBenchmarkCoordinator",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context for \(imageURL.lastPathComponent)"]
            )
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    private func resolveSceneModelPath() throws -> String {
        if let explicit = ProcessInfo.processInfo.environment["SG_LIVE_MODEL_PATH"],
           !explicit.isEmpty,
           FileManager.default.fileExists(atPath: explicit) {
            return explicit
        }

        let directCandidates = [
            Bundle.main.path(forResource: "dataset_v9_event_sft_q4_k_m", ofType: "gguf"),
            Bundle.main.path(forResource: "dataset_v9_event_sft_q4_k_m", ofType: "gguf", inDirectory: "Models"),
            Bundle.main.path(forResource: "dataset_v9_event_sft_q4_k_m", ofType: "gguf", inDirectory: "Resources/Models"),
        ].compactMap { $0 }

        if let first = directCandidates.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return first
        }

        let bundledCandidates = discoverBundledSceneModelURLs()
            .map { ($0, sceneModelSelectionScore(for: $0.lastPathComponent.lowercased())) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 {
                    return lhs.0.lastPathComponent < rhs.0.lastPathComponent
                }
                return lhs.1 > rhs.1
            }

        if let selected = bundledCandidates.first, selected.1 > 0 {
            return selected.0.path
        }

        let fallbackPaths = [
            "shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf",
        ]
        if let existing = fallbackPaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            return existing
        }

        throw NSError(
            domain: "DeviceBenchmarkCoordinator",
            code: 5,
            userInfo: [NSLocalizedDescriptionKey: "Could not resolve scene generator runtime model."]
        )
    }

    private func discoverBundledSceneModelURLs() -> [URL] {
        let resourceRoots = ([Bundle.main] + Bundle.allBundles + Bundle.allFrameworks)
            .compactMap(\.resourceURL)
        var seenPaths = Set<String>()
        var urls: [URL] = []

        for resourceRoot in resourceRoots {
            guard seenPaths.insert(resourceRoot.path).inserted else { continue }
            guard let enumerator = FileManager.default.enumerator(
                at: resourceRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "gguf" {
                urls.append(fileURL)
            }
        }

        return urls
    }

    private func sceneModelSelectionScore(for filename: String) -> Int {
        var score = 0
        if filename.contains("v9.3") { score += 400 }
        if filename.contains("v9") { score += 250 }
        if filename.contains("event") { score += 80 }
        if filename.contains("sft") { score += 40 }
        if filename.contains("q4") { score += 20 }
        if filename.contains("qwen2.5") { score -= 1000 }
        return score
    }

    private func loadingStateDescription(_ state: LLMParserService.LoadingState) -> String {
        switch state {
        case .notLoaded:
            return "not_loaded"
        case .loading:
            return "loading"
        case .loaded:
            return "loaded"
        case .failed(let reason):
            return "failed(\(reason))"
        }
    }

    private func sampledSceneRecords(from packDirectory: URL) throws -> [DeviceBenchmarkSceneRecord] {
        let core = try loadJSONLines(DeviceBenchmarkSceneRecord.self,
                                     from: packDirectory.appendingPathComponent("core_accepted_source.jsonl"))
        let hard = try loadJSONLines(DeviceBenchmarkSceneRecord.self,
                                     from: packDirectory.appendingPathComponent("hard_accepted_source.jsonl"))
        let selectedPatterns = [
            "dialogue_only",
            "dialogue_then_put_down_object",
            "dialogue_then_pick_up_object_then_give_to_third_actor",
            "ordinal_first_second_third",
            "toward_each_other_then_pass_by_marked_object",
            "same_type_two_marked_objects",
        ]
        let preferredOrder: [String: Int] = [
            "dialogue_then_pick_up_object_then_give_to_third_actor": 0,
            "dialogue_then_put_down_object": 1,
            "same_type_two_marked_objects": 2,
            "toward_each_other_then_pass_by_marked_object": 3,
            "ordinal_first_second_third": 4,
            "dialogue_only": 5,
        ]

        let records = (core + hard).filter { selectedPatterns.contains($0.patternName) }
        let grouped = Dictionary(grouping: records, by: \.patternName)
        let orderedPatterns = selectedPatterns.sorted {
            preferredOrder[$0, default: Int.max] < preferredOrder[$1, default: Int.max]
        }
        let caseLimit = config.tier == .quick ? 12 : 64
        let quotaPerPattern = max(1, caseLimit / max(1, orderedPatterns.count))
        var generator = DeviceBenchmarkSeededGenerator(seed: config.tier == .quick ? 20260615 : 20260616)
        var sampled: [DeviceBenchmarkSceneRecord] = []
        var seenSampleIds = Set<String>()

        for pattern in orderedPatterns {
            guard var pool = grouped[pattern], !pool.isEmpty else { continue }
            var pickedForPattern = 0
            while !pool.isEmpty && pickedForPattern < quotaPerPattern && sampled.count < caseLimit {
                let index = generator.nextInt(upperBound: pool.count)
                let candidate = pool.remove(at: index)
                guard seenSampleIds.insert(candidate.sampleId).inserted else { continue }
                sampled.append(candidate)
                pickedForPattern += 1
            }
        }

        if sampled.count < caseLimit {
            var remaining = grouped.values.flatMap { $0 }.filter { !seenSampleIds.contains($0.sampleId) }
            while !remaining.isEmpty && sampled.count < caseLimit {
                let index = generator.nextInt(upperBound: remaining.count)
                let candidate = remaining.remove(at: index)
                guard seenSampleIds.insert(candidate.sampleId).inserted else { continue }
                sampled.append(candidate)
            }
        }

        return sampled
    }

    private func sceneExpectation(for record: DeviceBenchmarkSceneRecord) -> DeviceBenchmarkSceneExpectation? {
        switch record.patternName {
        case "dialogue_only":
            return DeviceBenchmarkSceneExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 2),
                requiresDialogue: true,
                requiredActionTypes: [],
                markedObjectFloor: 0,
                expectsSameTypeConflict: false
            )
        case "dialogue_then_put_down_object":
            return DeviceBenchmarkSceneExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 2),
                requiresDialogue: true,
                requiredActionTypes: [.putDown],
                markedObjectFloor: 0,
                expectsSameTypeConflict: false
            )
        case "dialogue_then_pick_up_object_then_give_to_third_actor":
            return DeviceBenchmarkSceneExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 3),
                requiresDialogue: true,
                requiredActionTypes: [.pickUp, .give],
                markedObjectFloor: 0,
                expectsSameTypeConflict: false
            )
        case "ordinal_first_second_third":
            return DeviceBenchmarkSceneExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 3),
                requiresDialogue: false,
                requiredActionTypes: [.approach],
                markedObjectFloor: 0,
                expectsSameTypeConflict: false
            )
        case "toward_each_other_then_pass_by_marked_object":
            return DeviceBenchmarkSceneExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 2),
                requiresDialogue: false,
                requiredActionTypes: [.walk, .passBy],
                markedObjectFloor: record.graphConstraints.markedObjects.count,
                expectsSameTypeConflict: false
            )
        case "same_type_two_marked_objects":
            return DeviceBenchmarkSceneExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 2),
                requiresDialogue: false,
                requiredActionTypes: [],
                markedObjectFloor: record.graphConstraints.markedObjects.count,
                expectsSameTypeConflict: record.graphConstraints.sameTypeMarkerConflict
            )
        default:
            return nil
        }
    }

    private func makeMarkedObjects(from record: DeviceBenchmarkSceneRecord) -> [MarkedObject] {
        record.graphConstraints.markedObjects.enumerated().map { index, marker in
            MarkedObject(
                name: marker.canonicalName,
                position: Position3D(x: Float(index), y: 0, z: Float(-index))
            )
        }
    }

    private func evaluateSceneRecord(record: DeviceBenchmarkSceneRecord,
                                     result: SceneBundleParsingResult,
                                     trace: SceneRuntimeTrace?,
                                     parseWallTimeMs: Double,
                                     coldStart: Bool) -> DeviceBenchmarkSceneCaseResult {
        let expectation = sceneExpectation(for: record)
        let activeScene = result.activeSceneScript
        let actions = activeScene?.actions ?? []
        let matchedMarkedCount = Set(result.diagnostics.matchedMarkedObjects).count
        var hardIssues: [String] = []
        var softIssues: [String] = []

        if activeScene == nil {
            hardIssues.append("missing_active_scene")
        }

        if let activeScene {
            if activeScene.beats.isEmpty {
                hardIssues.append("empty_beats")
            }
            if result.chunkDiagnostics.contains(where: \.usedFallbackPlanner) {
                hardIssues.append("fallback_planner_used")
            }
            if let expectation {
                if activeScene.actors.count < expectation.actorFloor {
                    hardIssues.append("actor_floor_\(activeScene.actors.count)_of_\(expectation.actorFloor)")
                }
                if expectation.requiresDialogue {
                    let hasDialogue = actions.contains { action in
                        action.type == .talk || !(action.dialogue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    if !hasDialogue {
                        hardIssues.append("missing_dialogue")
                    }
                }
                for requiredAction in expectation.requiredActionTypes where !actions.contains(where: { $0.type == requiredAction }) {
                    hardIssues.append("missing_action_\(requiredAction.rawValue)")
                }
                if matchedMarkedCount < expectation.markedObjectFloor {
                    hardIssues.append("matched_marked_objects_\(matchedMarkedCount)_of_\(expectation.markedObjectFloor)")
                }
                if expectation.expectsSameTypeConflict {
                    let detectedConflict = result.chunkDiagnostics.contains { $0.anchors.sourceBundle.sameTypeMarkerConflict }
                    if !detectedConflict {
                        softIssues.append("same_type_conflict_not_detected")
                    }
                }
            }
        }

        if result.diagnostics.confidence < 0.6 {
            softIssues.append("low_confidence_\(String(format: "%.2f", result.diagnostics.confidence))")
        }
        if let verdict = record.validationReport?.criticVerdict, verdict != "pass" {
            softIssues.append("dataset_critic_\(verdict)")
        }
        for failure in record.validationReport?.criticDetectedFailures ?? [] {
            softIssues.append("dataset_flag_\(failure)")
        }

        return DeviceBenchmarkSceneCaseResult(
            sampleId: record.sampleId,
            patternName: record.patternName,
            difficultyBucket: record.difficultyBucket,
            coldStart: coldStart,
            parseWallTimeMs: parseWallTimeMs,
            actorCount: activeScene?.actors.count ?? 0,
            beatCount: activeScene?.beats.count ?? 0,
            actionCount: actions.count,
            confidence: result.diagnostics.confidence,
            route: trace?.route.rawValue,
            reasonCodes: trace?.reasons ?? [],
            hardIssues: hardIssues,
            softIssues: softIssues,
            passed: hardIssues.isEmpty
        )
    }
}

struct DeviceBenchmarkRootView: View {
    @StateObject private var coordinator: DeviceBenchmarkCoordinator
    let interactive: Bool

    init(config: DeviceBenchmarkConfig, interactive: Bool = true) {
        _coordinator = StateObject(wrappedValue: DeviceBenchmarkCoordinator(config: config))
        self.interactive = interactive
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.10, blue: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            if let scenario = coordinator.activeGuidedScenario {
                ZStack(alignment: .topLeading) {
                    ContentView()
                    guidedOverlay(for: scenario)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Device Benchmark")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(.white)

                    Text(coordinator.statusText)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.92))
                        .accessibilityIdentifier("deviceBenchmarkStatusLabel")

                    if coordinator.isRunning {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Button("Start Benchmark") {
                            coordinator.start(interactive: interactive)
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier("deviceBenchmarkStartButton")
                    }

                    if !coordinator.combinedSummaryMarkdown.isEmpty {
                        ScrollView {
                            Text(coordinator.combinedSummaryMarkdown)
                                .font(.system(size: 13, design: .monospaced))
                                .foregroundColor(.white.opacity(0.88))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        Spacer()
                    }
                }
                .padding(24)
            }
        }
        .task {
            coordinator.startIfNeeded(interactive: interactive)
        }
    }

    private func guidedOverlay(for scenario: DeviceBenchmarkGuidedScenario) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Guided Live Scenario")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text(scenario.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white.opacity(0.95))

            ForEach(Array(scenario.instructions.enumerated()), id: \.offset) { index, instruction in
                Text("\(index + 1). \(instruction)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.88))
            }

            Text("Suggested duration: \(scenario.durationSeconds)s")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.76))

            Button("Finish Scenario") {
                coordinator.completeGuidedScenario()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("deviceBenchmarkCompleteButton")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
        .padding(16)
        .accessibilityIdentifier("deviceBenchmarkGuidedOverlay")
    }
}

#endif
