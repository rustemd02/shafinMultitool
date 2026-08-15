//
//  DeviceBenchmarkHarnessTests.swift
//  shafinMultitoolTests
//
//  Created by Codex on 15.06.2026.
//

import XCTest
@testable import shafinMultitool

final class DeviceBenchmarkHarnessTests: XCTestCase {
    func testBenchmarkConfigEnvironmentTreatsAbsentAndEmptyValuesAsNotConfigured() throws {
        XCTAssertNil(try DeviceBenchmarkConfig.loadFromEnvironment([:]))
        XCTAssertNil(
            try DeviceBenchmarkConfig.loadFromEnvironment(
                [DeviceBenchmarkConfig.environmentKey: ""]
            )
        )
    }

    func testBenchmarkConfigEnvironmentRejectsInvalidBase64() {
        XCTAssertThrowsError(
            try DeviceBenchmarkConfig.loadFromEnvironment(
                [DeviceBenchmarkConfig.environmentKey: "not-valid-base64"]
            )
        ) { error in
            XCTAssertEqual(error as? DeviceBenchmarkConfigEnvironmentError, .invalidBase64)
        }
    }

    func testBenchmarkConfigEnvironmentRejectsBase64PayloadThatIsNotJSON() {
        let nonJSONPayload = Data("not-json".utf8).base64EncodedString()

        XCTAssertThrowsError(
            try DeviceBenchmarkConfig.loadFromEnvironment(
                [DeviceBenchmarkConfig.environmentKey: nonJSONPayload]
            )
        ) { error in
            XCTAssertEqual(error as? DeviceBenchmarkConfigEnvironmentError, .invalidConfiguration)
        }
    }

    func testBenchmarkConfigEnvironmentRejectsDecodableBase64WithInvalidConfig() {
        let incompleteConfig = Data("{}".utf8).base64EncodedString()

        XCTAssertThrowsError(
            try DeviceBenchmarkConfig.loadFromEnvironment(
                [DeviceBenchmarkConfig.environmentKey: incompleteConfig]
            )
        ) { error in
            XCTAssertEqual(error as? DeviceBenchmarkConfigEnvironmentError, .invalidConfiguration)
        }
    }

    @MainActor
    func testRunConfiguredDeviceBenchmark() async throws {
        guard let config = try DeviceBenchmarkConfig.loadFromEnvironment() else {
            throw XCTSkip("Set DEVICE_BENCHMARK_CONFIG_BASE64 to run the physical-device benchmark harness.")
        }

        let artifactStore = DeviceBenchmarkArtifactStore(runId: config.runId)
        let coordinator = DeviceBenchmarkCoordinator(config: config)

        do {
            let result = try await coordinator.run(interactive: false)
            attachResultFiles(result)
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.combinedSummaryURL.path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: result.combinedMarkdownURL.path))
        } catch {
            attachFilesIfPresent(
                named: [
                    "run_manifest.json",
                    "device_info.json",
                    "perf_samples.jsonl",
                    "camera_summary.json",
                    "scene_summary.json",
                    "combined_summary.json",
                    "combined_summary.md",
                    "camera_still_rows.jsonl",
                    "camera_live_sequence_rows.jsonl",
                    "scene_case_results.json",
                    "scene_execution_events.jsonl",
                    "scene_checkpoint_manifest.jsonl",
                    "artifacts.zip"
                ],
                in: artifactStore
            )
            throw error
        }
    }

    private func attachFile(_ url: URL, name: String) {
        let attachment = XCTAttachment(contentsOfFile: url)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func attachResultFiles(_ result: DeviceBenchmarkRunResult) {
        attachFile(result.manifestURL, name: "run_manifest.json")
        attachFile(result.deviceInfoURL, name: "device_info.json")
        attachFile(result.perfSamplesURL, name: "perf_samples.jsonl")
        if let cameraSummaryURL = result.cameraSummaryURL {
            attachFile(cameraSummaryURL, name: cameraSummaryURL.lastPathComponent)
        }
        if let sceneSummaryURL = result.sceneSummaryURL {
            attachFile(sceneSummaryURL, name: sceneSummaryURL.lastPathComponent)
        }
        attachFile(result.combinedSummaryURL, name: "combined_summary.json")
        attachFile(result.combinedMarkdownURL, name: "combined_summary.md")
        if let artifactsArchiveURL = result.artifactsArchiveURL {
            attachFile(artifactsArchiveURL, name: "artifacts.zip")
        }
        attachFilesIfPresent(
            named: [
                "camera_still_rows.jsonl",
                "camera_live_sequence_rows.jsonl",
                "scene_case_results.json",
                "scene_execution_events.jsonl",
                "scene_checkpoint_manifest.jsonl"
            ],
            in: result.artifactStore
        )
    }

    private func attachFilesIfPresent(named names: [String], in artifactStore: DeviceBenchmarkArtifactStore) {
        for name in names {
            let url = artifactStore.fileURL(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            attachFile(url, name: name)
        }
    }
}
