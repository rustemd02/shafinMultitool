//
//  CameraConfidenceCalibratorTests.swift
//  shafinMultitoolTests
//
//  M2-018 CalibrationOwner: calibration table fixtures, monotonicity, ECE
//  calculation, selective-risk abstention, and the raw-logit containment
//  guarantee (raw logits never reach UI-facing outcomes).
//

import CryptoKit
import XCTest
@testable import shafinMultitool

final class CameraConfidenceCalibratorTests: XCTestCase {

    private func knot(_ raw: Double, _ calibrated: Double) -> CameraCalibrationKnotV1 {
        CameraCalibrationKnotV1(raw: raw, calibrated: calibrated)
    }

    private var identitySchema: CameraActionCalibrationSchemaV1 {
        CameraActionCalibrationSchemaV1(entries: [
            "level_horizon": CameraCalibrationCurveV1(
                actionID: "level_horizon",
                version: 1,
                knots: [knot(0, 0), knot(1, 1)],
                domainLow: 0,
                domainHigh: 1
            ),
        ])
    }

    // MARK: - Schema validation

    func testNonMonotonicCurveIsRejected() {
        let schema = CameraActionCalibrationSchemaV1(entries: [
            "bad": CameraCalibrationCurveV1(
                actionID: "bad", version: 1,
                knots: [knot(0, 0.2), knot(0.5, 0.8), knot(1, 0.4)],
                domainLow: 0, domainHigh: 1
            ),
        ])
        XCTAssertThrowsError(try schema.entries["bad"]!.validate()) { error in
            XCTAssertEqual(error as? CameraCalibrationCurveV1.ValidationError, .calibratedNotMonotonic)
        }
    }

    func testUnsortedKnotsAndNonFiniteAndBadDomainAreRejected() {
        let unsorted = CameraCalibrationCurveV1(
            actionID: "a", version: 1,
            knots: [knot(0.5, 0.2), knot(0.1, 0.3)], domainLow: 0, domainHigh: 1
        )
        XCTAssertThrowsError(try unsorted.validate()) { error in
            XCTAssertEqual(error as? CameraCalibrationCurveV1.ValidationError, .knotsNotSortedByRaw)
        }

        let nonFinite = CameraCalibrationCurveV1(
            actionID: "a", version: 1,
            knots: [knot(0, .nan)], domainLow: 0, domainHigh: 1
        )
        XCTAssertThrowsError(try nonFinite.validate()) { error in
            XCTAssertEqual(error as? CameraCalibrationCurveV1.ValidationError, .nonFiniteValue)
        }

        let inverted = CameraCalibrationCurveV1(
            actionID: "a", version: 1, knots: [knot(0, 0)], domainLow: 1, domainHigh: 0
        )
        XCTAssertThrowsError(try inverted.validate()) { error in
            XCTAssertEqual(error as? CameraCalibrationCurveV1.ValidationError, .invertedDomain)
        }

        let empty = CameraCalibrationCurveV1(actionID: "a", version: 1, knots: [], domainLow: 0, domainHigh: 1)
        XCTAssertThrowsError(try empty.validate()) { error in
            XCTAssertEqual(error as? CameraCalibrationCurveV1.ValidationError, .emptyCurve)
        }
    }

    // MARK: - Calibration outcomes

    func testIdentityCurveCalibratesWithinDomain() {
        let calibrator = CameraConfidenceCalibrator(schema: identitySchema)
        for raw in [0.0, 0.25, 0.5, 0.75, 1.0] {
            XCTAssertEqual(
                calibrator.calibratedProbability(rawLogit: raw, actionID: "level_horizon").probability!,
                raw, accuracy: 1e-12
            )
        }
    }

    func testOutOfDomainRawYieldsSelectiveAbstention() {
        let calibrator = CameraConfidenceCalibrator(schema: identitySchema)
        XCTAssertEqual(calibrator.calibratedProbability(rawLogit: -0.5, actionID: "level_horizon"), .outOfDomain)
        XCTAssertEqual(calibrator.calibratedProbability(rawLogit: 1.5, actionID: "level_horizon"), .outOfDomain)
    }

