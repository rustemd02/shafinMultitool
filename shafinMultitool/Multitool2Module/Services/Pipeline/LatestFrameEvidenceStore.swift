import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import Foundation
import ImageIO

internal final class LatestFrameEvidenceStore: @unchecked Sendable {
    internal struct Snapshot: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        let orientation: CGImagePropertyOrientation
        let sourceFrameId: String
        let capturedAt: Date
        let isStable: Bool
        /// The capture-side lens identity that produced this exact buffer.
        /// Nil is retained as unknown provenance and must fail closed for
        /// subject-bound verification.
        let lensID: String?
        /// Actual preview destination geometry captured with this frame's
        /// orientation. Mismatched geometry is discarded at this immutable
        /// boundary rather than becoming an identity transform.
        let previewGeometry: CameraPreviewGeometry?
        /// The feature/adapter values produced for this exact source frame.
        /// This is optional for legacy synthetic publishers, but production
        /// high-priority capture publishes it atomically with the pixels.
        let adapterState: PipelineFeatureSnapshotAdapterState?
        /// M2-005: capture-side lens/session generation that produced this
        /// frame. 0 means unknown (legacy/synthetic publishers); production
        /// high-priority capture supplies CameraManager's capture generation.
        let lensGeneration: UInt64
        /// Exact presentation timestamp copied from the CMSampleBuffer. This
        /// is the ordering source within one camera capture epoch; it is not
        /// the callback arrival `capturedAt` wall-clock value.
        let samplePresentationTimestamp: CMTime
        /// CameraManager lifecycle/session epoch for this sample. `nil` is
        /// retained only for legacy synthetic publishers; `.some(0)` is a
        /// valid first camera session.
        let sessionGeneration: UInt64?

        init?(pixelBuffer: CVPixelBuffer,
              orientation: CGImagePropertyOrientation,
              sourceFrameId: String,
              capturedAt: Date,
              isStable: Bool,
              lensID: String? = nil,
              previewGeometry: CameraPreviewGeometry? = nil,
              adapterState: PipelineFeatureSnapshotAdapterState? = nil,
              lensGeneration: UInt64 = 0,
              samplePresentationTimestamp: CMTime = .invalid,
              sessionGeneration: UInt64? = nil) {
            let trimmedSourceFrameId = sourceFrameId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSourceFrameId.isEmpty else { return nil }
            // A known CameraManager session is a production provenance claim;
            // do not admit it without both the capture epoch and numeric PTS.
            guard sessionGeneration == nil
                || (lensGeneration != 0 && samplePresentationTimestamp.isNumeric) else {
                return nil
            }

            self.pixelBuffer = pixelBuffer
            self.orientation = orientation
            self.sourceFrameId = trimmedSourceFrameId
            self.capturedAt = capturedAt
            self.isStable = isStable
            let trimmedLensID = lensID?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.lensID = trimmedLensID?.isEmpty == false ? trimmedLensID : nil
            self.previewGeometry = previewGeometry?.imageOrientation == orientation
                ? previewGeometry
                : nil
            self.adapterState = adapterState?.sanitizedForFrame(
                frameID: trimmedSourceFrameId,
                captureGeneration: lensGeneration,
                orientation: orientation,
                samplePresentationTimestamp: samplePresentationTimestamp,
                sessionGeneration: sessionGeneration
            )
            self.lensGeneration = lensGeneration
            self.samplePresentationTimestamp = samplePresentationTimestamp
            self.sessionGeneration = sessionGeneration
        }

