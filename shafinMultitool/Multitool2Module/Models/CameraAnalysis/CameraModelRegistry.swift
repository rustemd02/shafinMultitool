import Foundation

/// M4-021: the single model version/rollback owner for Camera Coach neural
/// advice. Exactly one bundled model version may be active; any metadata
/// mismatch disables neural advice (the pipeline falls back to its
/// deterministic heuristic path and publishes the honest unavailable state)
/// instead of guessing. A prior compatible bundled version is restored by app
/// update — the registry records the rollback target but never downloads,
/// synthesizes, or hot-swaps model bytes at runtime.
struct CameraModelVersion: Equatable, Sendable {
    /// Frozen contract this artifact was built against.
    let contractVersion: String
    /// Candidate identity from the frozen manifest (e.g. "candidate-a").
    let candidateID: String
    /// Training receipt hash binding weights to config+data.
    let trainingReceiptSHA256: String
    /// Conversion receipt (Core ML export) hash.
    let conversionReceiptSHA256: String
    /// Calibration version bound to this artifact.
    let calibrationVersion: String

    /// The only approved bundled artifact in this build. No model bytes ship
    /// yet (M4-016 conversion pending), so the registry boots to
    /// `.unavailable` — neural advice stays disabled until a real converted
    /// artifact with matching metadata lands in the bundle.
    static let approved: CameraModelVersion? = nil
}

enum CameraModelActivation: Equatable, Sendable {
    /// No approved bundled artifact: neural advice disabled, heuristic path
    /// owns the advice, unavailable state is published honestly.
    case unavailable(reason: String)
    /// Exactly one approved artifact with fully matching metadata.
    case active(version: CameraModelVersion)
    /// Metadata mismatch on a present artifact: neural advice disabled the
    /// same way as unavailable, with the mismatch recorded for diagnostics.
    case mismatchDisabled(detail: String)
}

/// Pure activation gate: the single decision point between the bundled
/// artifact's metadata and the frozen contract. Table-tested.
enum CameraModelRegistry {
    static func activation(
        bundled: CameraModelVersion?,
        contractVersion: String,
        calibrationVersion: String
    ) -> CameraModelActivation {
        guard let bundled else {
            return .unavailable(reason: "no approved bundled model artifact")
        }
        guard bundled.contractVersion == contractVersion else {
            return .mismatchDisabled(detail: "contract \(bundled.contractVersion) != \(contractVersion)")
        }
        guard bundled.calibrationVersion == calibrationVersion else {
            return .mismatchDisabled(detail: "calibration \(bundled.calibrationVersion) != \(calibrationVersion)")
        }
        guard bundled.trainingReceiptSHA256.count == 64,
              bundled.conversionReceiptSHA256.count == 64 else {
            return .mismatchDisabled(detail: "receipt hash malformed")
        }
        return .active(version: bundled)
    }

    /// Rollback target recorded for app-update restore: the last known-good
    /// bundled version compatible with the frozen contract. Runtime restore
    /// happens only through a new app build carrying that artifact.
    static func rollbackTarget(
        current: CameraModelVersion?,
        lastKnownGood: CameraModelVersion?,
        contractVersion: String
    ) -> CameraModelVersion? {
        guard let candidate = lastKnownGood,
              candidate.contractVersion == contractVersion,
              candidate.candidateID != current?.candidateID else {
            return nil
        }
        return candidate
    }
}
