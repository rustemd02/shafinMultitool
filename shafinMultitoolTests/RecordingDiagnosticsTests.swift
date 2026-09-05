import XCTest
@testable import shafinMultitool

/// M7-030: bounded, versioned, redacted recording diagnostics — schema,
/// size cap, and production-recorder emission, without any media content.
final class RecordingDiagnosticsTests: XCTestCase {

    func testRingBufferIsBoundedAndOrdered() {
        let log = RecordingDiagnosticsLog(capacity: 16)
        for index in 0..<40 {
            log.emit(.stopCompleted(outcome: "finalized", failure: nil),
                     recordingID: UUID())
        }

        XCTAssertEqual(log.emittedEventCount, 16)
        let events = log.exportedEvents()
        XCTAssertEqual(events.count, 16)
        XCTAssertEqual(events.map(\.schemaVersion),
                       Array(repeating: RecordingDiagnosticsEvent.schemaVersion, count: 16))
        // Timestamps are monotonic in emission order (oldest first).
        XCTAssertTrue(zip(events, events.dropFirst()).allSatisfy { $0.0.timestamp <= $0.1.timestamp })
    }

    func testEventsCarryOnlyTypedFieldsAndNeverPayloads() {
        let log = RecordingDiagnosticsLog()
        let recordingID = UUID()
        log.emit(.stateChanged(from: "idle", to: "recording"), recordingID: recordingID)
        log.emit(.admission(acceptedVideo: 12, acceptedAudio: 11,
                            rejectedInactive: 1, rejectedStaleSource: 2,
                            rejectedTimelineFaults: 0),
                 recordingID: recordingID)
        log.emit(.backpressure(droppedVideo: 3, droppedAudio: 0), recordingID: recordingID)
        log.emit(.diskBudget(requiredBytes: 1_000_000, availableBytes: 5_000_000, satisfied: true),
                 recordingID: recordingID)
        log.emit(.sync(startDeltaSeconds: 0.03, endDeltaSeconds: 0.02, withinReleaseCriterion: true),
                 recordingID: recordingID)

        let events = log.exportedEvents()
        XCTAssertEqual(events.count, 5)
        XCTAssertTrue(events.allSatisfy { $0.recordingID == recordingID })
        // Codable round-trip proves the schema is machine-readable for export.
        let encoded = try! JSONEncoder().encode(events)
        let decoded = try! JSONDecoder().decode([RecordingDiagnosticsEvent].self, from: encoded)
        XCTAssertEqual(decoded, events)
        // Redaction: the JSON payload contains no path-like or payload-like text.
        let json = String(decoding: encoded, as: UTF8.self)
        XCTAssertFalse(json.contains("/"), "diagnostics must never contain path strings")
        XCTAssertFalse(json.lowercased().contains("mov"))
    }

