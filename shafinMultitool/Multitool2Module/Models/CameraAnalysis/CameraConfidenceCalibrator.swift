//
//  CameraConfidenceCalibrator.swift
//  shafinMultitool
//
//  M2-018 CalibrationOwner: converts neural and deterministic raw evidence
//  into action-specific CALIBRATED probabilities with selective-risk
//  decisions. Calibration tables are versioned per action/class; raw logits
//  never cross this boundary (outcomes carry only calibrated values);
//  out-of-domain, missing and non-finite inputs yield abstention instead of
//  invented probabilities.
//

import CryptoKit
import Foundation

/// Calibration is tied to the producer of the raw score. A curve fitted to
/// one source cannot certify another source merely because both use 0...1.
enum CameraCalibrationInputVersion: String, Codable, Sendable {
    case boundedPlanConfidenceV1 = "bounded_plan_confidence.v1"
    case technicalStabilityConfidenceV1 = "technical_stability_confidence.v1"
}

/// One knot of a piecewise-linear calibration curve. Knots must be sorted by
/// ascending `raw` with non-decreasing `calibrated` (isotonic shape).
struct CameraCalibrationKnotV1: Codable, Equatable, Sendable {
    let raw: Double
    let calibrated: Double
}

/// Versioned calibration curve for ONE action/class.
struct CameraCalibrationCurveV1: Codable, Equatable, Sendable {
    static let schemaVersion = "cal1"

    let actionID: String
    let version: Int
    let knots: [CameraCalibrationKnotV1]
    /// Raw inputs outside [domainLow, domainHigh] are OUT OF DOMAIN: the
    /// model is being asked about evidence it did not see — abstain.
    let domainLow: Double
    let domainHigh: Double
    /// Absent in historical tables. Such tables remain usable for offline
    /// interpolation, but cannot certify a production episode's evidence.
    let inputVersion: CameraCalibrationInputVersion?

    init(actionID: String,
         version: Int,
         knots: [CameraCalibrationKnotV1],
         domainLow: Double,
         domainHigh: Double,
         inputVersion: CameraCalibrationInputVersion? = nil) {
        self.actionID = actionID
        self.version = version
        self.knots = knots
        self.domainLow = domainLow
        self.domainHigh = domainHigh
        self.inputVersion = inputVersion
    }

    enum ValidationError: Error, Equatable, Sendable {
        case emptyCurve
        case knotsNotSortedByRaw
        case calibratedNotMonotonic
        case valuesOutOfRange
        case nonFiniteValue
        case invertedDomain
    }

    func validate() throws {
        guard !knots.isEmpty else { throw ValidationError.emptyCurve }
        for knot in knots {
            guard knot.raw.isFinite, knot.calibrated.isFinite,
                  knot.calibrated >= 0, knot.calibrated <= 1 else {
                throw ValidationError.nonFiniteValue
            }
        }
        for (first, second) in zip(knots, knots.dropFirst()) {
            guard second.raw > first.raw else { throw ValidationError.knotsNotSortedByRaw }
            guard second.calibrated >= first.calibrated else {
                throw ValidationError.calibratedNotMonotonic
            }
        }
        guard domainLow.isFinite, domainHigh.isFinite, domainLow < domainHigh else {
            throw ValidationError.invertedDomain
        }
    }

    /// Piecewise-linear calibrated probability. Returns nil when `raw` lies
    /// outside the declared domain (selective risk: abstain).
    func calibratedProbability(forRaw raw: Double) -> Double? {
        guard raw.isFinite else { return nil }
        guard raw >= domainLow, raw <= domainHigh else { return nil }
        guard let first = knots.first, let last = knots.last else { return nil }
        if raw <= first.raw { return first.calibrated }
        if raw >= last.raw { return last.calibrated }
        for (left, right) in zip(knots, knots.dropFirst()) where raw >= left.raw && raw <= right.raw {
            let span = right.raw - left.raw
            guard span > 0 else { return left.calibrated }
            let t = (raw - left.raw) / span
            return left.calibrated + t * (right.calibrated - left.calibrated)
        }
        return nil
    }
}

/// Versioned calibration schema: one curve per action/class id.
struct CameraActionCalibrationSchemaV1: Codable, Equatable, Sendable {
    static let schemaVersion = "cal1"

    let schemaVersion: String
    let entries: [String: CameraCalibrationCurveV1]

    init(entries: [String: CameraCalibrationCurveV1]) {
        self.schemaVersion = Self.schemaVersion
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        entries = try container.decode([String: CameraCalibrationCurveV1].self, forKey: .entries)
        guard schemaVersion == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container, debugDescription: "unsupported calibration schema \(schemaVersion)")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(entries, forKey: .entries)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case entries
    }
}

/// The outcome of calibration. Raw logits are intentionally absent — UI and
/// advice layers consume calibrated probabilities only.
enum CameraCalibratedOutcome: Equatable, Sendable {
    /// Calibrated probability within the declared domain.
    case calibrated(Double)
    /// Raw input outside the curve's declared domain — selective abstention.
    case outOfDomain
    /// No calibration entry exists for this action/class — abstain.
    case unavailable