        /// M2-005: per-source feature measurement timestamps for this frame,
        /// extracted from the adapter state. A missing entry means the source
        /// produced no value for this frame and is unavailable (fail closed).
        var featureSourceTimestamps: [FeatureSourceID: Date] {
            var timestamps: [FeatureSourceID: Date] = [:]
            if let measuredAt = adapterState?.vision?.measuredAt {
                timestamps[.vision] = measuredAt
            }
            if let measuredAt = adapterState?.horizonMeasuredAt {
                timestamps[.horizon] = measuredAt
            }
            if let measuredAt = adapterState?.lightingMeasuredAt {
                timestamps[.lighting] = measuredAt
            }
            if let measuredAt = adapterState?.detr?.measuredAt {
                timestamps[.detr] = measuredAt
            }
            if let measuredAt = adapterState?.aestheticMeasuredAt {
                timestamps[.aesthetic] = measuredAt
            }
            return timestamps
        }

        /// Builds the immutable analysis envelope for this frame.
        func makeEnvelope() -> AcceptedFrameEnvelope {
            AcceptedFrameEnvelope(
                frameID: sourceFrameId,
                capturedAt: capturedAt,
                orientation: orientation,
                lensID: lensID,
                previewGeometry: previewGeometry,
                lensGeneration: lensGeneration,
                pixelBuffer: pixelBuffer,
                featureSourceTimestamps: featureSourceTimestamps,
                samplePresentationTimestamp: samplePresentationTimestamp,
                sessionGeneration: sessionGeneration
            )
        }
    }

    /// An immutable pause input. `evidence` is the exact frame envelope that
    /// the pipeline must analyse; `displayImage` is a rendered copy captured
    /// after the envelope is accepted, before or during camera stop. The pixel
    /// buffer is copied synchronously at acceptance; the expensive Core Image
    /// display render is deliberately filled by an off-main owner afterward.
    /// Keeping both values together prevents the review marker and critique
    /// from drifting onto a later live frame.
    internal struct AcceptedSnapshot: @unchecked Sendable {
        let snapshotID: String
        let evidence: Snapshot
        let displayImage: CGImage?

        var adapterState: PipelineFeatureSnapshotAdapterState? { evidence.adapterState }

        var sourceFrameId: String { evidence.sourceFrameId }
        var orientation: CGImagePropertyOrientation { evidence.orientation }
        var capturedAt: Date { evidence.capturedAt }
        var isStable: Bool { evidence.isStable }
        var pixelBuffer: CVPixelBuffer { evidence.pixelBuffer }
        var sourcePixelSize: CGSize {
            CGSize(
                width: CVPixelBufferGetWidth(evidence.pixelBuffer),
                height: CVPixelBufferGetHeight(evidence.pixelBuffer)
            )
        }

        var samplePresentationTimestamp: CMTime { evidence.samplePresentationTimestamp }
        var sessionGeneration: UInt64? { evidence.sessionGeneration }

        func withDisplayImage(_ image: CGImage) -> Self {
            Self(snapshotID: snapshotID, evidence: evidence, displayImage: image)
        }
    }

    private let lock = NSLock()
    private var currentSnapshot: Snapshot?
    private static let displayContext = CIContext(options: [.useSoftwareRenderer: true])

    @discardableResult
    internal func publish(pixelBuffer: CVPixelBuffer,
                          orientation: CGImagePropertyOrientation,
                          sourceFrameId: String,
                          capturedAt: Date,
                          isStable: Bool,
                          lensID: String? = nil,
                          previewGeometry: CameraPreviewGeometry? = nil,
                          adapterState: PipelineFeatureSnapshotAdapterState? = nil,
                          lensGeneration: UInt64 = 0,
                          samplePresentationTimestamp: CMTime = .invalid,
                          sessionGeneration: UInt64? = nil) -> Bool {
        guard let snapshot = Snapshot(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            sourceFrameId: sourceFrameId,
            capturedAt: capturedAt,
            isStable: isStable,
            lensID: lensID,
            previewGeometry: previewGeometry,
            adapterState: adapterState,
            lensGeneration: lensGeneration,
            samplePresentationTimestamp: samplePresentationTimestamp,
            sessionGeneration: sessionGeneration
        ) else {
            return false
        }

        lock.lock()
        if let currentSnapshot {
            guard Self.accepts(
                sessionGeneration: snapshot.sessionGeneration,
                captureGeneration: snapshot.lensGeneration,
                samplePresentationTimestamp: snapshot.samplePresentationTimestamp,
                capturedAt: snapshot.capturedAt,
                over: currentSnapshot
            ) else {
                lock.unlock()
                return false
            }
        }
        currentSnapshot = snapshot
        lock.unlock()
        return true
    }

    /// Atomically checks the same provenance ordering used by `publish`.
    /// Callers use this before expensive work; `publish` repeats the check
    /// under its lock so a concurrent newer sample cannot be overtaken.
    internal func accepts(sessionGeneration: UInt64?,
                          captureGeneration: UInt64,
                          samplePresentationTimestamp: CMTime,
                          capturedAt: Date = Date()) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let currentSnapshot else { return true }
        return Self.accepts(
            sessionGeneration: sessionGeneration,
            captureGeneration: captureGeneration,
            samplePresentationTimestamp: samplePresentationTimestamp,
            capturedAt: capturedAt,
            over: currentSnapshot
        )
    }

    private static func accepts(sessionGeneration incomingSessionGeneration: UInt64?,
                                captureGeneration incomingCaptureGeneration: UInt64,
                                samplePresentationTimestamp incomingTimestamp: CMTime,
                                capturedAt incomingCapturedAt: Date,
                                over current: Snapshot) -> Bool {
        // Preserve the existing Date fallback only for fully legacy values.
        // CameraManager captureOutput always supplies a known session and
        // numeric PTS, so callback arrival time can never make old pixels
        // appear newer on the production path.
        let legacyOrdering = incomingSessionGeneration == nil
            && current.sessionGeneration == nil
            && !incomingTimestamp.isNumeric
            && !current.samplePresentationTimestamp.isNumeric

        if let currentSessionGeneration = current.sessionGeneration {
            guard let incomingSessionGeneration else { return false }
            if incomingSessionGeneration != currentSessionGeneration {
                return incomingSessionGeneration > currentSessionGeneration
            }
        } else if incomingSessionGeneration != nil {
            // A known session is a new authoritative epoch over an unknown
            // legacy value; its sample order starts anew.
            return true
        }

        if current.lensGeneration != 0 {
            guard incomingCaptureGeneration != 0 else { return false }
            if incomingCaptureGeneration < current.lensGeneration { return false }
        }

        if incomingCaptureGeneration != current.lensGeneration {
            // A newer known capture epoch supersedes any older/unknown PTS.
            return incomingCaptureGeneration > current.lensGeneration
                || (current.lensGeneration == 0 && incomingCaptureGeneration != 0)
        }

        if current.samplePresentationTimestamp.isNumeric {
            guard incomingTimestamp.isNumeric else { return false }
            return CMTimeCompare(incomingTimestamp, current.samplePresentationTimestamp) >= 0
        }
        if incomingTimestamp.isNumeric {
            return true
        }

        guard legacyOrdering else { return false }
        return incomingCapturedAt >= current.capturedAt
    }

    internal func snapshot() -> Snapshot? {
        lock.lock()
        let snapshot = currentSnapshot
        lock.unlock()
        return snapshot
    }

    /// Atomically accepts the current evidence and copies the minimum immutable
    /// pixel input before returning. Callers use this once for a pause, before
    /// initiating asynchronous camera stop. Full display rendering is kept out
    /// of this critical path and is performed through `renderDisplayImage` by
    /// an off-main owner.
    internal func acceptCurrentSnapshot() -> AcceptedSnapshot? {
        lock.lock()
        guard let currentSnapshot,
              let copiedPixelBuffer = Self.copyPixelBuffer(currentSnapshot.pixelBuffer),
              let acceptedEvidence = Snapshot(
                  pixelBuffer: copiedPixelBuffer,
                  orientation: currentSnapshot.orientation,
                  sourceFrameId: currentSnapshot.sourceFrameId,
                  capturedAt: currentSnapshot.capturedAt,
                  isStable: currentSnapshot.isStable,
                  lensID: currentSnapshot.lensID,
                  previewGeometry: currentSnapshot.previewGeometry,
                  adapterState: currentSnapshot.adapterState,
                  lensGeneration: currentSnapshot.lensGeneration,
                  samplePresentationTimestamp: currentSnapshot.samplePresentationTimestamp,
                  sessionGeneration: currentSnapshot.sessionGeneration
              ) else {
            lock.unlock()
            return nil
        }
        lock.unlock()

        return AcceptedSnapshot(
            snapshotID: acceptedEvidence.sourceFrameId,
            evidence: acceptedEvidence,
            displayImage: nil
        )
    }

    /// Produces the display-ready image for an already accepted immutable
    /// buffer. This method has no store lock and can be called from a detached
    /// task, so Core Image never blocks the main pause action or capture
    /// publisher. Orientation is applied exactly once here.
    internal func renderDisplayImage(for accepted: AcceptedSnapshot) -> AcceptedSnapshot? {
        guard let displayImage = Self.makeDisplayImage(for: accepted.evidence) else {
            return nil
        }
        return accepted.withDisplayImage(displayImage)
    }

    internal func clear() {
        lock.lock()
        currentSnapshot = nil
        lock.unlock()
    }

    private static func makeDisplayImage(for snapshot: Snapshot) -> CGImage? {
        let image = CIImage(cvPixelBuffer: snapshot.pixelBuffer)
            .oriented(forExifOrientation: Int32(snapshot.orientation.rawValue))
        return displayContext.createCGImage(image, from: image.extent)
    }

    /// Capture buffers are owned and reused by AVCaptureVideoDataOutput. A
    /// retained buffer is therefore not an immutable pause input. Copy every
    /// plane while the store lock still protects the accepted envelope, then
    /// let the analysis and display paths share this copied buffer.
    private static func copyPixelBuffer(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        var destination: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            CVPixelBufferGetWidth(source),
            CVPixelBufferGetHeight(source),
            CVPixelBufferGetPixelFormatType(source),
            nil,
            &destination
        )
        guard status == kCVReturnSuccess, let destination else { return nil }

        let sourceLockStatus = CVPixelBufferLockBaseAddress(source, .readOnly)
        guard sourceLockStatus == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }

        let destinationLockStatus = CVPixelBufferLockBaseAddress(destination, [])
        guard destinationLockStatus == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }

        let planeCount = CVPixelBufferGetPlaneCount(source)
        if planeCount > 0 {
            for plane in 0..<planeCount {
                guard let sourceBase = CVPixelBufferGetBaseAddressOfPlane(source, plane),
                      let destinationBase = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else {
                    return nil
                }

                let rowCount = min(
                    CVPixelBufferGetHeightOfPlane(source, plane),
                    CVPixelBufferGetHeightOfPlane(destination, plane)
                )
                let byteCount = min(
                    CVPixelBufferGetBytesPerRowOfPlane(source, plane),
                    CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
                )
                for row in 0..<rowCount {
                    memcpy(
                        destinationBase.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(destination, plane)),
                        sourceBase.advanced(by: row * CVPixelBufferGetBytesPerRowOfPlane(source, plane)),
                        byteCount
                    )
                }
            }
        } else {
            guard let sourceBase = CVPixelBufferGetBaseAddress(source),
                  let destinationBase = CVPixelBufferGetBaseAddress(destination) else {
                return nil
            }

            let rowCount = min(CVPixelBufferGetHeight(source), CVPixelBufferGetHeight(destination))
            let byteCount = min(CVPixelBufferGetBytesPerRow(source), CVPixelBufferGetBytesPerRow(destination))
            for row in 0..<rowCount {
                memcpy(
                    destinationBase.advanced(by: row * CVPixelBufferGetBytesPerRow(destination)),
                    sourceBase.advanced(by: row * CVPixelBufferGetBytesPerRow(source)),
                    byteCount
                )
            }
        }

        return destination
    }
}

