//
//  RecordingLifecycleTransitionTests.swift
//  shafinMultitoolTests
//
//  M1-010 RecordingOwner: the canonical recording lifecycle is the single
//  state vocabulary shared by SerializedMediaRecorder, SceneRecordingController
//  and the legacy CameraService writer path. These tests pin the transition
//  table, the RecorderState mapping, and the serialized recorder/controller
//  behavior on top of it.
//

import XCTest
import CoreVideo
@testable import shafinMultitool

final class RecordingLifecycleTransitionTests: XCTestCase {

    // MARK: - Canonical transition table

    func testTransitionTableMatchesSpecifiedAdjacency() {
        let legal: [RecordingLifecycleState: Set<RecordingLifecycleState>] = [
            .idle: [.preparing, .ready, .starting, .recording, .failed, .cancelled, .released],
            .preparing: [.ready, .failed, .cancelled, .released],
            .ready: [.starting, .recording, .failed, .cancelled, .released],
            .starting: [.recording, .stopping, .idle, .failed, .cancelled, .released],
            .recording: [.stopping, .finalizing, .idle, .failed, .cancelled, .released],
            .stopping: [.finalizing, .completed, .idle, .failed, .cancelled, .released],
            .finalizing: [.promoting, .completed, .failed, .cancelled, .idle, .released],
            .promoting: [.completed, .failed, .cancelled],
            .completed: [.promoting, .released],
            .failed: [.finalizing, .idle, .cancelled, .released],
            .cancelled: [.released],
            .released: [],
        ]

        XCTAssertEqual(Set(legal.keys), Set(RecordingLifecycleState.allCases))

        for from in RecordingLifecycleState.allCases {
            for to in RecordingLifecycleState.allCases {
                let expected = legal[from]!.contains(to)
                XCTAssertEqual(
                    RecordingLifecycleState.isLegalTransition(from: from, to: to),
                    expected,
                    "transition \(from) -> \(to) must be \(expected ? "legal" : "illegal")"
                )
            }
        }
    }

    func testReleasedIsTerminalAndSameStateTransitionsAreRejected() {
        for state in RecordingLifecycleState.allCases {
            XCTAssertFalse(
                RecordingLifecycleState.isLegalTransition(from: state, to: state),
                "no-op transition \(state) must be rejected"
            )
            if state == .released {
                for to in RecordingLifecycleState.allCases where to != .released {
                    XCTAssertFalse(
                        RecordingLifecycleState.isLegalTransition(from: .released, to: to),
                        "released must be terminal, illegal edge to \(to)"
                    )
                }
            }
        }
    }

    func testRecorderStateMapsOntoCanonicalLifecycle() {
        let expected: [RecorderState: RecordingLifecycleState] = [
            .idle: .idle,
            .prepared: .ready,
            .recording: .recording,
            .finishing: .finalizing,
            .finished: .completed,
            .failed: .failed,
            .released: .released,
        ]
        for (recorderState, canonical) in expected {
            XCTAssertEqual(RecordingLifecycleState(recorderState), canonical)
        }
    }

    // MARK: - SerializedMediaRecorder behavior on the canonical machine

    func testSerializedRecorderRejectsStartFromIdleAndStopFromIdle() async {
        let recorder = makeRecorder()

        do {
            try await recorder.start()
            XCTFail("start from idle must throw")
        } catch let failure as RecorderFailure {
            XCTAssertEqual(failure, .invalidTransition)
        } catch {
            XCTFail("unexpected error \(error)")
        }

        let stopResult = await recorder.stop(reason: .user)
        XCTAssertEqual(stopResult, .failed(.invalidTransition, recoverableArtifact: nil))
    }

