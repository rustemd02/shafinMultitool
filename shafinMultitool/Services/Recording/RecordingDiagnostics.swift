import Foundation

/// M7-030: one bounded, versioned, redacted recording diagnostics event.
/// Only typed enumerations, counters, durations and identifiers are stored —
/// never frame pixels, audio samples, screenplay text, file paths, or any
/// other user content.
struct RecordingDiagnosticsEvent: Codable, Equatable, Sendable {
    /// Schema version for exported bundles.
    static let schemaVersion = 1

    enum Kind: Codable, Equatable, Sendable {
        /// Recorder lifecycle change; values are canonical state names.
        case stateChanged(from: String, to: String)
        /// A take reached a terminal stop result (finalized or failure kind).
        case stopCompleted(outcome: String, failure: String?)
        /// Sample admission summary (per-take counters from the timebase).
        case admission(acceptedVideo: Int, acceptedAudio: Int,
                       rejectedInactive: Int, rejectedStaleSource: Int,
                       rejectedTimelineFaults: Int)
        /// Writer backpressure summary.
        case backpressure(droppedVideo: Int, droppedAudio: Int)
        /// The sustained-drop policy fired.
        case dropPolicyFired
        /// Disk budget verdict at preflight (bytes, redacted to magnitudes).
        case diskBudget(requiredBytes: Int64, availableBytes: Int64, satisfied: Bool)
        /// ENOSPC-class failure observed.
        case storagePressure
        /// A/V sync measurement outcome.
        case sync(startDeltaSeconds: Double?, endDeltaSeconds: Double?,
                  withinReleaseCriterion: Bool)
        /// Recovery classified a journal record at cold launch.
        case recovery(outcome: String, recordingID: UUID?)
        /// Device thermal posture observed at a recording boundary (M7-030).
        /// Values: nominal / fair / serious / critical.
        case thermal(state: String)
    }

    let schemaVersion: Int
    let timestamp: Date
    /// Recording identity only; no paths or content.
    let recordingID: UUID?
    let kind: Kind
}

/// M7-030: the bounded local recording diagnostics owner. The buffer is a
/// fixed-size ring (oldest events evicted first); emission is thread-safe and
/// never blocking for the caller's critical path. Export is explicit and
/// returns only the redacted typed events.
final class RecordingDiagnosticsLog: @unchecked Sendable {
    static let shared = RecordingDiagnosticsLog()

    private let lock = NSLock()
    private var events: [RecordingDiagnosticsEvent] = []
    private var capacity: Int
    private var sequenceCounter = 0

    init(capacity: Int = 200) {
        self.capacity = max(1, capacity)
    }

    func emit(_ kind: RecordingDiagnosticsEvent.Kind,
              recordingID: UUID? = nil,
              timestamp: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        sequenceCounter += 1
        events.append(RecordingDiagnosticsEvent(
            schemaVersion: RecordingDiagnosticsEvent.schemaVersion,
            timestamp: timestamp,
            recordingID: recordingID,
            kind: kind
        ))
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    /// Explicit export: the redacted typed events, oldest first.
    func exportedEvents() -> [RecordingDiagnosticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }

    var emittedEventCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    func removeAllForTesting() {
        lock.lock()
        defer { lock.unlock() }
        events.removeAll()
        sequenceCounter = 0
    }
}

/// Emission seam for recording owners; production binds the shared log and
/// tests bind an isolated instance.
protocol RecordingDiagnosticsEmitting: Sendable {
    func emit(_ kind: RecordingDiagnosticsEvent.Kind, recordingID: UUID?)
}

extension RecordingDiagnosticsLog: RecordingDiagnosticsEmitting {
    func emit(_ kind: RecordingDiagnosticsEvent.Kind, recordingID: UUID?) {
        emit(kind, recordingID: recordingID, timestamp: Date())
    }
}
