import CoreGraphics
import CoreVideo
import Foundation
import ImageIO

internal final class LatestFrameEvidenceStore: @unchecked Sendable {
    internal struct Snapshot: @unchecked Sendable {
        let pixelBuffer: CVPixelBuffer
        let orientation: CGImagePropertyOrientation
        let sourceFrameId: String
        let capturedAt: Date
        let isStable: Bool

        init?(pixelBuffer: CVPixelBuffer,
              orientation: CGImagePropertyOrientation,
              sourceFrameId: String,
              capturedAt: Date,
              isStable: Bool) {
            let trimmedSourceFrameId = sourceFrameId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedSourceFrameId.isEmpty else { return nil }

            self.pixelBuffer = pixelBuffer
            self.orientation = orientation
            self.sourceFrameId = trimmedSourceFrameId
            self.capturedAt = capturedAt
            self.isStable = isStable
        }
    }

    private let lock = NSLock()
    private var currentSnapshot: Snapshot?

    @discardableResult
    internal func publish(pixelBuffer: CVPixelBuffer,
                          orientation: CGImagePropertyOrientation,
                          sourceFrameId: String,
                          capturedAt: Date,
                          isStable: Bool) -> Bool {
        guard let snapshot = Snapshot(
            pixelBuffer: pixelBuffer,
            orientation: orientation,
            sourceFrameId: sourceFrameId,
            capturedAt: capturedAt,
            isStable: isStable
        ) else {
            return false
        }

        lock.lock()
        currentSnapshot = snapshot
        lock.unlock()
        return true
    }

    internal func snapshot() -> Snapshot? {
        lock.lock()
        let snapshot = currentSnapshot
        lock.unlock()
        return snapshot
    }

    internal func clear() {
        lock.lock()
        currentSnapshot = nil
        lock.unlock()
    }
}
