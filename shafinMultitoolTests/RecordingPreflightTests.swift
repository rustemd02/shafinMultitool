import XCTest
@testable import shafinMultitool

/// M7-008: one failure fixture per mandatory start precondition, plus the
/// passing baseline. The production preflight owner is exercised directly —
/// not a mock of the final result.
final class RecordingPreflightTests: XCTestCase {
    private struct SelectedCodecSupportChecker: RecordingCodecSupportChecking {
        let supported: Set<RecordingQuickTimeCodec>

        func isSupported(_ codec: RecordingQuickTimeCodec) -> Bool {
            supported.contains(codec)
        }
    }

    private final class StaticMicrophoneChecker: RecordingMicrophonePermissionChecking, @unchecked Sendable {
        let available: Bool

        init(available: Bool) {
            self.available = available
        }

        func microphoneAvailable() async -> Bool { available }
    }

    private final class StaticAudioSessionChecker: RecordingAudioSessionChecking, @unchecked Sendable {
        let available: Bool

        init(available: Bool) {
            self.available = available
        }

        func audioSessionAvailable() async -> Bool { available }
    }

    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingPreflightTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL,
                                                withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        try super.tearDownWithError()
    }

    private func makeContext(audioMode: RecordingAudioMode = .disabled) -> RecordingStartPreflightContext {
        RecordingStartPreflightContext(
            width: 640,
            height: 480,
            fps: 30,
            codec: .h264,
            pixelFormatFourCC: RecordingPixelFormat.yPlanar420VideoRange,
            audioMode: audioMode
        )
    }

    private func makePreflight(
        supported: Set<RecordingQuickTimeCodec> = [.h264, .hevc],
        microphoneAvailable: Bool = true,
        audioSessionAvailable: Bool = true,
        diskBudget: (@Sendable (RecordingStartPreflightContext) throws -> RecordingDiskBudgetEstimate)? = nil
    ) -> StandardRecordingStartPreflight {
        StandardRecordingStartPreflight(
            codecSupport: SelectedCodecSupportChecker(supported: supported),
            microphonePermission: StaticMicrophoneChecker(available: microphoneAvailable),
            audioSession: StaticAudioSessionChecker(available: audioSessionAvailable),
            diskBudget: diskBudget
        )
    }

    func testInvalidDimensionsFailBeforeRecording() async {
        let context = RecordingStartPreflightContext(
            width: 0,
            height: 480,
            fps: 30,
            codec: .h264,
            pixelFormatFourCC: nil,
            audioMode: .disabled
        )
        let verdict = await makePreflight().validate(context)
        XCTAssertEqual(verdict, .writerInputRejected)
    }

    func testUnsupportedCodecFailsBeforeRecording() async {
        let hevcContext = RecordingStartPreflightContext(
            width: 640,
            height: 480,
            fps: 30,
            codec: .hevc,
            pixelFormatFourCC: nil,
            audioMode: .disabled
        )
        let verdict = await makePreflight(supported: [.h264]).validate(hevcContext)
        XCTAssertEqual(verdict, .writerInputRejected)
    }

    func testExplicitZeroPixelFormatFailsBeforeRecording() async {
        let context = RecordingStartPreflightContext(
            width: 640,
            height: 480,
            fps: 30,
            codec: .h264,
            pixelFormatFourCC: 0,
            audioMode: .disabled
        )
        let verdict = await makePreflight().validate(context)
        XCTAssertEqual(verdict, .writerInputRejected)
    }

    func testDiskBudgetBelowRequirementFailsBeforeRecording() async {
        let verdict = await makePreflight(diskBudget: { context in
            RecordingDiskBudgetEstimate(
                requiredFreeBytes: 1_000_000_000,
                availableBytes: 500_000_000
            )
        }).validate(makeContext())
        XCTAssertEqual(verdict, .insufficientStorage)
    }

    func testDiskBudgetQueryFailureFailsClosed() async {
        let verdict = await makePreflight(diskBudget: { _ in
            throw RecordingArtifactStoreError.fileSystemFailure
        }).validate(makeContext())
        XCTAssertEqual(verdict, .insufficientStorage)
    }

    func testDeniedMicrophoneFailsSoundRequiredTake() async {
        let verdict = await makePreflight(microphoneAvailable: false)
            .validate(makeContext(audioMode: .required))
        XCTAssertEqual(verdict, .microphoneDenied)
    }

    func testUnavailableAudioSessionFailsSoundRequiredTake() async {
        let verdict = await makePreflight(audioSessionAvailable: false)
            .validate(makeContext(audioMode: .required))
        XCTAssertEqual(verdict, .audioSessionUnavailable)
    }

    func testSatisfiedPreconditionsAllowStart() async {
        let verdict = await makePreflight(diskBudget: { context in
            RecordingDiskBudgetEstimate(
                requiredFreeBytes: 1_000,
                availableBytes: 1_000_000
            )
        }).validate(makeContext(audioMode: .required))
        XCTAssertNil(verdict)
    }

    /// The default controller preflight (unit seam) is availability-neutral:
    /// a sound-required start in a unit fixture never depends on the host's
    /// real privacy state.
    func testDefaultControllerPreflightIsAvailabilityNeutral() async {
        let preflight = StandardRecordingStartPreflight(
            microphonePermission: AlwaysAvailableMicrophonePermissionChecker(),
            audioSession: AlwaysAvailableAudioSessionChecker()
        )
        let verdict = await preflight.validate(makeContext(audioMode: .required))
        XCTAssertNil(verdict)
    }

    /// The production session checker answers available for the shared
    /// coordinator's non-interrupted state.
    func testCoordinatorAudioSessionCheckerAnswersAvailableWhenInactive() async {
        let checker = CoordinatorAudioSessionChecker()
        let available = await checker.audioSessionAvailable()
        XCTAssertTrue(available)
    }

    /// M7-007: the production orientation derivation always produces valid
    /// metadata for any device posture (flat/unknown falls back to portrait).
    @MainActor
    func testCurrentRecordingTrackTransformIsAlwaysValid() {
        let transform = SceneGeneratorViewModel.currentRecordingTrackTransform()
        XCTAssertTrue(RecordingCaptureOrientation.allCases.contains(transform.captureOrientation))
        XCTAssertFalse(transform.isMirrored)
        XCTAssertEqual(transform.strategy, .preferredTransformMetadata)
    }

    /// M7-017: the budget model is a documented deterministic function.
    func testDiskBudgetModelIsConservativeAndMonotonic() {
        let base = RecordingDiskBudgetModel.requiredFreeBytes(
            width: 1920, height: 1080, fps: 30,
            codec: .h264, audioMode: .required,
            durationLimitSeconds: 600
        )
        // 1920*1080*30*0.12 bps = 7.46 Mbps video + 128 kbps audio, doubled,
        // plus the fixed floor.
        XCTAssertGreaterThan(base, 1_000_000_000)
        let hevc = RecordingDiskBudgetModel.requiredFreeBytes(
            width: 1920, height: 1080, fps: 30,
            codec: .hevc, audioMode: .required,
            durationLimitSeconds: 600
        )
        XCTAssertLessThan(hevc, base)
        let halfDuration = RecordingDiskBudgetModel.requiredFreeBytes(
            width: 1920, height: 1080, fps: 30,
            codec: .h264, audioMode: .required,
            durationLimitSeconds: 300
        )
        XCTAssertLessThan(halfDuration, base)
    }

    /// M7-017: a real store against the real volume answers with a satisfied
    /// estimate in the test environment (multi-GB free).
    func testArtifactStoreDiskBudgetEstimateAnswersOnRealVolume() throws {
        let store = try RecordingArtifactStore(
            applicationSupportDirectoryURL: temporaryDirectoryURL
        )
        let estimate = try store.diskBudgetEstimate(
            width: 640, height: 480, fps: 30,
            codec: .h264, audioMode: .disabled
        )
        XCTAssertGreaterThan(estimate.requiredFreeBytes, 0)
        XCTAssertGreaterThan(estimate.availableBytes, 0)
        XCTAssertTrue(estimate.isSatisfied)
    }
}
