import XCTest
@testable import shafinMultitool

final class DeviceBenchmarkResourcePackTests: XCTestCase {
    func testBundledInputResolutionDoesNotMaterializeCache() throws {
        let store = DeviceBenchmarkArtifactStore(runId: "resource-read-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store.rootURL) }

        let pack = try store.resourcePackURL(packId: "camera_device_benchmark_pack_v1")

        XCTAssertTrue(pack.standardizedFileURL.path.hasPrefix(Bundle.main.bundleURL.standardizedFileURL.path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pack.appendingPathComponent("camera_full_labels.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: pack.appendingPathComponent("semantic_demo_scenarios.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.rootURL.path))
    }

    func testFreshPreparationCopiesBundledInputsWithoutExistingDestinationFailure() throws {
        let store = DeviceBenchmarkArtifactStore(runId: "resource-copy-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let bundled = try store.resourcePackURL(packId: "camera_device_benchmark_pack_v1")

        let prepared = try store.preparePackDirectory(packId: "camera_device_benchmark_pack_v1")

        XCTAssertNotEqual(prepared, bundled)
        XCTAssertEqual(try store.preparePackDirectory(packId: "camera_device_benchmark_pack_v1"), prepared)
        for path in ["camera_device_benchmark_manifest.json", "camera_full_labels.jsonl", "semantic_demo_scenarios.json", "images/001.jpg"] {
            XCTAssertEqual(
                try Data(contentsOf: prepared.appendingPathComponent(path)),
                try Data(contentsOf: bundled.appendingPathComponent(path)),
                "Prepared input bytes changed: \(path)"
            )
        }
        let children = try FileManager.default.contentsOfDirectory(atPath: prepared.deletingLastPathComponent().path)
        XCTAssertFalse(children.contains { $0.hasSuffix(".partial") })
    }

    func testEmptyInterruptedCacheCanBePreparedAgain() throws {
        let store = DeviceBenchmarkArtifactStore(runId: "resource-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let empty = store.directoryURL("packs").appendingPathComponent("camera_device_benchmark_pack_v1", isDirectory: true)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let prepared = try store.preparePackDirectory(packId: "camera_device_benchmark_pack_v1")

        XCTAssertEqual(prepared, empty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.appendingPathComponent("camera_full_labels.jsonl").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.appendingPathComponent("images/001.jpg").path))
    }

    func testExistingNonemptyCacheIsPreserved() throws {
        let store = DeviceBenchmarkArtifactStore(runId: "resource-preserve-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let existing = store.directoryURL("packs").appendingPathComponent("camera_device_benchmark_pack_v1", isDirectory: true)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true)
        let sentinel = existing.appendingPathComponent("existing-input.txt")
        let bytes = Data("Existing cache content must survive recovery.\n".utf8)
        try bytes.write(to: sentinel)

        XCTAssertEqual(try store.preparePackDirectory(packId: "camera_device_benchmark_pack_v1"), existing)
        XCTAssertEqual(try Data(contentsOf: sentinel), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: existing.path), ["existing-input.txt"])
    }

    func testFailedPreparationDoesNotPublishOrCachePartialInputs() throws {
        let store = DeviceBenchmarkArtifactStore(runId: "resource-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: store.rootURL) }
        let unknownPack = "unavailable-test-pack-\(UUID().uuidString)"

        XCTAssertThrowsError(try store.preparePackDirectory(packId: unknownPack))
        XCTAssertThrowsError(try store.preparePackDirectory(packId: unknownPack))

        let packs = store.directoryURL("packs")
        XCTAssertFalse(FileManager.default.fileExists(atPath: packs.appendingPathComponent(unknownPack).path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: packs.path), [])
    }
}
