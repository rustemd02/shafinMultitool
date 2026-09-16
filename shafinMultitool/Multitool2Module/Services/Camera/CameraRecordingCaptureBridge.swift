import CoreMedia
import CoreVideo
import Foundation

enum CameraRecordingCapturePolicy {
    static func fixedFramesPerSecond(_ value: Double?) -> Int? {
        guard let value, value.isFinite, value >= 1, value <= 240,
              abs(value.rounded() - value) < 0.001 else { return nil }
        return Int(value.rounded())
    }

    /// An existing confirmed mode is kept. A variable/default mode is fixed
    /// using a real device option at the same dimensions, preferring its
    /// current cadence and then 30 FPS. Resolution is never guessed or scaled.
    static func formatToApply(_ snapshot: CameraProControlsSnapshot) throws -> CameraProFormatOption? {
        let readback = snapshot.readback
        guard readback.width > 0, readback.height > 0 else {
            throw CameraRecordingCaptureError.formatUnavailable
        }
        let options = snapshot.capabilities.formats.filter {
            $0.width == readback.width && $0.height == readback.height
                && fixedFramesPerSecond($0.fps) != nil
        }
        if let fps = fixedFramesPerSecond(readback.fixedFPS), let id = readback.formatID,
           options.contains(where: { $0.id == id && abs($0.fps - Double(fps)) < 0.001 }) {
            return nil
        }
        let preferredFPS = fixedFramesPerSecond(readback.fixedFPS) ?? 30
        guard let selected = options.sorted(by: {
            let first = abs($0.fps - Double(preferredFPS))
            let second = abs($1.fps - Double(preferredFPS))
            if first != second { return first < second }
            return $0.id < $1.id
        }).first else { throw CameraRecordingCaptureError.formatUnavailable }
        return selected
    }
}

/// A take-scoped handoff from CameraManager's existing output queues. This
/// object never configures or starts a capture session, writer or audio session.
/// CameraManager reserves the graph on sessionQueue; this lock protects only
/// the immutable take identity and callback admission shared by its outputs.
final class CameraRecordingCaptureBridge: @unchecked Sendable {
    struct Context: Sendable {
        let lease: CameraRecordingCaptureLease
        let sessionGeneration: UInt64
        let deviceID: String
        let formatID: String
        let width: Int
        let height: Int
        let fps: Int
        let pixelFormat: OSType
        let minimumHostTimestamp: TimeInterval
        let trackTransform: RecordingTrackTransformMetadata
        let audioEnabled: Bool
    }

    private let lock = NSLock()
    private var reservation: (lease: CameraRecordingCaptureLease, sessionGeneration: UInt64)?
    private var reservationClosed = false
    private var context: Context?
    private var admissionOpen = false
    private var prepared = false
    private weak var controller: SceneRecordingController?
    private var firstFrameWaiter: CheckedContinuation<PreparedCameraRecordingCapture, Error>?
    private var audioDriverID: UUID?
    private var audioHandler: RecordingAudioFrameHandler?

    private func withState<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    var isReserved: Bool { withState { reservation != nil } }

#if DEBUG
    var hasPendingFirstFrameForTesting: Bool { withState { firstFrameWaiter != nil } }
#endif

    func owns(_ lease: CameraRecordingCaptureLease) -> Bool {
        withState { reservation?.lease == lease }
    }

    func reserve(ownerID: UUID, sessionGeneration: UInt64) throws -> CameraRecordingCaptureLease {
        try withState {
            guard reservation == nil else { throw CameraRecordingCaptureError.recordingInProgress }
            let lease = CameraRecordingCaptureLease(id: UUID(), ownerID: ownerID)
            reservation = (lease, sessionGeneration)
            reservationClosed = false
            return lease
        }
    }

    func validates(_ lease: CameraRecordingCaptureLease, sessionGeneration: UInt64) -> Bool {
        withState {
            !reservationClosed && reservation?.lease == lease
                && reservation?.sessionGeneration == sessionGeneration
        }
    }

