//
//  CameraAnalysisV3ContractsTests.swift
//  shafinMultitoolTests
//
//  Runbook package C01.a conformance suite for the CameraAnalysis v3 draft
//  contract.  It consumes the SAME fixture document as the independent Python
//  validator (tools/tests/test_camera_analysis_v3_parity.py):
//
//      tools/tests/fixtures/camera_analysis_v3_cases.json          (canonical)
//      shafinMultitoolTests/Fixtures/camera_analysis_v3_cases.json (bundled copy)
//
//  Fixture access: the bundled copy is resolved through Bundle(for:) so the
//  simulator sandbox never needs a host path.  If the resource is not compiled
//  into the test bundle, the test falls back to the canonical copy next to this
//  source file via #filePath and reports which path was used.
//

import XCTest
@testable import shafinMultitool

final class CameraAnalysisV3ContractsTests: XCTestCase {

    private static let fixtureName = "camera_analysis_v3_cases"

    private enum FixtureError: Error {
        case missing
        case malformed
    }

    private struct Case {
        let id: String
        let conformance: String
        let expect: String
        let reason: String
        let body: Any
    }

    private func fixtureURL() throws -> URL {
        var candidates: [Bundle] = [Bundle(for: CameraAnalysisV3ContractsTests.self)]
        candidates.append(contentsOf: Bundle.allBundles)
        candidates.append(Bundle.main)
        for bundle in candidates {
            if let url = bundle.url(forResource: Self.fixtureName, withExtension: "json") {
                return url
            }
        }
        let sourceRelative = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(Self.fixtureName).json")
        if FileManager.default.fileExists(atPath: sourceRelative.path) {
            return sourceRelative
        }
        throw FixtureError.missing
    }

    private func loadCases() throws -> [Case] {
        let url = try fixtureURL()
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawCases = root["cases"] as? [[String: Any]] else {
            throw FixtureError.malformed
        }
        return try rawCases.map { raw in
            guard let id = raw["id"] as? String,
                  let conformance = raw["conformance"] as? String,
                  let expect = raw["expect"] as? String,
                  let reason = raw["reason"] as? String,
                  let body = raw["body"] else {
                throw FixtureError.malformed
            }
            return Case(id: id, conformance: conformance, expect: expect, reason: reason, body: body)
        }
    }

    private func data(for body: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
    }

    private func decode(_ body: Any) throws -> CameraAnalysisV3Envelope {
        try CameraAnalysisV3Contract.decode(try data(for: body))
    }

    private func reason(of error: Error) -> String {
        if let failure = error as? CameraAnalysisV3ValidationFailure {
            return failure.reason.rawValue
        }
        return "unexpected_error:\(error)"
    }

    // MARK: Fixture reachability