    func testMissingEntryAndNonFiniteRawAbstain() {
        let calibrator = CameraConfidenceCalibrator(schema: identitySchema)
        XCTAssertEqual(calibrator.calibratedProbability(rawLogit: 0.5, actionID: "unknown_action"), .unavailable)
        XCTAssertEqual(
            calibrator.calibratedProbability(rawLogit: .nan, actionID: "level_horizon"),
            .outOfDomain,
            "non-finite raw input must abstain, never produce a probability"
        )
    }

    func testOutcomeNeverExposesRawLogits() {
        // The UI-facing outcome type carries only the calibrated probability:
        // out-of-domain raw logits can never leak through as values.
        let calibrator = CameraConfidenceCalibrator(schema: identitySchema)
        let outcome = calibrator.calibratedProbability(rawLogit: 123.456, actionID: "level_horizon")
        XCTAssertEqual(outcome, .outOfDomain)
        XCTAssertNil(outcome.probability)
        XCTAssertTrue(outcome.isAbstaining)
    }

    // MARK: - Piecewise interpolation and monotonicity

    func testPiecewiseCurveIsMonotonicAcrossGrid() {
        let schema = CameraActionCalibrationSchemaV1(entries: [
            "shift_frame_left": CameraCalibrationCurveV1(
                actionID: "shift_frame_left", version: 3,
                knots: [knot(0, 0.05), knot(0.25, 0.2), knot(0.5, 0.5), knot(0.75, 0.8), knot(1, 0.95)],
                domainLow: 0, domainHigh: 1
            ),
        ])
        let calibrator = CameraConfidenceCalibrator(schema: schema)
        var previous = -1.0
        let steps = 200
        for step in 0...steps {
            let raw = Double(step) / Double(steps)
            let outcome = calibrator.calibratedProbability(rawLogit: raw, actionID: "shift_frame_left")
            guard case let .calibrated(probability) = outcome else {
                return XCTFail("grid points are inside the domain and must calibrate, got \(outcome)")
            }
            XCTAssertGreaterThanOrEqual(probability, previous)
            previous = probability
        }
    }

    // MARK: - Expected calibration error

    func testProductionEvidenceRequiresMatchingInputContract() {
        let action = SemanticActionType.shiftFrameRight.rawValue
        let scoped = CameraEpisodeCalibrationFixture.calibrator
        let evidence = scoped.calibratedEvidence(rawScore: 0.8, actionID: action,
                                                 inputVersion: .boundedPlanConfidenceV1)
        XCTAssertEqual(evidence?.probability ?? .nan, 0.848, accuracy: 1e-12)
        XCTAssertTrue(evidence?.calibrationReference.hasPrefix("cal1:") == true)
        XCTAssertNil(scoped.calibratedEvidence(rawScore: 0.8, actionID: action,
                                               inputVersion: .technicalStabilityConfidenceV1))
        XCTAssertNil(CameraConfidenceCalibrator.unavailable.calibratedEvidence(
            rawScore: 0.99, actionID: action, inputVersion: .boundedPlanConfidenceV1
        ))
        XCTAssertNil(CameraConfidenceCalibrator(schema: identitySchema).calibratedEvidence(
            rawScore: 0.99, actionID: "level_horizon", inputVersion: .boundedPlanConfidenceV1
        ), "historical interpolation tables without producer provenance cannot certify an episode")
        for raw in [Double.nan, .infinity, -0.01, 1.01] {
            XCTAssertNil(scoped.calibratedEvidence(rawScore: raw, actionID: action,
                                                   inputVersion: .boundedPlanConfidenceV1))
        }
    }

    func testInvalidOrMisattributedCurvesCannotProduceProbabilities() {
        let invalidCurves = [
            CameraCalibrationCurveV1(actionID: "other", version: 1,
                                     knots: [knot(0, 0.1), knot(1, 0.9)], domainLow: 0, domainHigh: 1),
            CameraCalibrationCurveV1(actionID: "action", version: 0,
                                     knots: [knot(0, 0.1), knot(1, 0.9)], domainLow: 0, domainHigh: 1),
            CameraCalibrationCurveV1(actionID: "action", version: 1,
                                     knots: [knot(0, 0.9), knot(1, 0.1)], domainLow: 0, domainHigh: 1),
            CameraCalibrationCurveV1(actionID: "action", version: 1,
                                     knots: [knot(0, .nan)], domainLow: 0, domainHigh: 1)
        ]
        for curve in invalidCurves {
            let calibrator = CameraConfidenceCalibrator(schema: .init(entries: ["action": curve]))
            XCTAssertEqual(calibrator.calibratedProbability(rawLogit: 0.9, actionID: "action"), .unavailable)
            XCTAssertNil(calibrator.calibrationReference(actionID: "action", inputVersion: .boundedPlanConfidenceV1))
        }
    }

