//
//  RecordingHintIsolationTests.swift
//  shafinMultitoolTests
//
//  S05 recorder-side companion to the C07 VoiceOver-channel check: the camera
//  hint channel is presentation/analysis only. Toggling hints, running a live
//  hint frame through the analysis entry point, and entering/leaving the hint
//  pause review must not change the recording projection nor the explicit
//  sound policy that decides whether a take records audio.
//
//  The recorder-side audio gate itself is covered by
//  `SerializedMediaRecorderTests.testDisabledAudioNeverCreatesDriver`,
//  `SerializedMediaRecorderTests.testAppendedAudioCannotOverrideWriterMetadataFalse`,
//  and
//  `SceneRecordingControllerTests.testSoundOffSkipsMicrophoneAndAudioSessionAndUsesDisabledContract`.
//

import XCTest
import CoreVideo
import simd
import UIKit
@testable import shafinMultitool

@MainActor
final class RecordingHintIsolationTests: XCTestCase {
    /// The complete observable recording projection a hint action could
    /// plausibly disturb. Equality is asserted before/after the hint activity.
    @MainActor
    private struct RecordingProjection: Equatable {
        let isRecording: Bool
        let isRecordingStarting: Bool
        let isRecordingFinalizing: Bool
        let soundEnabled: Bool

        init(_ viewModel: SceneGeneratorViewModel) {
            self.isRecording = viewModel.isRecording
            self.isRecordingStarting = viewModel.isRecordingStarting
            self.isRecordingFinalizing = viewModel.isRecordingFinalizing
            self.soundEnabled = viewModel.recordingSoundEnabled
        }
    }

    func testHintLifecycleAndLiveFrameLeaveRecordingStateAndSoundPolicyUntouched() async throws {
        let viewModel = SceneGeneratorViewModel()
        let baseline = RecordingProjection(viewModel)
        XCTAssertFalse(baseline.isRecording)
        XCTAssertFalse(baseline.isRecordingStarting)
        XCTAssertFalse(baseline.isRecordingFinalizing)
        XCTAssertTrue(baseline.soundEnabled)

        viewModel.toggleHintsEnabled()
        XCTAssertTrue(viewModel.isHintsEnabled)

        // Feed the same live-frame seam the AR coordinator uses while hints are
        // enabled and drain the analysis the hint pipeline scheduled.
        viewModel.processARFrameSnapshot(
            cameraTransform: matrix_identity_float4x4,
            planeSnapshots: [ScenePlaneSnapshot(alignment: .horizontal, y: -1.0)],
            timestamp: 1.0,
            capturedImage: try makePixelBuffer(),
            interfaceOrientation: .portrait,
            displayTransform: .identity
        )
        await viewModel.testingDrainHintAnalysis()

        // Enter and leave the hint pause review on the accepted frame.
        viewModel.startHintPauseAnalysis()
        viewModel.resumeHintLiveAnalysis()

        viewModel.toggleHintsEnabled()
        XCTAssertFalse(viewModel.isHintsEnabled)

        XCTAssertEqual(RecordingProjection(viewModel), baseline)
    }

    private func makePixelBuffer() throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: 64,
            kCVPixelBufferHeightKey as String: 48,
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            64,
            48,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &pixelBuffer
        )
        XCTAssertEqual(status, kCVReturnSuccess)
        return try XCTUnwrap(pixelBuffer)
    }
}