    func testFixtureDocumentIsReachableAndWellFormed() throws {
        let url = try fixtureURL()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "fixture document not found via bundle or source fallback")
        let cases = try loadCases()
        XCTAssertGreaterThanOrEqual(cases.filter { $0.expect == "accept" }.count, 20)
        XCTAssertGreaterThanOrEqual(cases.filter { $0.expect == "reject" }.count, 30)
        XCTAssertEqual(Set(cases.map(\.id)).count, cases.count, "fixture ids must be unique")
    }

    func testEveryConformanceTagFromN12IsPresent() throws {
        let tags = Set(try loadCases().map(\.conformance))
        let required: Set<String> = [
            "N12.1_two_lamps_same_label",
            "N12.2_invalid_endpoint",
            "N12.3_region",
            "N12.4_frame_transform",
            "N12.5_same_label_track_swap",
            "N12.6_unknown_operation",
            "N12.7_stale_intent",
            "N12.8_qualified_evidence",
            "N12.9_result_unchanged_worse",
            "N12.10_face_protection",
            "N12.11_sampled_still_temporality",
            "N12.12_record_immutability",
            "N12.13_research_admission",
            "C01.finite_ranges",
            "C01.entity_graph_cycles",
            "C01.enum_payload_combinations",
            "C01.review_no_active_action",
        ]
        XCTAssertTrue(required.isSubset(of: tags), "missing conformance tags: \(required.subtracting(tags))")
    }

    // MARK: Shared fixture parity (accept/reject + exact reason)

    func testAllFixtureCasesMatchExpectedDecisionAndReason() throws {
        var failures: [String] = []
        for testCase in try loadCases() {
            let gotExpect: String
            let gotReason: String
            do {
                _ = try decode(testCase.body)
                gotExpect = "accept"
                gotReason = "ok"
            } catch {
                gotExpect = "reject"
                gotReason = reason(of: error)
            }
            if gotExpect != testCase.expect || gotReason != testCase.reason {
                failures.append("\(testCase.id): expected \(testCase.expect)/\(testCase.reason) got \(gotExpect)/\(gotReason)")
            }
        }
        XCTAssertEqual(failures, [], failures.joined(separator: "\n"))
    }

    // MARK: Typed positive cases (executable types are load-bearing)

    func testTwoLampsWithSameLabelAreDistinguishedByIDNotLabel() throws {
        let envelope = try decode(try body(for: "accept_two_lamps_same_label"))
        XCTAssertEqual(envelope.state, .correct)
        XCTAssertEqual(envelope.phase, .live)
        let lamps = envelope.entities.filter { $0.displayLabel == "lamp" }
        XCTAssertEqual(lamps.count, 2)
        XCTAssertEqual(Set(lamps.map(\.entityID)), ["lampA", "lampB"])
        XCTAssertEqual(Set(lamps.map(\.trackID)), ["ta", "tb"])
        XCTAssertEqual(envelope.activeAction?.targetRefs, ["lampA"])
        XCTAssertEqual(envelope.activeAction?.protectedRefs, ["person1", "lampB"])
        XCTAssertEqual(envelope.activeAction?.operation, "reposition_entity")
        XCTAssertEqual(envelope.activeAction?.effectGoal.desired, .increase)
        XCTAssertEqual(envelope.activeAction?.effectGoal.metricID, "contour_gap")
        XCTAssertEqual(envelope.qualification?.status, "qualified")
        XCTAssertEqual(envelope.qualification?.artifactKind, .production)
    }

    func testPortraitLandscapeMirroringAndOutputCropAreRepresentable() throws {
        let portrait = try decode(try body(for: "accept_portrait_mirrored_crop"))
        XCTAssertEqual(portrait.frameReference.orientation, .portrait)
        XCTAssertTrue(portrait.frameReference.mirrored)
        XCTAssertTrue(portrait.frameReference.outputCrop.contains(
            try XCTUnwrap(portrait.activeAction?.payload.targetRegion)))

        let landscape = try decode(try body(for: "accept_landscape_crop"))
        XCTAssertEqual(landscape.frameReference.orientation, .landscape)
        XCTAssertFalse(landscape.frameReference.mirrored)
    }

    func testSampledFramesRequireAndDecodeMediaTimeIncludingInt64Strings() throws {
        let envelope = try decode(try body(for: "accept_sampled_frames_int64_strings"))
        XCTAssertEqual(envelope.coverage?.kind, .sampledFrames)
        XCTAssertEqual(envelope.coverage?.pts, [0, 1_000_000])
    }

    func testImprovedOutcomeKeepsProtectedFaceUnchanged() throws {
        let envelope = try decode(try body(for: "accept_improved_face_protected"))
        XCTAssertEqual(envelope.verification?.outcome, .improved)
        XCTAssertEqual(envelope.verification?.goalSatisfied, true)
        let protected = try XCTUnwrap(envelope.verification?.protectedDeltas.first)
        XCTAssertEqual(protected.entityRef, "person1")
        XCTAssertEqual(protected.delta, 0.0)
    }

    func testUnchangedAndWorseOutcomesAreDistinctFromImproved() throws {
        XCTAssertEqual(try decode(try body(for: "accept_unchanged_result")).verification?.outcome, .unchanged)
        XCTAssertEqual(try decode(try body(for: "accept_worse_result")).verification?.outcome, .worse)
    }

    func testReviewPhaseCarriesNoActiveAction() throws {
        let envelope = try decode(try body(for: "accept_review_without_action"))
        XCTAssertEqual(envelope.phase, .review)
        XCTAssertNil(envelope.activeAction)
    }

    func testFrozenRecordWithMatchingBaselineDecodes() throws {
        let envelope = try decode(try body(for: "accept_frozen_record_matching"))
        XCTAssertEqual(envelope.record?.frozen, true)
        XCTAssertEqual(envelope.record?.baseline?.actionID, envelope.activeAction?.actionID)
    }

    func testResearchArtifactWithoutAdmissionCannotReachProductionCorrect() throws {
        let research = try decode(try body(for: "accept_research_artifact_abstain"))
        XCTAssertEqual(research.state, .abstain)
        XCTAssertNotEqual(research.state, .correct)
        XCTAssertNil(research.activeAction)

        let error = assertRejects(try body(for: "reject_research_without_admission"))
        XCTAssertEqual(reason(of: error), "research_not_admitted")
    }

    // MARK: Negative cases with concrete reasons

    @discardableResult
    private func assertRejects(_ body: Any, file: StaticString = #filePath, line: UInt = #line) -> Error {
        do {
            _ = try decode(body)
            XCTFail("expected rejection", file: file, line: line)
            return FixtureError.malformed
        } catch {
            return error
        }
    }

    func testUnknownOperationAndUnknownEnumsAreRejectedNotDefaulted() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_unknown_operation"))), "unknown_operation")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_unknown_state"))), "unknown_enum_value")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_invalid_action_payload_unknown_enum"))), "unknown_enum_value")
    }

    func testNegativeAndNonFiniteRegionsAreRejectedNotClampedToZero() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_region_negative"))), "region_out_of_range")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_region_nan"))), "region_non_finite")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_region_degenerate"))), "region_degenerate")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_region_not_numeric"))), "region_not_numeric")
    }

    func testInvalidEndpointAndSameLabelTrackSwapAreRejected() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_relation_endpoint_missing"))), "relation_endpoint_missing")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_entity_reference_missing"))), "entity_reference_missing")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_label_not_identity"))), "label_not_identity")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_same_label_track_swap"))), "identity_lost")
    }

    func testStaleIntentRevisionIsRejected() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_stale_intent_revision"))), "stale_intent_revision")
    }

    func testQualifiedVsUnknownEvidenceBoundary() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_unqualified_evidence"))), "unqualified_evidence")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_missing_qualification"))), "missing_qualification")
        let unknownEvidence = try decode(try body(for: "accept_unknown_evidence_abstain"))
        XCTAssertEqual(unknownEvidence.state, .abstain)
        XCTAssertEqual(unknownEvidence.evidence.first?.qualificationStatus, .unknown)
    }

    func testUnchangedOrWorseResultCannotClaimImprovement() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_improved_without_delta"))),
                       "claimed_improvement_without_delta")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_protected_regression"))),
                       "protected_regression")
    }

    func testSampledStillWithoutTemporalEvidenceIsRejected() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_sampled_still_without_t"))),
                       "missing_temporal_evidence")
    }

    func testRecordImmutabilityIsEnforced() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_frozen_record_mutation"))),
                       "frozen_record_mutation")
    }

    func testSchemaVersionAndEnumPayloadCombinations() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_schema_version_mismatch"))),
                       "schema_version_mismatch")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_invalid_action_payload_screen_goal"))),
                       "invalid_action_payload")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_invalid_action_payload_small_probe_angle"))),
                       "invalid_action_payload")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_invalid_action_payload_measured_no_angle"))),
                       "invalid_action_payload")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_invalid_action_payload_bool_vs_number"))),
                       "invalid_action_payload")
    }

    func testEntityGraphCyclesAndDuplicateIDsAreRejected() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_entity_graph_cycle"))), "entity_graph_cycle")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_duplicate_entity_id"))), "duplicate_entity_id")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_duplicate_relation_id"))), "duplicate_relation_id")
    }

    func testReviewPhaseWithActionAndStateConflictsAreRejected() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_review_state_with_action"))),
                       "review_state_with_action")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_state_action_conflict"))),
                       "state_action_conflict")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_selection_candidates_conflict"))),
                       "selection_candidates_conflict")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_select_subject_empty_candidates"))),
                       "selection_candidates_conflict")
    }

    func testFrameAndTransformReferenceFailures() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_transform_reference_missing"))),
                       "transform_reference_missing")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_output_crop_mismatch"))),
                       "output_crop_mismatch")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_orientation_mismatch"))),
                       "orientation_mismatch")
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_mirroring_mismatch"))),
                       "mirroring_mismatch")
    }

    func testInvalidJSONIsRejected() throws {
        XCTAssertEqual(reason(of: assertRejects(try body(for: "reject_invalid_json"))), "invalid_json")
    }

    func testSelectionStatesCarryNoAction() throws {
        let select = try decode(try body(for: "accept_select_subject_candidates"))
        XCTAssertEqual(select.state, .selectSubject)
        XCTAssertEqual(select.selectionCandidates, ["lampA", "lampB"])
        XCTAssertNil(select.activeAction)

        XCTAssertEqual(try decode(try body(for: "accept_keep_no_action")).state, .keep)
        XCTAssertEqual(try decode(try body(for: "accept_wait_no_action")).state, .wait)
    }

    // MARK: Helpers

    private func body(for id: String) throws -> Any {
        guard let match = try loadCases().first(where: { $0.id == id }) else {
            throw FixtureError.missing
        }
        return match.body
    }
}
