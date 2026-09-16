import Foundation

/// Bounds retained payloads before dispatching to the writer queue. Rejected
/// frames leave only aggregate integers, so overload cannot enqueue another
/// closure for each drop. Writer state and finalization remain owned by
/// SerializedMediaRecorder's queue.
final class RecordingFrameAdmissionGate: @unchecked Sendable {
    enum Stream: Equatable { case video, audio }

    struct Statistics {
        var droppedVideo = 0
        var droppedAudio = 0
        var inactiveVideo = 0
        var inactiveAudio = 0
        var staleVideo = 0
        var staleAudio = 0
    }

    struct Occupancy: Sendable, Equatable {
        let video: Int
        let audio: Int
    }

    private let lock = NSLock()
    private let videoCapacity: Int
    private let audioCapacity: Int
    private var videoInFlight = 0
    private var audioInFlight = 0
    private var generation: UInt64 = 0
    private var preparedGeneration: UInt64?
    private var fence: RecordingFrameFence?
    private var audioEnabled = false
    private var statistics = Statistics()

    init(videoCapacity: Int = 4, audioCapacity: Int = 16) {
        self.videoCapacity = max(1, videoCapacity)
        self.audioCapacity = max(1, audioCapacity)
    }

    private func withState<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Capture before queueing prepare. A later synchronous stop/release
    /// increments this generation, so delayed prepare/start cannot reopen it.
    var preparationGeneration: UInt64 { withState { generation } }

    @discardableResult
    func prepare(expectedGeneration: UInt64) -> Bool {
        withState {
            guard generation == expectedGeneration else { return false }
            preparedGeneration = expectedGeneration
            fence = nil
            audioEnabled = false
            statistics = Statistics()
            return true
        }
    }

    func open(fence newFence: RecordingFrameFence, audioEnabled: Bool) -> Bool {
        withState {
            guard preparedGeneration == generation else { return false }
            fence = newFence
            self.audioEnabled = audioEnabled
            return true
        }
    }

    /// Does not discard already admitted work. The serial writer processes
    /// those bounded submissions before its queued stop/finalization command.
    func close() {
        withState {
            generation = generation == .max ? 1 : generation + 1
            preparedGeneration = nil
            fence = nil
        }
    }

    func reserveVideo(_ frame: RecordingVideoFrame, submit: () -> Void) -> Bool {
        reserve(.video, recordingID: frame.recordingID,
                generation: frame.generation, ownerToken: frame.ownerToken, submit: submit)
    }

    func reserveAudio(_ frame: RecordingAudioFrame, submit: () -> Void) -> Bool {
        reserve(.audio, recordingID: frame.recordingID,
                generation: frame.generation, ownerToken: frame.ownerToken, submit: submit)
    }

    private func reserve(_ stream: Stream,
                         recordingID: RecordingID,
                         generation: UInt64,
                         ownerToken: RecordingOwnerToken?, submit: () -> Void) -> Bool {
        withState {
            // Video-only recordings intentionally have no microphone stream.
            if stream == .audio && !audioEnabled { return false }
            guard let fence else {
                switch stream {
                case .video: increment(&statistics.inactiveVideo)
                case .audio: increment(&statistics.inactiveAudio)
                }
                return false
            }
            guard recordingID == fence.recordingID, generation == fence.generation,
                  ownerToken == fence.ownerToken else {
                switch stream {
                case .video: increment(&statistics.staleVideo)
                case .audio: increment(&statistics.staleAudio)
                }
                return false
            }
            switch stream {
            case .video:
                guard videoInFlight < videoCapacity else {
                    increment(&statistics.droppedVideo)
                    return false
                }
                videoInFlight += 1
            case .audio:
                guard audioInFlight < audioCapacity else {
                    increment(&statistics.droppedAudio)
                    return false
                }
                audioInFlight += 1
            }
            // Enqueue under the same lock as admission. Stop cannot close the
            // fence and enqueue finalization between reservation and dispatch.
            // This callback only submits asynchronously; it must never block.
            submit()
            return true
        }
    }

    func release(_ stream: Stream) {
        withState {
            switch stream {
            case .video:
                assert(videoInFlight > 0)
                videoInFlight = max(0, videoInFlight - 1)
            case .audio:
                assert(audioInFlight > 0)
                audioInFlight = max(0, audioInFlight - 1)
            }
        }
    }

    func drainStatistics() -> Statistics {
        withState {
            let snapshot = statistics
            statistics = Statistics()
            return snapshot
        }
    }

    var occupancy: Occupancy {
        withState { Occupancy(video: videoInFlight, audio: audioInFlight) }
    }

#if DEBUG
    var isOpenForTesting: Bool { withState { fence != nil } }
#endif

    private func increment(_ value: inout Int) {
        if value < .max { value += 1 }
    }
}
