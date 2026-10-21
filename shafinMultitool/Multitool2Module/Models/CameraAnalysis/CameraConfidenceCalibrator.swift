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
struct CameraConfidenceCalibrator: Equatable, Sendable {
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

// MARK: - CAM-003: typed production calibration artifact contract
//
// ML-002 H7 (`calibration_artifact`, routing CAM-003/ML-007): the production
// calibration artifact is not a tensor head. It is a versioned, hash-bound
// document that carries the per-head/per-action calibration curves consumed
// by this calibrator path plus the ML-002 show/silent thresholds. This section
// defines the contract and the fail-closed loader only; it admits nothing:
// no production artifact ships in this build (ML-002 GAP-4, ML-007 pending),
// so the runtime default remains `CameraConfidenceCalibrator.unavailable` and
// every consumer keeps its `calibration_unavailable` behavior. When a future
// admitted artifact lands (ML-015/CAM-011), it may only enter the runtime
// through `CameraCalibrationArtifact.load`/`loadBundledResource`, which refuse
// anything missing, tampered, schema-incompatible, or provenance-less.

/// The ML-002 v1 production tensor heads a calibration artifact may cover.
/// `scene_class_logits`, `subjectness_roi_agreement_logits` and `embedding`
/// are outside the production set and cannot be declared here.
enum CameraProductionCalibrationHeadV1: String, Codable, CaseIterable, Sendable {
    case goodFrameProbability = "good_frame_probability"
    case issueLogits = "issue_logits"
    case actionUtilityLogits = "action_utility_logits"
    case continuousTargetDeltas = "continuous_target_deltas"
    case riskProbability = "risk_probability"
    case abstentionProbability = "abstention_probability"
}

/// ML-002 H7 show/silent thresholds for one covered head: `silent` is the
/// calibrated-confidence floor below which advice stays silent, `show` is the
/// level required to surface advice. Both live in [0, 1] with
/// `silent <= show`. No runtime consumer exists yet (CAM-012 owns the
/// decision wiring); the artifact carries them so the future consumer cannot
/// invent its own thresholds outside the admitted artifact.
struct CameraCalibrationShowSilentThresholdsV1: Codable, Equatable, Sendable {
    let show: Double
    let silent: Double

    var isValid: Bool {
        [show, silent].allSatisfy(\.isFinite)
            && (0...1).contains(show)
            && (0...1).contains(silent)
            && silent <= show
    }
}

/// The typed production calibration artifact envelope. `schemaVersion` is the
/// envelope contract version; the embedded payload keeps its own established
/// "cal1" curve schema — this contract deliberately creates no parallel
/// payload format and no parallel curve semantics.
struct CameraProductionCalibrationArtifactV1: Codable, Equatable, Sendable {
    static let contractID = "camera_calibration_artifact"
    static let schemaVersion = "1"

    let schemaVersion: String
    let artifactVersion: Int
    /// Non-empty, duplicate-free subset of the ML-002 production heads whose
    /// outputs this calibration is fitted to cover.
    let coveredHeads: [CameraProductionCalibrationHeadV1]
    /// Hash-bound calibration payload consumed by `CameraConfidenceCalibrator`.
    let payload: CameraActionCalibrationSchemaV1
    /// SHA-256 (lowercase hex) over the CANONICAL payload bytes: the decoded
    /// payload re-encoded with `JSONEncoder` `.sortedKeys`. Producers (ML-007)
    /// and this loader must agree on exactly this rule; the hash therefore
    /// does not depend on envelope whitespace or key order.
    let payloadSHA256: String
    /// Per-head show/silent thresholds keyed by covered head id.
    let thresholds: [String: CameraCalibrationShowSilentThresholdsV1]

