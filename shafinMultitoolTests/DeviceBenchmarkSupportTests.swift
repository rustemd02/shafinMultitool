//
//  DeviceBenchmarkSupportTests.swift
//  shafinMultitoolTests
//
//  Created by Codex on 15.06.2026.
//

import XCTest
@testable import shafinMultitool

final class DeviceBenchmarkSupportTests: XCTestCase {
    func testBenchmarkConfigRoundTripsExecutionModeAndThermalPolicy() throws {
        let config = DeviceBenchmarkConfig(
            runId: "run-1",
            tier: .quick,
            enabledModules: [.sceneGenerator],
            sceneGeneratorModelPolicy: .explicitOrLatest,
            sceneGeneratorExecutionMode: .monolithic,
            sceneGeneratorThermalPolicy: SceneGeneratorMobileExecutionPolicy(
                mode: .monolithic,
                cooldownOnSeriousMs: 1111,
                cooldownOnCriticalMs: 2222,
                maxChunkAttempts: 3,
                checkpointEnabled: true
            ),
            cameraResourcePackId: "camera_pack",
            sceneResourcePackId: "scene_pack",
            guidedLiveEnabled: false,
            softThresholds: .default,
            autoStart: true,
            liveSequenceEnabled: true
        )

        let decoded = try XCTUnwrap(
            DeviceBenchmarkConfig.fromEnvironment(
                [DeviceBenchmarkConfig.environmentKey: try config.toBase64()]
            )
        )

        XCTAssertEqual(decoded, config)
    }

    func testSceneExecutionAggregateComputesThermalAndLatencyMetrics() {
        let start = Date(timeIntervalSince1970: 1_000)
        let samples = [
            DeviceBenchmarkPerfSample(
                timestamp: start,
                module: "scene_generator",
                phase: "case_1",
                mode: "chunkedThermalAware",
                uiFPS: 60,
                pipelineFPS: 60,
                frameTimeMs: 16.7,
                droppedFrames: 0,
                cpuUsage: 10,
                memoryMB: 100,
                batteryLevel: 0.9,
                thermalState: "nominal",
                stageLatenciesMs: [:],
                note: nil
            ),
            DeviceBenchmarkPerfSample(
                timestamp: start.addingTimeInterval(10),
                module: "scene_generator",
                phase: "case_1",
                mode: "chunkedThermalAware",
                uiFPS: 58,
                pipelineFPS: 58,
                frameTimeMs: 17.2,
                droppedFrames: 1,
                cpuUsage: 20,
                memoryMB: 110,
                batteryLevel: 0.88,
                thermalState: "serious",
                stageLatenciesMs: [:],
                note: nil
            ),
            DeviceBenchmarkPerfSample(
                timestamp: start.addingTimeInterval(20),
                module: "scene_generator",
                phase: "case_2",
                mode: "chunkedThermalAware",
                uiFPS: 57,
                pipelineFPS: 57,
                frameTimeMs: 17.5,
                droppedFrames: 1,
                cpuUsage: 25,
                memoryMB: 115,
                batteryLevel: 0.87,
                thermalState: "serious",
                stageLatenciesMs: [:],
                note: nil
            ),
            DeviceBenchmarkPerfSample(
                timestamp: start.addingTimeInterval(30),
                module: "scene_generator",
                phase: "case_2",
                mode: "chunkedThermalAware",
                uiFPS: 55,
                pipelineFPS: 55,
                frameTimeMs: 18.1,
                droppedFrames: 2,
                cpuUsage: 30,
                memoryMB: 120,
                batteryLevel: 0.86,
                thermalState: "critical",
                stageLatenciesMs: [:],
                note: nil
            ),
        ]
        let caseMetrics = [
            DeviceBenchmarkSceneCaseExecutionMetrics(
                parseWallTimeMs: 1_000,
                chunkCount: 2,
                completedChunkCount: 2,
                checkpointCount: 3,
                thermalPauseCount: 1,
                thermalPauseTotalMs: 5_000,
                chunkRetryCount: 1,
                chunkFailureCount: 0
            ),
            DeviceBenchmarkSceneCaseExecutionMetrics(
                parseWallTimeMs: 2_000,
                chunkCount: 1,
                completedChunkCount: 1,
                checkpointCount: 2,
                thermalPauseCount: 0,
                thermalPauseTotalMs: 0,
                chunkRetryCount: 0,
                chunkFailureCount: 1
            ),
        ]

        let aggregate = DeviceBenchmarkSceneExecutionAggregate.from(
            executionMode: .chunkedThermalAware,
            samples: samples,
            caseMetrics: caseMetrics
        )

        XCTAssertEqual(aggregate.executionMode, "chunkedThermalAware")
        XCTAssertEqual(aggregate.chunkCount, 3)
        XCTAssertEqual(aggregate.completedChunkCount, 3)
        XCTAssertEqual(aggregate.checkpointCount, 5)
        XCTAssertEqual(aggregate.thermalPauseCount, 1)
        XCTAssertEqual(aggregate.thermalPauseTotalMs, 5_000, accuracy: 0.001)
        XCTAssertEqual(aggregate.timeToSeriousThermalMs ?? -1, 10_000, accuracy: 0.001)
        XCTAssertEqual(aggregate.timeInNominalMs, 10_000, accuracy: 0.001)
        XCTAssertEqual(aggregate.timeInSeriousMs, 20_000, accuracy: 0.001)
        XCTAssertEqual(aggregate.timeInCriticalMs, 0, accuracy: 0.001)
        XCTAssertEqual(aggregate.seriousThermalDurationRatio ?? -1, 20_000.0 / 30_000.0, accuracy: 0.0001)
        XCTAssertEqual(aggregate.latencyFirstHalfP50Ms ?? -1, 1_000, accuracy: 0.001)
        XCTAssertEqual(aggregate.latencySecondHalfP50Ms ?? -1, 2_000, accuracy: 0.001)
        XCTAssertEqual(aggregate.sustainedLatencyDegradationRatio ?? -1, 2.0, accuracy: 0.001)
        XCTAssertEqual(aggregate.casesPerMinute ?? -1, 40.0, accuracy: 0.001)
        XCTAssertEqual(aggregate.chunkRetryCount, 1)
        XCTAssertEqual(aggregate.chunkFailureRate, 1.0 / 3.0, accuracy: 0.0001)
    }
}
