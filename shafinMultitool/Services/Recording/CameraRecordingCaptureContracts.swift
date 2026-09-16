import CoreVideo
import Foundation

struct CameraRecordingCaptureLease: Hashable, Sendable {
    let id: UUID
    let ownerID: UUID
}

enum CameraRecordingCaptureError: Error, Sendable, Equatable {
    case cameraUnavailable
    case recordingInProgress
    case formatUnavailable
    case microphoneDenied
    case audioUnavailable
    case staleLease
    case noFrames
    case sourceChanged
    case proControlPending
}

struct PreparedCameraRecordingCapture: @unchecked Sendable {
    let lease: CameraRecordingCaptureLease
    let pixelBuffer: CVPixelBuffer
    /// Capture producer's host-clock seconds; never wall-clock time.
    let timestamp: TimeInterval
    let fps: Int
    let trackTransform: RecordingTrackTransformMetadata
    let audioDriverFactory: (any RecordingAudioDriverFactory)?
}

protocol CameraRecordingCaptureSource: AnyObject, Sendable {
    var sourceOwnerID: UUID { get }
    func reserveRecordingCapture() async throws -> CameraRecordingCaptureLease
    func prepareRecordingCapture(
        lease: CameraRecordingCaptureLease,
        audioMode: RecordingAudioMode
    ) async throws -> PreparedCameraRecordingCapture
    func attachRecordingController(
        _ controller: SceneRecordingController,
        lease: CameraRecordingCaptureLease
    ) async throws
    func closeRecordingFrameAdmission(_ lease: CameraRecordingCaptureLease) async
    func releaseRecordingCapture(_ lease: CameraRecordingCaptureLease) async
    func setRecordingAudioMeterEnabled(_ enabled: Bool) async throws
}