    func testSerializedRecorderHappyPathFollowsCanonicalSequence() async throws {
        let writer = LifecycleFakeWriter()
        let recorder = makeRecorder(writer: writer)

        var snapshot = await recorder.stateSnapshot()
        XCTAssertEqual(RecordingLifecycleState(snapshot.state), .idle)

        let configuration = try makeConfiguration()
        try await recorder.prepare(configuration)
        snapshot = await recorder.stateSnapshot()
        XCTAssertEqual(RecordingLifecycleState(snapshot.state), .ready)

        try await recorder.start()
        snapshot = await recorder.stateSnapshot()
        XCTAssertEqual(RecordingLifecycleState(snapshot.state), .recording)

        let fence = RecordingFrameFence(recordingID: configuration.id, generation: snapshot.generation)
        recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 0.5))
        recorder.enqueueVideo(RecordingVideoFrame(fence: fence, timestamp: 1.0))

        let stopResult = await recorder.stop(reason: .user)
        guard case .finalized(let artifact) = stopResult else {
            return XCTFail("expected finalized artifact, got \(stopResult)")
        }
        XCTAssertEqual(artifact.id, configuration.id)
        snapshot = await recorder.stateSnapshot()
        XCTAssertEqual(RecordingLifecycleState(snapshot.state), .completed)

        let releaseResult = await recorder.releaseAndWait()
        XCTAssertEqual(releaseResult, stopResult)
        snapshot = await recorder.stateSnapshot()
        XCTAssertEqual(RecordingLifecycleState(snapshot.state), .released)

        // Release is terminal; a repeated stop reports the cached result.
        let repeatedStop = await recorder.stop(reason: .routeExit)
        XCTAssertEqual(repeatedStop, stopResult)
        snapshot = await recorder.stateSnapshot()
        XCTAssertEqual(RecordingLifecycleState(snapshot.state), .released)
    }

    // MARK: - SceneRecordingController canonical projection

    func testControllerLifecycleProjectsCanonicalStatesAcrossOneTake() async throws {
        let applicationSupportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-lifecycle-store-\(UUID().uuidString)", isDirectory: true)
        let store = try RecordingArtifactStore(applicationSupportDirectoryURL: applicationSupportURL)
        defer { try? FileManager.default.removeItem(at: applicationSupportURL) }

        let writer = LifecycleFakeWriter()
        let controller = SceneRecordingController(
            artifactStore: store,
            makeRecorder: { configuration in
                SerializedMediaRecorder(
                    writerFactory: SingletonWriterFactory(writer: writer),
                    queueLabel: "recording-lifecycle-\(UUID().uuidString)"
                )
            }
        )

        XCTAssertEqual(controller.canonicalLifecycleState, .idle)

        let buffer = try makePixelBuffer()
        try await controller.start(
            firstPixelBuffer: buffer,
            requestedFPS: 30,
            audioMode: .disabled,
            timestamp: 0.5
        )
        XCTAssertEqual(controller.canonicalLifecycleState, .recording)

        controller.enqueueVideo(buffer, at: 1.5, ownerToken: controller.recordingSourceToken)

        let stopResult = await controller.stop(reason: .user)
        XCTAssertEqual(controller.canonicalLifecycleState, .idle)
        guard let stopResult, case .finalized = stopResult else {
            return XCTFail("expected finalized artifact, got \(String(describing: stopResult))")
        }

        _ = await controller.releaseAndWait()
        XCTAssertEqual(controller.canonicalLifecycleState, .released)
    }

    // MARK: - Helpers

    private func makeRecorder(writer: LifecycleFakeWriter = LifecycleFakeWriter()) -> SerializedMediaRecorder {
        SerializedMediaRecorder(
            writerFactory: SingletonWriterFactory(writer: writer),
            queueLabel: "recording-lifecycle-\(UUID().uuidString)"
        )
    }

    private func makeConfiguration() throws -> RecordingConfiguration {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-lifecycle-\(UUID().uuidString).mp4", isDirectory: false)
        return RecordingConfiguration(
            id: RecordingID(rawValue: UUID()),
            outputURL: url,
            width: 4,
            height: 4,
            fps: 30,
            audioMode: .disabled
        )
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            4,
            4,
            kCVPixelFormatType_32BGRA,
            nil,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw XCTSkip("CVPixelBufferCreate failed with \(status)")
        }
        return buffer
    }
}

/// One writer per test; every recorder created during the test shares it.
private final class SingletonWriterFactory: RecordingWriterFactory {
    let writer: LifecycleFakeWriter

    init(writer: LifecycleFakeWriter) {
        self.writer = writer
    }

    func makeWriter(for configuration: RecordingConfiguration) throws -> any RecordingWriter {
        writer
    }
}

/// Minimal deterministic writer: synchronous success path with controllable
/// append disposition, no AVFoundation dependency.
private final class LifecycleFakeWriter: RecordingWriter, @unchecked Sendable {
    private let lock = NSLock()
    private var videoAppendCount = 0
    var startResult = true
    var videoAppendDisposition: RecordingAppendDisposition = .appended

    func start() -> Bool {
        startResult
    }

    func appendVideo(_ frame: RecordingVideoFrame) -> RecordingAppendDisposition {
        lock.lock()
        videoAppendCount += 1
        lock.unlock()
        return videoAppendDisposition
    }

    func appendAudio(_ frame: RecordingAudioFrame) -> RecordingAppendDisposition {
        .dropped
    }

    func markVideoInputAsFinished() {}

    func markAudioInputAsFinished() {}

    func finishWriting(completion: @escaping (Result<RecordingWriterFinish, RecordingWriterError>) -> Void) {
        completion(.success(RecordingWriterFinish(duration: 1.0, hasAudio: false)))
    }

    func discard() {}
}
