//
//  DeviceBenchmarkHarnessTests.swift
//  shafinMultitoolTests
//
//  Created by Codex on 15.06.2026.
//

import XCTest
@testable import shafinMultitool

final class DeviceBenchmarkHarnessTests: XCTestCase {
    @MainActor
    func testRunConfiguredDeviceBenchmark() async throws {
        let config = DeviceBenchmarkConfig.fromEnvironment() ?? DeviceBenchmarkConfig.defaultQuick
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