    func testSerializedRecorderEmitsLifecycleAndTerminalDiagnostics() async throws {
        let diagnostics = RecordingDiagnosticsLog(capacity: 64)
        let writer = RecordingDiagnosticsTestsWriter()
        let recorder = SerializedMediaRecorder(
            writerFactory: RecordingDiagnosticsWriterFactory(writer: writer),
            audioDriverFactory: nil,
            diagnostics: diagnostics
        )

        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("diag-\(UUID().uuidString).mov"),
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        try await recorder.prepare(configuration)
        try await recorder.start()
        let snapshot = await recorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))
        _ = await recorder.stop(reason: .user)
        _ = await recorder.releaseAndWait()

        let events = diagnostics.exportedEvents()
        let states = events.compactMap { event -> String? in
            if case let .stateChanged(_, to) = event.kind { return to }
            return nil
        }
        // Diagnostics use the canonical M1-010 lifecycle vocabulary.
        XCTAssertEqual(states, ["ready", "recording", "finalizing", "completed", "released"])

        let stopEvents = events.filter {
            if case .stopCompleted = $0.kind { return true }
            return false
        }
        XCTAssertEqual(stopEvents.count, 1)
        XCTAssertEqual(stopEvents.first?.recordingID, configuration.id.rawValue)
        if case let .stopCompleted(outcome, failure) = stopEvents.first!.kind {
            XCTAssertEqual(outcome, "finalized")
            XCTAssertNil(failure)
        } else {
            XCTFail("expected a stopCompleted event")
        }
    }

    func testThermalPostureIsEmittedAtStart() async throws {
        let diagnostics = RecordingDiagnosticsLog(capacity: 64)
        let writer = RecordingDiagnosticsTestsWriter()
        let recorder = SerializedMediaRecorder(
            writerFactory: RecordingDiagnosticsWriterFactory(writer: writer),
            audioDriverFactory: nil,
            diagnostics: diagnostics
        )
        let configuration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("diag-\(UUID().uuidString).mov"),
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        try await recorder.prepare(configuration)
        try await recorder.start()
        _ = await recorder.stop(reason: .user)

        let thermalEvents = diagnostics.exportedEvents().compactMap { event -> String? in
            if case let .thermal(state) = event.kind { return state }
            return nil
        }
        XCTAssertEqual(thermalEvents.count, 1)
        XCTAssertTrue(["nominal", "fair", "serious", "critical"].contains(thermalEvents.first))
        XCTAssertEqual(thermalEvents.first,
                       SerializedMediaRecorder.thermalStateNameForTesting(ProcessInfo.processInfo.thermalState))
    }

    func testStoragePressureAndDropPolicyAreEmitted() async throws {
        // ENOSPC-class append failure emits the typed storage-pressure event.
        let pressureDiagnostics = RecordingDiagnosticsLog(capacity: 64)
        let pressureWriter = RecordingDiagnosticsTestsWriter()
        pressureWriter.videoAppendResult = .storagePressure
        let pressureRecorder = SerializedMediaRecorder(
            writerFactory: RecordingDiagnosticsWriterFactory(writer: pressureWriter),
            audioDriverFactory: nil,
            maxConsecutiveDroppedFrames: 900,
            diagnostics: pressureDiagnostics
        )
        let pressureConfiguration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("diag-\(UUID().uuidString).mov"),
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        try await pressureRecorder.prepare(pressureConfiguration)
        try await pressureRecorder.start()
        let snapshot = await pressureRecorder.stateSnapshot()
        let fence = try XCTUnwrap(snapshot.frameFence)
        pressureRecorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))
        _ = await pressureRecorder.stop(reason: .user)

        XCTAssertTrue(pressureDiagnostics.exportedEvents().map(\.kind).contains { kind in
            if case .storagePressure = kind { return true }
            return false
        })

        // Sustained backpressure reaching the policy limit emits dropPolicyFired.
        let dropDiagnostics = RecordingDiagnosticsLog(capacity: 64)
        let dropWriter = RecordingDiagnosticsTestsWriter()
        dropWriter.videoAppendResult = .dropped
        let dropRecorder = SerializedMediaRecorder(
            writerFactory: RecordingDiagnosticsWriterFactory(writer: dropWriter),
            audioDriverFactory: nil,
            maxConsecutiveDroppedFrames: 1,
            diagnostics: dropDiagnostics
        )
        let dropConfiguration = RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("diag-\(UUID().uuidString).mov"),
            width: 320,
            height: 240,
            fps: 30,
            audioMode: .disabled
        )
        try await dropRecorder.prepare(dropConfiguration)
        try await dropRecorder.start()
        let dropSnapshot = await dropRecorder.stateSnapshot()
        let dropFence = try XCTUnwrap(dropSnapshot.frameFence)
        dropRecorder.enqueueVideo(RecordingVideoFrame(fence: dropFence, timestamp: 1.0))
        _ = await dropRecorder.stop(reason: .user)

        XCTAssertTrue(dropDiagnostics.exportedEvents().map(\.kind).contains { kind in
            if case .dropPolicyFired = kind { return true }
            return false
        })
    }
}

// MARK: - Minimal writer fixtures

private final class RecordingDiagnosticsWriterFactory: RecordingWriterFactory {
    let writer: RecordingDiagnosticsTestsWriter

    init(writer: RecordingDiagnosticsTestsWriter) {
        self.writer = writer
    }

    func makeWriter(for configuration: RecordingConfiguration) throws -> any RecordingWriter {
        writer
    }
}

private final class RecordingDiagnosticsTestsWriter: RecordingWriter {
    var startResult = true
    var videoAppendResult: RecordingAppendDisposition = .appended
    private let lock = NSLock()
    private var finishCompletion: ((Result<RecordingWriterFinish, RecordingWriterError>) -> Void)?

    func start() -> Bool { startResult }

    func appendVideo(_ frame: RecordingVideoFrame) -> RecordingAppendDisposition {
        videoAppendResult
    }

    func appendAudio(_ frame: RecordingAudioFrame) -> RecordingAppendDisposition {
        .appended
    }

    func markVideoInputAsFinished() {}
    func markAudioInputAsFinished() {}

    func finishWriting(completion: @escaping (Result<RecordingWriterFinish, RecordingWriterError>) -> Void) {
        lock.lock()
        finishCompletion = completion
        lock.unlock()
        completion(.success(RecordingWriterFinish(duration: 1.0, hasAudio: false)))
    }

    func discard() {}
}