    init(artifactVersion: Int,
         coveredHeads: [CameraProductionCalibrationHeadV1],
         payload: CameraActionCalibrationSchemaV1,
         payloadSHA256: String,
         thresholds: [String: CameraCalibrationShowSilentThresholdsV1] = [:]) {
        self.schemaVersion = Self.schemaVersion
        self.artifactVersion = artifactVersion
        self.coveredHeads = coveredHeads
        self.payload = payload
        self.payloadSHA256 = payloadSHA256
        self.thresholds = thresholds
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case artifactVersion
        case coveredHeads
        case payload
        case payloadSHA256
        case thresholds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        guard schemaVersion == Self.schemaVersion else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: container,
                                                   debugDescription: "unsupported calibration artifact schema \(schemaVersion)")
        }
        artifactVersion = try container.decode(Int.self, forKey: .artifactVersion)
        coveredHeads = try container.decode([CameraProductionCalibrationHeadV1].self, forKey: .coveredHeads)
        payload = try container.decode(CameraActionCalibrationSchemaV1.self, forKey: .payload)
        payloadSHA256 = try container.decode(String.self, forKey: .payloadSHA256)
        thresholds = try container.decodeIfPresent([String: CameraCalibrationShowSilentThresholdsV1].self,
                                                   forKey: .thresholds) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(artifactVersion, forKey: .artifactVersion)
        try container.encode(coveredHeads, forKey: .coveredHeads)
        try container.encode(payload, forKey: .payload)
        try container.encode(payloadSHA256, forKey: .payloadSHA256)
        try container.encode(thresholds, forKey: .thresholds)
    }

    /// Canonical bytes bound by `payloadSHA256`.
    static func canonicalPayloadData(_ payload: CameraActionCalibrationSchemaV1) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return (try? encoder.encode(payload)) ?? Data()
    }

    static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Typed fail-closed reasons. Every one of them means "no calibration":
/// callers must map them to `CameraConfidenceCalibrator.unavailable`, never
/// to a default or substituted table.
enum CameraCalibrationArtifactFailure: Equatable, Sendable {
    case missingResource
    case unreadableResource
    case emptyData
    case malformedJSON
    case unsupportedSchemaVersion(String)
    case unsupportedArtifactVersion(Int)
    case emptyCoverage
    case duplicateCoverage
    case payloadHashMalformed
    case payloadHashMismatch(expected: String, actual: String)
    case emptyPayload
    case invalidCurve(actionID: String)
    case missingProducerProvenance(actionID: String)
    case invalidThreshold(headID: String)
    case thresholdForUncoveredHead(headID: String)
}

/// A verified artifact plus the calibrator built from it. `reference` binds
/// the runtime calibrator to the exact contract version and payload digest,
/// so downstream evidence can name the calibration it used.
struct CameraCalibrationArtifactLoadResult: Equatable, Sendable {
    let calibrator: CameraConfidenceCalibrator
    let artifact: CameraProductionCalibrationArtifactV1
    let reference: String

    func thresholds(for head: CameraProductionCalibrationHeadV1) -> CameraCalibrationShowSilentThresholdsV1? {
        artifact.thresholds[head.rawValue]
    }
}

/// Outcome of fail-closed artifact loading. Only `.loaded` exposes a
/// calibrator; every failure path yields `nil` here by construction.
enum CameraCalibrationArtifactLoadOutcome: Equatable, Sendable {
    case loaded(CameraCalibrationArtifactLoadResult)
    case unavailable(CameraCalibrationArtifactFailure)

    var calibrator: CameraConfidenceCalibrator? {
        switch self {
        case .loaded(let result): return result.calibrator
        case .unavailable: return nil
        }
    }
}