    var probability: Double? {
        switch self {
        case .calibrated(let value): return value
        case .outOfDomain, .unavailable: return nil
        }
    }

    var isAbstaining: Bool {
        probability == nil
    }
}

/// The probability and exact calibration rule travel together. Only the
/// calibrator can construct this value; a planner threshold is not evidence.
struct CameraCalibratedActionEvidence: Equatable, Sendable {
    let probability: Double
    let calibrationReference: String

    fileprivate init(probability: Double, calibrationReference: String) {
        self.probability = probability
        self.calibrationReference = calibrationReference
    }
}

/// The calibration layer used by the advice planner.
struct CameraConfidenceCalibrator: Sendable {
    let schema: CameraActionCalibrationSchemaV1

    /// No measured/approved episode calibration is bundled yet. Keep this
    /// empty until its dataset, fit and admission evidence exist.
    static let unavailable = CameraConfidenceCalibrator(
        schema: CameraActionCalibrationSchemaV1(entries: [:])
    )

    init(schema: CameraActionCalibrationSchemaV1) {
        self.schema = schema
    }

    /// Calibrated probability for one action/class, or an abstention outcome.
    func calibratedProbability(rawLogit: Double, actionID: String) -> CameraCalibratedOutcome {
        guard let curve = validatedCurve(actionID: actionID) else { return .unavailable }
        guard let probability = curve.calibratedProbability(forRaw: rawLogit) else {
            return .outOfDomain
        }
        return .calibrated(probability)
    }

    /// Production handoff: a finite in-domain score, the matching producer
    /// contract, and a valid action-specific curve are all required. No raw
    /// score or guardrail threshold is substituted when any part is missing.
    func calibratedEvidence(rawScore: Double,
                            actionID: String,
                            inputVersion: CameraCalibrationInputVersion) -> CameraCalibratedActionEvidence? {
        guard let reference = calibrationReference(actionID: actionID, inputVersion: inputVersion),
              let probability = calibratedProbability(rawLogit: rawScore, actionID: actionID).probability else {
            return nil
        }
        return CameraCalibratedActionEvidence(probability: probability, calibrationReference: reference)
    }

    /// An after-frame may have no corrective candidate. Its measurements can
    /// still carry the unchanged action calibration reference; this does not
    /// invent an after-frame probability or reinterpret a missing score as 0.
    func calibrationReference(actionID: String,
                              inputVersion: CameraCalibrationInputVersion) -> String? {
        guard let curve = validatedCurve(actionID: actionID),
              curve.inputVersion == inputVersion else { return nil }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(curve) else { return nil }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return "\(schema.schemaVersion):\(digest)"
    }

    private func validatedCurve(actionID: String) -> CameraCalibrationCurveV1? {
        guard schema.schemaVersion == CameraActionCalibrationSchemaV1.schemaVersion,
              !actionID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let curve = schema.entries[actionID],
              curve.actionID == actionID,
              curve.version > 0,
              (try? curve.validate()) != nil else { return nil }
        return curve
    }

    /// Batch form used by the planner when several candidates are calibrated
    /// at once. Any abstaining candidate is reported as such — never mixed.
    func calibratedProbabilities(rawLogits: [String: Double]) -> [String: CameraCalibratedOutcome] {
        var result: [String: CameraCalibratedOutcome] = [:]
        for (actionID, raw) in rawLogits {
            result[actionID] = calibratedProbability(rawLogit: raw, actionID: actionID)
        }
        return result
    }

    /// Expected calibration error over binned (predicted, actual) pairs.
    /// Perfectly calibrated predictions yield 0.
    static func expectedCalibrationError(
        pairs: [(predicted: Double, actual: Double)],
        bins: Int = 10
    ) -> Double {
        guard bins > 0, !pairs.isEmpty else { return 0 }
        var binSum = [Double](repeating: 0, count: bins)
        var binCount = [Int](repeating: 0, count: bins)
        for pair in pairs {
            guard pair.predicted.isFinite, pair.actual.isFinite else { continue }
            let clamped = min(1, max(0, pair.predicted))
            var bin = Int(clamped * Double(bins))
            if bin >= bins { bin = bins - 1 }
            binSum[bin] += pair.actual
            binCount[bin] += 1
        }
        var totalError = 0.0
        var totalSamples = 0
        for bin in 0..<bins where binCount[bin] > 0 {
            let meanPredicted = Double(bin + 1) / Double(bins) - 1.0 / (2 * Double(bins))
            let meanActual = binSum[bin] / Double(binCount[bin])
            totalError += Double(binCount[bin]) * abs(meanPredicted - meanActual)
            totalSamples += binCount[bin]
        }
        guard totalSamples > 0 else { return 0 }
        return totalError / Double(totalSamples)
    }
}