    func testCalibrationReferenceBindsCurveBytesNotJustDeclaredVersion() throws {
        let action = SemanticActionType.shiftFrameRight.rawValue
        let original = CameraEpisodeCalibrationFixture.calibrator
        let curve = try XCTUnwrap(original.schema.entries[action])
        let changedCurve = CameraCalibrationCurveV1(
            actionID: action, version: curve.version,
            knots: [knot(0, 0.02), knot(0.5, 0.60), knot(1, 0.98)],
            domainLow: curve.domainLow, domainHigh: curve.domainHigh,
            inputVersion: curve.inputVersion
        )
        let changed = CameraConfidenceCalibrator(schema: .init(entries: [action: changedCurve]))
        let originalReference = try XCTUnwrap(original.calibrationReference(actionID: action,
                                                                            inputVersion: .boundedPlanConfidenceV1))
        let changedReference = try XCTUnwrap(changed.calibrationReference(actionID: action,
                                                                         inputVersion: .boundedPlanConfidenceV1))
        XCTAssertNotEqual(originalReference, changedReference)
        let decoded = try JSONDecoder().decode(CameraActionCalibrationSchemaV1.self,
                                                from: JSONEncoder().encode(original.schema))
        XCTAssertEqual(originalReference, CameraConfidenceCalibrator(schema: decoded).calibrationReference(
            actionID: action, inputVersion: .boundedPlanConfidenceV1
        ))
    }

    func testPerfectCalibrationYieldsZeroECE() {
        // One perfectly-calibrated point per bin center: bin mean predicted
        // == bin mean actual == center, so the total error is exactly 0.
        let pairs = (0..<10).map { bin -> (Double, Double) in
            let center = Double(bin) / 10.0 + 0.05
            return (center, center)
        }
        XCTAssertEqual(
            CameraConfidenceCalibrator.expectedCalibrationError(pairs: pairs),
            0, accuracy: 1e-9
        )
    }

    func testKnownOffsetYieldsExpectedECE() {
        // Every prediction in the top bin is 0.8 while the actual outcome is
        // 0.5: single populated bin with |0.8 − 0.5| = 0.3.
        let pairs = Array(repeating: (predicted: 0.85, actual: 0.5), count: 50)
        XCTAssertEqual(
            CameraConfidenceCalibrator.expectedCalibrationError(pairs: pairs),
            0.35, accuracy: 1e-9,
            "bin center 0.85 vs actual 0.5 gives |0.85 - 0.5| = 0.35"
        )
    }

    // MARK: - Codable round-trip (fixture)

    func testSchemaCodableRoundTrip() throws {
        let schema = identitySchema
        let data = try JSONEncoder().encode(schema)
        let decoded = try JSONDecoder().decode(CameraActionCalibrationSchemaV1.self, from: data)
        XCTAssertEqual(decoded, schema)
        XCTAssertEqual(decoded.schemaVersion, "cal1")
        XCTAssertEqual(decoded.entries["level_horizon"]?.version, 1)
    }

    // MARK: - CAM-003: typed production calibration artifact (fail-closed loading)
    //
    // ML-002 H7 routing: the artifact envelope is hash-bound over canonical
    // payload bytes (decoded payload re-encoded with .sortedKeys); the tests
    // pin that rule independently with CryptoKit instead of reusing the
    // production digest helper.