/// The single fail-closed entry point for production calibration artifacts.
enum CameraCalibrationArtifact {
    /// Load and verify an artifact from bytes. Missing bytes, malformed JSON,
    /// schema/version mismatch, hash mismatch or malformed hash, invalid or
    /// provenance-less curves, and invalid thresholds all yield
    /// `.unavailable` — never a default calibrator and never a crash.
    static func load(from data: Data) -> CameraCalibrationArtifactLoadOutcome {
        guard !data.isEmpty else { return .unavailable(.emptyData) }
        guard let probe = try? JSONDecoder().decode(VersionProbe.self, from: data) else {
            return .unavailable(.malformedJSON)
        }
        guard probe.schemaVersion == CameraProductionCalibrationArtifactV1.schemaVersion else {
            return .unavailable(.unsupportedSchemaVersion(probe.schemaVersion))
        }
        guard let version = probe.artifactVersion, version >= 1 else {
            return .unavailable(.unsupportedArtifactVersion(probe.artifactVersion ?? 0))
        }
        guard let artifact = try? JSONDecoder().decode(CameraProductionCalibrationArtifactV1.self, from: data) else {
            return .unavailable(.malformedJSON)
        }
        if let failure = validationFailure(of: artifact) {
            return .unavailable(failure)
        }
        let digest = CameraProductionCalibrationArtifactV1.sha256Hex(
            of: CameraProductionCalibrationArtifactV1.canonicalPayloadData(artifact.payload)
        )
        return .loaded(CameraCalibrationArtifactLoadResult(
            calibrator: CameraConfidenceCalibrator(schema: artifact.payload),
            artifact: artifact,
            reference: "\(CameraProductionCalibrationArtifactV1.contractID).v\(CameraProductionCalibrationArtifactV1.schemaVersion):\(digest)"
        ))
    }

    /// Bundle-resource entry point. A missing or unreadable resource is an
    /// honest `.unavailable` — no bundled production calibration artifact
    /// exists yet, and this call must not fake one.
    static func loadBundledResource(named name: String,
                                    extension fileExtension: String = "json",
                                    in bundle: Bundle) -> CameraCalibrationArtifactLoadOutcome {
        guard let url = bundle.url(forResource: name, withExtension: fileExtension) else {
            return .unavailable(.missingResource)
        }
        guard let data = try? Data(contentsOf: url) else {
            return .unavailable(.unreadableResource)
        }
        return load(from: data)
    }

    private static func validationFailure(
        of artifact: CameraProductionCalibrationArtifactV1
    ) -> CameraCalibrationArtifactFailure? {
        guard !artifact.coveredHeads.isEmpty else { return .emptyCoverage }
        guard Set(artifact.coveredHeads).count == artifact.coveredHeads.count else {
            return .duplicateCoverage
        }
        // Integrity before semantics: a tampered payload is reported as
        // tampered even if its curves would also fail validation.
        guard isHexDigest(artifact.payloadSHA256) else { return .payloadHashMalformed }
        let actual = CameraProductionCalibrationArtifactV1.sha256Hex(
            of: CameraProductionCalibrationArtifactV1.canonicalPayloadData(artifact.payload)
        )
        if actual != artifact.payloadSHA256.lowercased() {
            return .payloadHashMismatch(expected: artifact.payloadSHA256, actual: actual)
        }
        guard !artifact.payload.entries.isEmpty else { return .emptyPayload }
        for actionID in artifact.payload.entries.keys.sorted() {
            guard let curve = artifact.payload.entries[actionID] else { continue }
            guard curve.actionID == actionID,
                  curve.version > 0,
                  (try? curve.validate()) != nil else {
                return .invalidCurve(actionID: actionID)
            }
            // Production handoff rule, identical to `calibratedEvidence`: a
            // curve without producer provenance cannot certify production
            // evidence, so it cannot be admitted inside a production artifact.
            guard curve.inputVersion != nil else {
                return .missingProducerProvenance(actionID: actionID)
            }
        }
        for headID in artifact.thresholds.keys.sorted() {
            guard let head = CameraProductionCalibrationHeadV1(rawValue: headID),
                  artifact.coveredHeads.contains(head) else {
                return .thresholdForUncoveredHead(headID: headID)
            }
            guard let threshold = artifact.thresholds[headID], threshold.isValid else {
                return .invalidThreshold(headID: headID)
            }
        }
        return nil
    }

    private static func isHexDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    private struct VersionProbe: Decodable {
        let schemaVersion: String
        let artifactVersion: Int?
    }
}
