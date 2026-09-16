//
//  CaptureIntentFeatureParityTests.swift
//  shafinMultitoolTests
//
//  M00b Swift <-> Python parity for the SETCompositionNet-v2 intent input.
//
//  Both implementations read the SAME canonical fixture:
//
//      ml/camera_coach/contracts/fixtures/set_composition_net_v2_intent_parity.json
//
//  Python: ml/camera_coach/tests/test_set_composition_net_v2.py
//  Swift:  this file (resolved from #filePath; no bundled copy that could drift).
//
//  The suite proves order, dtype semantics, unknown != natural, multi-style
//  preservation, invalid-vector rejection, supervision masking, the
//  CameraStyleCue -> CaptureStyle mapping, and that intent never occupies the
//  inherited 40 scalar slots.
//

import CoreML
import XCTest
@testable import shafinMultitool

final class CaptureIntentFeatureParityTests: XCTestCase {

    private enum FixtureError: Error {
        case missing
        case malformed
    }

    // MARK: - Fixture access

    /// `.../shafinMultitoolTests/CaptureIntentFeatureParityTests.swift`
    ///  -> repo root -> ml/camera_coach/contracts/fixtures/...
    private func fixtureURL() throws -> URL {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<4 {
            let candidate = directory
                .appendingPathComponent("ml/camera_coach/contracts/fixtures/set_composition_net_v2_intent_parity.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        throw FixtureError.missing
    }

    private func loadFixture() throws -> [String: Any] {
        let data = try Data(contentsOf: try fixtureURL())
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixtureError.malformed
        }
        return root
    }

    private func doubleArray(_ value: Any?) -> [Double] {
        (value as? [Any])?.compactMap { ($0 as? NSNumber)?.doubleValue } ?? []
    }

    private func styleNames(_ value: Any?) -> [String] {
        if value is NSNull { return [] }
        return (value as? [String]) ?? []
    }

    // MARK: - Manifest order and encoding parity

    func testFixtureIsReachableAndOrderMatchesManifest() throws {
        let fixture = try loadFixture()
        XCTAssertEqual(fixture["contract_version"] as? String, "setcompositionnet.v2")
        XCTAssertEqual(fixture["input_contract_version"] as? String,
                       CaptureIntentFeatureContract.inputContractVersion)
        XCTAssertEqual(styleNames(fixture["intent_order"]), CaptureIntentFeatureContract.orderedNames)
        XCTAssertEqual(fixture["known_flag_index"] as? Int, CaptureIntentFeatureContract.knownFlagIndex)
        XCTAssertEqual(CaptureIntentFeatureContract.orderedNames.count, 9)
        XCTAssertEqual(CaptureIntentFeatureContract.styleFlagNames.count, 8)
        XCTAssertEqual(CaptureStyle.allCases.map(\.rawValue), CaptureIntentFeatureContract.styleFlagNames)
    }

    func testEncodingCasesMatchFixtureExactly() throws {
        let fixture = try loadFixture()
        let cases = try XCTUnwrap(fixture["encoding_cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let caseId = try XCTUnwrap(item["case_id"] as? String)
            let encoded = try CaptureIntentFeatureContract.encode(styleNames: styleNames(item["styles"]))
            XCTAssertEqual(encoded.count, 9, caseId)
            XCTAssertEqual(encoded, doubleArray(item["expected"]), caseId)
        }
    }

    func testInvalidVectorsAreRejected() throws {
        let fixture = try loadFixture()
        let cases = try XCTUnwrap(fixture["invalid_cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let caseId = try XCTUnwrap(item["case_id"] as? String)
            let vector = doubleArray(item["vector"])
            XCTAssertFalse(CaptureIntentFeatureContract.validate(vector).isEmpty,
                           "invalid vector accepted: \(caseId)")
        }
        // The known=1 / empty-styles case is also rejected at encode time.
        XCTAssertThrowsError(try CaptureIntentFeatureContract.encodeExplicit(styleNames: [])) { error in
            XCTAssertEqual(error as? CaptureIntentFeatureEncodingError, .emptyExplicitSelection)
        }
    }

    // MARK: - Unknown vs explicit natural

    func testUnknownIsNeverEncodedAsNatural() throws {
        let unknown = try CaptureIntentFeatureContract.encode(styleNames: [])
        XCTAssertEqual(unknown, Array(repeating: 0.0, count: 9))
        XCTAssertEqual(unknown[CaptureIntentFeatureContract.knownFlagIndex], 0.0)
        XCTAssertEqual(unknown[0], 0.0, "unknown must not be filled with natural")

        let natural = try CaptureIntentFeatureContract.encode(styleNames: ["natural"])
        XCTAssertEqual(natural[0], 1.0)
        XCTAssertEqual(natural[CaptureIntentFeatureContract.knownFlagIndex], 1.0)
        XCTAssertNotEqual(unknown, natural)

        // The forbidden placeholder is rejected at the tensor boundary.
        let unknownAsNatural = [1.0, 0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertFalse(CaptureIntentFeatureContract.validate(unknownAsNatural).isEmpty)
    }

    func testPairedDistinctnessMatchesFixture() throws {
        let fixture = try loadFixture()
        let cases = try XCTUnwrap(fixture["paired_distinctness_cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let caseId = try XCTUnwrap(item["case_id"] as? String)
            let left = try CaptureIntentFeatureContract.encode(styleNames: styleNames(item["left_styles"]))
            let right = try CaptureIntentFeatureContract.encode(styleNames: styleNames(item["right_styles"]))
            let differing = (0..<9).filter { left[$0] != right[$0] }
            XCTAssertEqual(differing, (item["expected_differing_indices"] as? [Any])?
                .compactMap { ($0 as? NSNumber)?.intValue }, caseId)
        }
    }

    func testSupervisionMaskCasesMatchFixture() throws {
        let fixture = try loadFixture()
        let cases = try XCTUnwrap(fixture["supervision_mask_cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        for item in cases {
            let caseId = try XCTUnwrap(item["case_id"] as? String)
            let intent = try CaptureIntentFeatureContract.encode(styleNames: styleNames(item["styles"]))
            let roiPresent = (item["roi_present"] as? NSNumber)?.boolValue ?? false
            let mask = CaptureIntentFeatureContract.supervisionMask(
                intentFeatures: intent,
                roiPresent: roiPresent
            )
            XCTAssertEqual(mask, doubleArray(item["expected"]), caseId)
        }
    }

    // MARK: - CameraStyleCue -> CaptureStyle mapping

    func testCameraStyleCueMappingTable() {
        XCTAssertEqual(CameraStyleCue.lowKey.captureStyle, .lowKey)
        XCTAssertEqual(CameraStyleCue.silhouette.captureStyle, .silhouette)
        XCTAssertEqual(CameraStyleCue.symmetry.captureStyle, .symmetry)
        XCTAssertEqual(CameraStyleCue.negativeSpace.captureStyle, .negativeSpace)
        // Documented inexact pairs: a defect look is not proof of intent.
        XCTAssertEqual(CameraStyleCue.tilt.captureStyle, .dutchAngle)
        XCTAssertFalse(CameraStyleCue.tilt.captureStyleMapping.isExactSemanticMatch)
        XCTAssertEqual(CameraStyleCue.motionBlur.captureStyle, .intentionalMotionBlur)
        XCTAssertFalse(CameraStyleCue.motionBlur.captureStyleMapping.isExactSemanticMatch)

        // Styles outside the cue-detectable set are explicit-only and never
        // silently inferred: natural and handheld have no cue candidate.
        XCTAssertNil(CaptureStyle.natural.detectedCueCandidate)
        XCTAssertNil(CaptureStyle.handheld.detectedCueCandidate)
        XCTAssertEqual(CaptureStyle.lowKey.detectedCueCandidate, .lowKey)
        XCTAssertEqual(CaptureStyle.dutchAngle.detectedCueCandidate, .tilt)
        XCTAssertEqual(CameraStyleCue.allCases.count, 6)
        XCTAssertEqual(CaptureStyle.allCases.count, 8)

        // A style name outside the manifest set is rejected, not coerced.
        XCTAssertThrowsError(try CaptureIntentFeatureContract.encode(styleNames: ["tilt"])) { error in
            XCTAssertEqual(error as? CaptureIntentFeatureEncodingError, .unknownStyle("tilt"))
        }
    }

    // MARK: - CaptureIntent domain type

    func testCaptureIntentUnknownAndExplicitNaturalEncodeDistinctly() throws {
        let unknown = CaptureIntent.unknown(intentRevision: 7)
        XCTAssertTrue(unknown.validate().isEmpty)
        XCTAssertEqual(try unknown.intentFeatures(), Array(repeating: 0.0, count: 9))

        let natural = CaptureIntent(selection: .user, styles: [.natural], intentRevision: 7)
        let naturalVector = try natural.intentFeatures()
        let unknownVector = try unknown.intentFeatures()
        XCTAssertEqual(unknownVector[0], 0.0)
        XCTAssertEqual(naturalVector[0], 1.0)
        XCTAssertEqual(naturalVector[CaptureIntentFeatureContract.knownFlagIndex], 1.0)
        XCTAssertNotEqual(unknownVector, naturalVector)
        // Only natural and known differ.
        let differing = (0..<9).filter { unknownVector[$0] != naturalVector[$0] }
        XCTAssertEqual(differing, [0, 8])
    }

    func testCaptureIntentPreservesMultipleStyles() throws {
        let intent = CaptureIntent(
            selection: .user,
            styles: [.silhouette, .negativeSpace],
            intentRevision: 1
        )
        let vector = try intent.intentFeatures()
        XCTAssertEqual(CaptureIntentFeatureContract.selectedStyleNames(in: vector),
                       ["silhouette", "negative_space"])
        XCTAssertEqual(vector[CaptureIntentFeatureContract.knownFlagIndex], 1.0)
        XCTAssertTrue(intent.validate().isEmpty)
    }

    func testIntentRevisionIncrementsOnlyOnRealChange() {
        let base = CaptureIntent.unknown(intentRevision: 3)
        XCTAssertEqual(base.selecting(.user).intentRevision, 4)
        XCTAssertEqual(base.withStyles([.handheld]).intentRevision, 4)
        XCTAssertEqual(base.withSubjectRefs(["s1"]).intentRevision, 4)

        // No-op mutations keep the revision.
        XCTAssertEqual(base.selecting(.unknown).intentRevision, 3)
        XCTAssertEqual(base.withStyles([]).intentRevision, 3)

        // Group requires at least two members and unknown forbids subjects.
        let shortGroup = CaptureIntent(selection: .group, subjectRefs: ["s1"], intentRevision: 1)
        XCTAssertFalse(shortGroup.validate().isEmpty)
        let subjectsUnderUnknown = CaptureIntent(selection: .unknown, subjectRefs: ["s1"], intentRevision: 1)
        XCTAssertFalse(subjectsUnderUnknown.validate().isEmpty)
    }

    // MARK: - Scalar-slot isolation and v2 assembly

    func testIntentDoesNotOccupyInheritedScalarSlots() {
        XCTAssertEqual(SETCompositionNetContract.scalarFeatureCount, 40)
        XCTAssertEqual(SETCompositionNetInputName.allCases.count, 6)
        XCTAssertFalse(SETCompositionNetInputName.allCases
            .map(\.rawValue)
            .contains(CaptureIntentFeatureContract.intentFeatureName))
        XCTAssertTrue(Set(CaptureIntentFeatureContract.orderedNames)
            .isDisjoint(with: Set(SETCompositionNetContract.featureNames)))
    }

    func testV2InputAssemblyValidatesAndKeepsV1PayloadIntact() throws {
        let base = makeValidV1Tensors()
        XCTAssertTrue(base.validate().isEmpty, "base v1 payload must validate: \(base.validate())")

        let known = try SETCompositionNetV2InputTensors(base: base, intent: CaptureIntent(
            selection: .user,
            styles: [.lowKey, .handheld],
            intentRevision: 2
        ))
        XCTAssertTrue(known.validate().isEmpty, "valid v2 payload: \(known.validate())")
        XCTAssertEqual(known.scalarFeatures, base.scalarFeatures)
        XCTAssertEqual(known.intentFeatures, [0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0])

        let unknown = try SETCompositionNetV2InputTensors(base: base, intent: .unknown())
        XCTAssertEqual(unknown.intentFeatures, Array(repeating: 0.0, count: 9))

        let invalid = SETCompositionNetV2InputTensors(
            base: base,
            intentFeatures: [1.0, 0, 0, 0, 0, 0, 0, 0, 0]
        )
        XCTAssertFalse(invalid.validate().isEmpty, "unknown encoded as natural must fail assembly validation")
    }

    func testV2ScorerSeamFailsClosedWithoutAnExportedModel() throws {
        let scorer = SETCompositionNetScorer()
        if scorer.isAvailable {
            // The bundled research candidate is v1 and must not claim v2 intent.
            XCTAssertFalse(scorer.declaresV2IntentInput)
        }
        let intent = try CaptureIntentFeatureContract.encode(styles: [.silhouette])
        XCTAssertNil(
            scorer.predictV2(baseFeatures: [:], intentFeatures: intent),
            "no v2 artifact exists; predictV2 must return nil, never a fabricated score"
        )
    }

    // MARK: - Helpers

    private func makeValidV1Tensors() -> SETCompositionNetInputTensors {
        SETCompositionNetInputTensors(
            fullFrameRGB: Array(
                repeating: 0.0,
                count: SETCompositionNetContract.fullFrameWidth
                    * SETCompositionNetContract.fullFrameHeight * 3
            ),
            subjectCropRGB: Array(
                repeating: 0.0,
                count: SETCompositionNetContract.subjectCropWidth
                    * SETCompositionNetContract.subjectCropHeight * 3
            ),
            roi: SETCompositionNetROI(x: 0, y: 0, width: 0, height: 0, present: false),
            roiMask: Array(
                repeating: 0.0,
                count: SETCompositionNetContract.roiMaskWidth * SETCompositionNetContract.roiMaskHeight
            ),
            scalarFeatures: Array(repeating: 0.0, count: SETCompositionNetContract.scalarFeatureCount),
            missingFeatureMask: Array(repeating: 0.0, count: SETCompositionNetContract.scalarFeatureCount)
        )
    }
}