// MARK: - M2-005 AcceptedFrameEnvelope (AnalysisPipelineOwner)

/// The five feature sources whose freshness the envelope governs.
enum FeatureSourceID: String, Codable, CaseIterable, Sendable {
    case vision
    case horizon
    case lighting
    case detr
    case aesthetic
}

/// Declared per-source freshness windows (seconds, measured against the
/// envelope capture time). A source older than its window is UNAVAILABLE for
/// the analysis result — feature values of mixed age are never silently
/// combined.
enum FeatureSourceFreshnessWindows {
    static let vision: TimeInterval = 0.25
    static let horizon: TimeInterval = 0.4
    static let lighting: TimeInterval = 0.6
    static let detr: TimeInterval = 0.8
    static let aesthetic: TimeInterval = 1.5

    static func window(for source: FeatureSourceID) -> TimeInterval {
        switch source {
        case .vision: return vision
        case .horizon: return horizon
        case .lighting: return lighting
        case .detr: return detr
        case .aesthetic: return aesthetic
        }
    }
}

/// M2-005 frame ownership: one immutable value binding the accepted frame's
/// identity (ID), capture time, orientation, capture-side lens ID, preview
/// geometry, lens generation, pixels, and the measurement timestamp of every
/// feature source built from it. Every analysis result must reference exactly
/// one envelope; sources outside their declared freshness window are reported
/// unavailable rather than silently mixed with newer values.
struct AcceptedFrameEnvelope {
    let frameID: String
    let capturedAt: Date
    let orientation: CGImagePropertyOrientation
    let lensID: String?
    let previewGeometry: CameraPreviewGeometry?
    let lensGeneration: UInt64
    let samplePresentationTimestamp: CMTime
    let sessionGeneration: UInt64?
    let pixelBuffer: CVPixelBuffer
    let featureSourceTimestamps: [FeatureSourceID: Date]