    func waitForFirstFrame(context newContext: Context, timeout: TimeInterval = 3) async throws
        -> PreparedCameraRecordingCapture {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let error: CameraRecordingCaptureError? = withState {
                    guard !reservationClosed, reservation?.lease == newContext.lease,
                          reservation?.sessionGeneration == newContext.sessionGeneration else {
                        return .staleLease
                    }
                    guard context == nil, firstFrameWaiter == nil else { return .recordingInProgress }
                    context = newContext
                    admissionOpen = true
                    firstFrameWaiter = continuation
                    return nil
                }
                if let error { continuation.resume(throwing: error); return }
                if Task.isCancelled {
                    closeAdmission(newContext.lease, error: .staleLease)
                    return
                }
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + max(0.05, timeout)) { [weak self] in
                    self?.failFirstFrame(newContext.lease)
                }
            }
        } onCancel: {
            self.closeAdmission(newContext.lease, error: .staleLease)
        }
    }

    private func failFirstFrame(_ lease: CameraRecordingCaptureLease) {
        let waiter = withState { () -> CheckedContinuation<PreparedCameraRecordingCapture, Error>? in
            guard reservation?.lease == lease, let waiter = firstFrameWaiter else { return nil }
            firstFrameWaiter = nil
            admissionOpen = false
            return waiter
        }
        waiter?.resume(throwing: CameraRecordingCaptureError.noFrames)
    }

    func attach(_ newController: SceneRecordingController, lease: CameraRecordingCaptureLease) throws {
        try withState {
            guard reservation?.lease == lease, admissionOpen, prepared,
                  newController.recordingSourceOwnerID == lease.ownerID else {
                throw CameraRecordingCaptureError.staleLease
            }
            guard controller == nil || controller === newController else {
                throw CameraRecordingCaptureError.recordingInProgress
            }
            controller = newController
        }
    }

    /// Returns sourceChanged only when an active take receives a different
    /// native buffer format. CameraManager sends that through its existing
    /// interruption owner, which finalizes already admitted media once.
    func forwardVideo(_ pixelBuffer: CVPixelBuffer,
                      hostTimestamp: TimeInterval,
                      sessionGeneration: UInt64) -> CameraRecordingCaptureError? {
        guard hostTimestamp.isFinite else { return nil }
        var completion: (CheckedContinuation<PreparedCameraRecordingCapture, Error>, PreparedCameraRecordingCapture)?
        var destination: SceneRecordingController?
        var owner: UUID?
        var failedWaiter: CheckedContinuation<PreparedCameraRecordingCapture, Error>?
        let error: CameraRecordingCaptureError? = withState {
            guard admissionOpen, let context,
                  reservation?.lease == context.lease,
                  context.sessionGeneration == sessionGeneration else { return nil }
            guard hostTimestamp >= context.minimumHostTimestamp else { return nil }
            guard CVPixelBufferGetWidth(pixelBuffer) == context.width,
                  CVPixelBufferGetHeight(pixelBuffer) == context.height,
                  CVPixelBufferGetPixelFormatType(pixelBuffer) == context.pixelFormat else {
                failedWaiter = firstFrameWaiter
                firstFrameWaiter = nil
                admissionOpen = false
                audioHandler = nil
                return .sourceChanged
            }
            if let waiter = firstFrameWaiter {
                firstFrameWaiter = nil
                prepared = true
                completion = (waiter, PreparedCameraRecordingCapture(
                    lease: context.lease, pixelBuffer: pixelBuffer, timestamp: hostTimestamp,
                    fps: context.fps, trackTransform: context.trackTransform,
                    audioDriverFactory: context.audioEnabled
                        ? CameraSharedCaptureAudioDriverFactory(bridge: self, lease: context.lease) : nil
                ))
            }
            destination = controller
            owner = context.lease.ownerID
            return nil
        }
        failedWaiter?.resume(throwing: CameraRecordingCaptureError.sourceChanged)
        if let (waiter, capture) = completion { waiter.resume(returning: capture) }
        if let destination, let owner,
           let token = destination.recordingSourceToken,
           token.source == .cameraCoach, token.ownerID == owner {
            destination.enqueueVideo(pixelBuffer, at: hostTimestamp, ownerID: owner, ownerToken: token)
        }
        return error
    }

    func startAudio(lease: CameraRecordingCaptureLease, driverID: UUID,
                    handler: @escaping RecordingAudioFrameHandler) -> Bool {
        withState {
            guard reservation?.lease == lease, admissionOpen, prepared,
                  context?.audioEnabled == true,
                  audioDriverID == nil || audioDriverID == driverID else { return false }
            audioDriverID = driverID
            audioHandler = handler
            return true
        }
    }

    func stopAudio(lease: CameraRecordingCaptureLease, driverID: UUID) {
        withState {
            guard reservation?.lease == lease, audioDriverID == driverID else { return }
            audioDriverID = nil
            audioHandler = nil
        }
    }

    func forwardAudio(_ sampleBuffer: CMSampleBuffer,
                      synchronizationClock: CMClockOrTimebase?,
                      sessionGeneration: UInt64) {
        let handler: RecordingAudioFrameHandler? = withState {
            guard admissionOpen, let context,
                  context.sessionGeneration == sessionGeneration,
                  context.audioEnabled else { return nil }
            return audioHandler
        }
        guard let handler,
              let copy = copyAudioSampleBufferToHostTime(sampleBuffer, synchronizationClock: synchronizationClock) else {
            return
        }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(copy).seconds
        guard timestamp.isFinite else { return }
        handler(timestamp, AppleRecordingAudioFramePayload(sampleBuffer: copy))
    }

    /// Caller drains both CameraManager output queues after closing this
    /// boundary, before it asks the controller to stop its writer.
    func closeAdmission(_ lease: CameraRecordingCaptureLease? = nil,
                        error: CameraRecordingCaptureError = .staleLease) {
        let waiter = withState { () -> CheckedContinuation<PreparedCameraRecordingCapture, Error>? in
            if let lease, reservation?.lease != lease { return nil }
            reservationClosed = true
            admissionOpen = false
            controller = nil
            audioHandler = nil
            audioDriverID = nil
            let waiter = firstFrameWaiter
            firstFrameWaiter = nil
            return waiter
        }
        waiter?.resume(throwing: error)
    }

    func release(_ lease: CameraRecordingCaptureLease) {
        closeAdmission(lease)
        withState {
            guard reservation?.lease == lease else { return }
            reservation = nil
            reservationClosed = false
            context = nil
            prepared = false
        }
    }
}

private struct CameraSharedCaptureAudioDriverFactory: RecordingAudioDriverFactory {
    let bridge: CameraRecordingCaptureBridge
    let lease: CameraRecordingCaptureLease

    func makeAudioDriver(for configuration: RecordingConfiguration) throws -> any RecordingAudioDriver {
        guard configuration.audioMode == .required else { throw RecorderFailure.audioSessionUnavailable }
        return CameraSharedCaptureAudioDriver(bridge: bridge, lease: lease)
    }
}

private final class CameraSharedCaptureAudioDriver: RecordingAudioDriver {
    private let bridge: CameraRecordingCaptureBridge
    private let lease: CameraRecordingCaptureLease
    private let id = UUID()

    init(bridge: CameraRecordingCaptureBridge, lease: CameraRecordingCaptureLease) {
        self.bridge = bridge
        self.lease = lease
    }

    func start(onFrame: @escaping RecordingAudioFrameHandler) -> Bool {
        bridge.startAudio(lease: lease, driverID: id, handler: onFrame)
    }

    func stop() { bridge.stopAudio(lease: lease, driverID: id) }
}
