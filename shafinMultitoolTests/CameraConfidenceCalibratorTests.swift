//
//  CameraConfidenceCalibratorTests.swift
//  shafinMultitoolTests
//
//  M2-018 CalibrationOwner: calibration table fixtures, monotonicity, ECE
//  calculation, selective-risk abstention, and the raw-logit containment
//  guarantee (raw logits never reach UI-facing outcomes).
//

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
}