    init(frameID: String,
         capturedAt: Date,
         orientation: CGImagePropertyOrientation,
         lensID: String? = nil,
         previewGeometry: CameraPreviewGeometry? = nil,
         lensGeneration: UInt64,
         pixelBuffer: CVPixelBuffer,
         featureSourceTimestamps: [FeatureSourceID: Date],
         samplePresentationTimestamp: CMTime = .invalid,
         sessionGeneration: UInt64? = nil) {
        let trimmedFrameID = frameID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.frameID = trimmedFrameID
        self.capturedAt = capturedAt
        self.orientation = orientation
        let trimmedLensID = lensID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.lensID = trimmedLensID?.isEmpty == false ? trimmedLensID : nil
        self.previewGeometry = previewGeometry?.imageOrientation == orientation
            ? previewGeometry
            : nil
        self.lensGeneration = lensGeneration
        self.samplePresentationTimestamp = samplePresentationTimestamp
        self.sessionGeneration = sessionGeneration
        self.pixelBuffer = pixelBuffer
        self.featureSourceTimestamps = featureSourceTimestamps
    }

    var isLensGenerationKnown: Bool { lensGeneration != 0 }

    var isLensIDKnown: Bool { lensID != nil }

    /// Age of one source relative to `asOf`. Nil when the source produced no
    /// value for this frame (unknown, therefore unavailable).
    func age(of source: FeatureSourceID, asOf: Date) -> TimeInterval? {
        guard let measuredAt = featureSourceTimestamps[source] else { return nil }
        return max(0, asOf.timeIntervalSince(measuredAt))
    }