    private func fixtureSHA256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func fixtureCanonicalPayloadData(_ payload: CameraActionCalibrationSchemaV1) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try! encoder.encode(payload)
    }

    private var artifactPayload: CameraActionCalibrationSchemaV1 {
        CameraActionCalibrationSchemaV1(entries: [
            "shift_frame_left": CameraCalibrationCurveV1(
                actionID: "shift_frame_left", version: 2,
                knots: [knot(0, 0.02), knot(0.5, 0.65), knot(1, 0.98)],
                domainLow: 0, domainHigh: 1,
                inputVersion: .boundedPlanConfidenceV1
            ),
            "stabilize_camera": CameraCalibrationCurveV1(
                actionID: "stabilize_camera", version: 1,
                knots: [knot(0, 0.05), knot(1, 0.9)],
                domainLow: 0, domainHigh: 1,
                inputVersion: .technicalStabilityConfidenceV1
            ),
        ])
    }

    private func artifactData(payload: CameraActionCalibrationSchemaV1,
                              artifactVersion: Int = 1,
                              coveredHeads: [CameraProductionCalibrationHeadV1] = [.actionUtilityLogits],
                              payloadSHA256: String? = nil,
                              thresholds: [String: CameraCalibrationShowSilentThresholdsV1] = [:]) throws -> Data {
        let digest = payloadSHA256 ?? fixtureSHA256Hex(fixtureCanonicalPayloadData(payload))
        let artifact = CameraProductionCalibrationArtifactV1(
            artifactVersion: artifactVersion,
            coveredHeads: coveredHeads,
            payload: payload,
            payloadSHA256: digest,
            thresholds: thresholds
        )
        return try JSONEncoder().encode(artifact)
    }

    func testArtifactLoadMissingDataAndMissingResourceAreUnavailable() {
        XCTAssertEqual(CameraCalibrationArtifact.load(from: Data()),
                       .unavailable(.emptyData))
        XCTAssertEqual(
            CameraCalibrationArtifact.loadBundledResource(
                named: "no_production_calibration_artifact_ships_in_this_build",
                in: Bundle(for: CameraConfidenceCalibratorTests.self)
            ),
            .unavailable(.missingResource)
        )
        XCTAssertNil(CameraCalibrationArtifact.load(from: Data()).calibrator,
                     "fail-closed loading must not expose a calibrator")
    }

    func testArtifactLoadRejectsMalformedAndIncompatibleSchemas() throws {
        XCTAssertEqual(CameraCalibrationArtifact.load(from: Data("definitely not json".utf8)),
                       .unavailable(.malformedJSON))

        let wrongSchema = """
        {"schemaVersion":"2","artifactVersion":1,"coveredHeads":["action_utility_logits"],\
        "payload":{"schemaVersion":"cal1","entries":{}},"payloadSHA256":"\(String(repeating: "a", count: 64))"}
        """
        XCTAssertEqual(CameraCalibrationArtifact.load(from: Data(wrongSchema.utf8)),
                       .unavailable(.unsupportedSchemaVersion("2")))

        let zeroVersionData = try artifactData(payload: artifactPayload, artifactVersion: 0)
        XCTAssertEqual(CameraCalibrationArtifact.load(from: zeroVersionData),
                       .unavailable(.unsupportedArtifactVersion(0)))
    }

    func testArtifactCoverageMustBePresentAndUnique() throws {
        let payload = artifactPayload
        XCTAssertEqual(try CameraCalibrationArtifact.load(from: artifactData(payload: payload, coveredHeads: [])),
                       .unavailable(.emptyCoverage))
        XCTAssertEqual(
            try CameraCalibrationArtifact.load(from: artifactData(
                payload: payload,
                coveredHeads: [.actionUtilityLogits, .actionUtilityLogits]
            )),
            .unavailable(.duplicateCoverage)
        )
    }

    func testTamperedPayloadHashIsUnavailable() throws {
        let payload = artifactPayload
        let validDigest = fixtureSHA256Hex(fixtureCanonicalPayloadData(payload))
        guard case .loaded(let valid) = try CameraCalibrationArtifact.load(
            from: artifactData(payload: payload, payloadSHA256: validDigest)) else {
            return XCTFail("valid fixture must load")
        }
        XCTAssertTrue(valid.reference.hasPrefix("camera_calibration_artifact.v1:"))
        XCTAssertTrue(valid.reference.hasSuffix(validDigest))

        // Flip one calibrated knot value but keep the declared hash.
        let curve = try XCTUnwrap(payload.entries["shift_frame_left"])
        let tamperedPayload = CameraActionCalibrationSchemaV1(entries: [
            "shift_frame_left": CameraCalibrationCurveV1(
                actionID: curve.actionID, version: curve.version,
                knots: [knot(0, 0.02), knot(0.5, 0.66), knot(1, 0.98)],
                domainLow: curve.domainLow, domainHigh: curve.domainHigh,
                inputVersion: curve.inputVersion
            ),
            "stabilize_camera": try XCTUnwrap(payload.entries["stabilize_camera"]),
        ])
        let tamperedData = try artifactData(payload: tamperedPayload, payloadSHA256: validDigest)
        XCTAssertEqual(CameraCalibrationArtifact.load(from: tamperedData),
                       .unavailable(.payloadHashMismatch(
                           expected: validDigest,
                           actual: fixtureSHA256Hex(fixtureCanonicalPayloadData(tamperedPayload))
                       )))
        XCTAssertNil(CameraCalibrationArtifact.load(from: tamperedData).calibrator)

        XCTAssertEqual(try CameraCalibrationArtifact.load(from: artifactData(payload: payload,
                                                                             payloadSHA256: "deadbeef")),
                       .unavailable(.payloadHashMalformed))
    }

    func testInvalidOrProvenancelessPayloadEntriesAreUnavailable() throws {
        func curve(_ actionID: String,
                   version: Int = 1,
                   knots: [CameraCalibrationKnotV1],
                   inputVersion: CameraCalibrationInputVersion? = .boundedPlanConfidenceV1) -> CameraCalibrationCurveV1 {
            CameraCalibrationCurveV1(actionID: actionID, version: version,
                                     knots: knots, domainLow: 0, domainHigh: 1,
                                     inputVersion: inputVersion)
        }

        let mismatchedKey = CameraActionCalibrationSchemaV1(entries: [
            "shift_frame_left": curve("other_action", knots: [knot(0, 0), knot(1, 1)])
        ])
        XCTAssertEqual(try CameraCalibrationArtifact.load(from: artifactData(payload: mismatchedKey)),
                       .unavailable(.invalidCurve(actionID: "shift_frame_left")))

        let nonMonotonic = CameraActionCalibrationSchemaV1(entries: [
            "shift_frame_left": curve("shift_frame_left", knots: [knot(0, 0.9), knot(1, 0.1)])
        ])
        XCTAssertEqual(try CameraCalibrationArtifact.load(from: artifactData(payload: nonMonotonic)),
                       .unavailable(.invalidCurve(actionID: "shift_frame_left")))

        let zeroVersion = CameraActionCalibrationSchemaV1(entries: [
            "shift_frame_left": curve("shift_frame_left", version: 0, knots: [knot(0, 0), knot(1, 1)])
        ])
        XCTAssertEqual(try CameraCalibrationArtifact.load(from: artifactData(payload: zeroVersion)),
                       .unavailable(.invalidCurve(actionID: "shift_frame_left")))

        // Historical tables without producer provenance cannot be admitted as
        // a production artifact even though they interpolate fine offline.
        let provenanceless = CameraActionCalibrationSchemaV1(entries: [
            "shift_frame_left": curve("shift_frame_left",
                                      knots: [knot(0, 0), knot(1, 1)],
                                      inputVersion: nil)
        ])
        XCTAssertEqual(try CameraCalibrationArtifact.load(from: artifactData(payload: provenanceless)),
                       .unavailable(.missingProducerProvenance(actionID: "shift_frame_left")))

        XCTAssertEqual(try CameraCalibrationArtifact.load(
            from: artifactData(payload: CameraActionCalibrationSchemaV1(entries: [:]))),
            .unavailable(.emptyPayload))
    }

    func testInvalidOrUncoveredThresholdsAreUnavailable() throws {
        let payload = artifactPayload
        XCTAssertEqual(
            try CameraCalibrationArtifact.load(from: artifactData(
                payload: payload,
                thresholds: ["action_utility_logits": .init(show: 0.3, silent: 0.6)]
            )),
            .unavailable(.invalidThreshold(headID: "action_utility_logits")),
            "silent must not exceed show"
        )
        XCTAssertEqual(
            try CameraCalibrationArtifact.load(from: artifactData(
                payload: payload,
                thresholds: ["action_utility_logits": .init(show: 1.5, silent: 0.2)]
            )),
            .unavailable(.invalidThreshold(headID: "action_utility_logits"))
        )
        // A valid head id outside the artifact's declared coverage is refused.
        XCTAssertEqual(
            try CameraCalibrationArtifact.load(from: artifactData(
                payload: payload,
                thresholds: ["risk_probability": .init(show: 0.6, silent: 0.2)]
            )),
            .unavailable(.thresholdForUncoveredHead(headID: "risk_probability"))
        )
        // So is a key that is not a production head at all.
        XCTAssertEqual(
            try CameraCalibrationArtifact.load(from: artifactData(
                payload: payload,
                thresholds: ["legacy_confidence_v0": .init(show: 0.6, silent: 0.2)]
            )),
            .unavailable(.thresholdForUncoveredHead(headID: "legacy_confidence_v0"))
        )
    }

    func testValidFixtureLoadsAndCalibratesDeterministically() throws {
        let payload = artifactPayload
        let thresholds = [
            "action_utility_logits": CameraCalibrationShowSilentThresholdsV1(show: 0.60, silent: 0.20)
        ]
        let data = try artifactData(payload: payload, thresholds: thresholds)

        guard case .loaded(let first) = CameraCalibrationArtifact.load(from: data),
              case .loaded(let second) = CameraCalibrationArtifact.load(from: data) else {
            return XCTFail("valid fixture must load twice")
        }

        // Two reads of the same artifact are identical, reference included.
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.reference.hasPrefix("camera_calibration_artifact.v1:"))
        XCTAssertTrue(first.reference.contains(
            fixtureSHA256Hex(fixtureCanonicalPayloadData(payload))
        ))

        // Show/silent thresholds travel with the artifact, per covered head.
        XCTAssertEqual(first.thresholds(for: .actionUtilityLogits)?.show, 0.60)
        XCTAssertEqual(first.thresholds(for: .actionUtilityLogits)?.silent, 0.20)
        XCTAssertNil(first.thresholds(for: .abstentionProbability))

        // Calibrated outputs are the pure piecewise interpolation of the
        // verified payload — nothing else may influence them.
        let grid = stride(from: 0.0, through: 1.0, by: 0.05).map { $0 }
        let firstOutputs = grid.map {
            first.calibrator.calibratedProbability(rawLogit: $0, actionID: "shift_frame_left")
        }
        let secondOutputs = grid.map {
            second.calibrator.calibratedProbability(rawLogit: $0, actionID: "shift_frame_left")
        }
        XCTAssertEqual(firstOutputs, secondOutputs, "two loads must calibrate identically")

        let curve = try XCTUnwrap(payload.entries["shift_frame_left"])
        for (raw, outcome) in zip(grid, firstOutputs) {
            guard case let .calibrated(probability) = outcome else {
                return XCTFail("grid point \(raw) is inside the declared domain")
            }
            XCTAssertEqual(probability,
                           try XCTUnwrap(curve.calibratedProbability(forRaw: raw)),
                           accuracy: 1e-15)
        }
        XCTAssertEqual(
            first.calibrator.calibratedProbability(rawLogit: 0.25, actionID: "shift_frame_left").probability!,
            0.335, accuracy: 1e-12
        )
        XCTAssertEqual(
            first.calibrator.calibratedProbability(rawLogit: 0.8, actionID: "shift_frame_left").probability!,
            0.848, accuracy: 1e-12
        )
        XCTAssertEqual(first.calibrator.calibratedProbability(rawLogit: 1.5, actionID: "shift_frame_left"),
                       .outOfDomain)
        XCTAssertEqual(first.calibrator.calibratedProbability(rawLogit: 0.5, actionID: "unknown_action"),
                       .unavailable)

        // The evidence path keeps the existing producer-provenance contract.
        let evidence = first.calibrator.calibratedEvidence(
            rawScore: 0.8, actionID: "shift_frame_left", inputVersion: .boundedPlanConfidenceV1
        )
        XCTAssertEqual(evidence?.probability ?? .nan, 0.848, accuracy: 1e-12)
        XCTAssertTrue(evidence?.calibrationReference.hasPrefix("cal1:") == true)
        XCTAssertNil(first.calibrator.calibratedEvidence(
            rawScore: 0.8, actionID: "shift_frame_left", inputVersion: .technicalStabilityConfidenceV1
        ))
    }
}