    /// Fail-closed availability: a source is available only when it produced
    /// a value for this frame AND that value is inside its declared freshness
    /// window. An unknown lens generation (0) marks every source unavailable:
    /// without the capture generation the evidence cannot be attributed.
    func sourceAvailability(asOf: Date) -> [FeatureSourceID: Bool] {
        var availability: [FeatureSourceID: Bool] = [:]
        for source in FeatureSourceID.allCases {
            guard isLensGenerationKnown,
                  let age = age(of: source, asOf: asOf) else {
                availability[source] = false
                continue
            }
            availability[source] = age <= FeatureSourceFreshnessWindows.window(for: source)
        }
        return availability
    }

    /// True when this envelope is the provenance of the given result frame ID.
    func matches(frameID other: String) -> Bool {
        frameID == other.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - M2-006 Pause evidence package (PauseAnalysisOwner)

/// Explicit temporality declaration of a pause evidence package.
enum PauseEvidenceTemporality: Equatable, Sendable {
    /// Every feature source was measured with the accepted frame.
    case sameFrame
    /// At least one source was re-measured after frame acceptance (declared
    /// aggregate — never a silent mix of ages).
    case temporalAggregate
}

/// Per-source freshness verdict exposed to validation.
struct FeatureFreshnessVerdict: Equatable, Sendable {
    let isAvailable: Bool
    let measuredAt: Date?
    let ageSeconds: TimeInterval?

    static func unavailable(measuredAt: Date?) -> FeatureFreshnessVerdict {
        FeatureFreshnessVerdict(isAvailable: false, measuredAt: measuredAt, ageSeconds: nil)
    }
}

/// M2-006: the pause evidence package. Assembled from the accepted frame's
/// envelope plus optional pause-time re-measurements (fresh local DETR /
/// aesthetic recomputes on the accepted pixel buffer). Every source's age is
/// exposed to validation, and sources outside their declared freshness window
/// are unavailable — pause output cannot combine current inference with stale
/// unmarked values.
struct PauseEvidencePackage: Equatable, Sendable {
    let envelopeFrameID: String
    let envelopeCapturedAt: Date
    let temporality: PauseEvidenceTemporality
    let verdicts: [FeatureSourceID: FeatureFreshnessVerdict]

    /// - Parameters:
    ///   - envelope: the accepted frame's immutable envelope (M2-005).
    ///   - recomputeTimestamps: sources re-measured after acceptance, with
    ///     their pause-time measurement dates.
    ///   - asOf: validation moment. Freshness is judged against this instant
    ///     with the M2-005 declared windows.
    init(envelope: AcceptedFrameEnvelope,
         recomputeTimestamps: [FeatureSourceID: Date],
         asOf: Date) {
        self.envelopeFrameID = envelope.frameID
        self.envelopeCapturedAt = envelope.capturedAt

        var merged = envelope.featureSourceTimestamps
        var recomputed = false
        for (source, date) in recomputeTimestamps {
            merged[source] = date
            recomputed = true
        }
        self.temporality = recomputed ? .temporalAggregate : .sameFrame

        var verdicts: [FeatureSourceID: FeatureFreshnessVerdict] = [:]
        for source in FeatureSourceID.allCases {
            guard let measuredAt = merged[source] else {
                verdicts[source] = .unavailable(measuredAt: nil)
                continue
            }
            let age = max(0, asOf.timeIntervalSince(measuredAt))
            let available = envelope.isLensGenerationKnown
                && age <= FeatureSourceFreshnessWindows.window(for: source)
            verdicts[source] = FeatureFreshnessVerdict(
                isAvailable: available,
                measuredAt: measuredAt,
                ageSeconds: age
            )
        }
        self.verdicts = verdicts
    }

    /// Fail-closed gate: a source value may enter the pause analysis result
    /// only when its verdict is available.
    func isSourceUsable(_ source: FeatureSourceID) -> Bool {
        verdicts[source]?.isAvailable == true
    }

    /// Convenience snapshot of all ages (nil when unavailable), for
    /// diagnostics and validation.
    var exposedAges: [FeatureSourceID: TimeInterval?] {
        var ages: [FeatureSourceID: TimeInterval?] = [:]
        for source in FeatureSourceID.allCases {
            ages[source] = verdicts[source]?.ageSeconds
        }
        return ages
    }
}
