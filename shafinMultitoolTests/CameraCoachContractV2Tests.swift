//
//  CameraCoachContractV2Tests.swift
//  shafinMultitoolTests
//
//  M2-001 CameraCoachDomainOwner: the fixed production Camera Coach decision
//  contract. Round-trip, exhaustiveness, legacy migration and fail-closed
//  behavior are pinned here; the JSON artifact must stay in lockstep with the
//  in-code contract.
//

import XCTest
@testable import shafinMultitool

final class CameraCoachContractV2Tests: XCTestCase {

    private let contract = CameraCoachContractV2.production

    // MARK: - Fixed decision space

    func testDecisionSpaceIsExactlyTheFiveProductionDecisions() {
        XCTAssertEqual(
            Set(CameraCoachDecisionV2.allCases.map(\.rawValue)),
            ["KEEP", "CORRECT", "SELECT_SUBJECT", "WAIT", "ABSTAIN"]
        )
        XCTAssertEqual(contract.decisions, CameraCoachDecisionV2.allCases.map(\.rawValue))
        XCTAssertEqual(contract.contractVersion, 2)
    }

    func testDecisionCodableRoundTrip() throws {
        for decision in CameraCoachDecisionV2.allCases {
            let data = try JSONEncoder().encode(decision)
            let decoded = try JSONDecoder().decode(CameraCoachDecisionV2.self, from: data)
            XCTAssertEqual(decoded, decision)
            XCTAssertEqual(String(data: data, encoding: .utf8), "\"\(decision.rawValue)\"")
        }
    }

    func testContractCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(contract)
        let decoded = try JSONDecoder().decode(CameraCoachContractV2.self, from: data)
        XCTAssertEqual(decoded, contract)
    }

    // MARK: - Approved action catalog

    func testApprovedActionIDsAreExactlyTheCanonicalSemanticCatalog() {
        XCTAssertEqual(
            Set(contract.approvedActionIDs),
            Set(SemanticActionType.allCases.map(\.rawValue)),
            "the approved action ID list must track the canonical semantic catalog"
        )
        XCTAssertTrue(contract.isApprovedActionID("keep_current_setup"))
        XCTAssertFalse(contract.isApprovedActionID("vibe_it_up"))
    }

    // MARK: - Legacy migration mapping (exhaustive, table-driven)

    func testEveryLegacyActionHasExactlyOneMigration() {
        let legacyIDs = ActionTypeV1.allCases.map(\.rawValue)
        XCTAssertEqual(
            Set(contract.legacyMigrations.map(\.legacyActionID)),
            Set(legacyIDs),
            "the migration table must cover every legacy action exactly once"
        )
        XCTAssertEqual(contract.legacyMigrations.count, legacyIDs.count)
    }

    func testLegacyMigrationsTargetApprovedActionsAndValidDecisions() {
        for migration in contract.legacyMigrations {
            XCTAssertTrue(
                contract.isApprovedActionID(migration.approvedActionID),
                "\(migration.legacyActionID) must migrate to an approved action"
            )
            XCTAssertTrue(
                CameraCoachDecisionV2.allCases.map(\.rawValue).contains(migration.decision.rawValue)
            )
        }
    }

    func testLegacyActionMigrationTable() {
        let expected: [(ActionTypeV1, CameraCoachDecisionV2, SemanticActionType)] = [
            (.moveFrameLeft, .correct, .shiftFrameLeft),
            (.moveFrameRight, .correct, .shiftFrameRight),
            (.moveFrameUp, .correct, .shiftFrameUp),
            (.moveFrameDown, .correct, .shiftFrameDown),
            (.increaseSubjectSize, .correct, .stepCloser),
            (.reduceBackgroundDistractions, .correct, .simplifyBackground),
            (.changeAngle, .correct, .changeCameraAngle),
            (.improveFrontLight, .correct, .addFrontFillLight),
            (.levelHorizon, .correct, .levelHorizon),
            (.leaveFrameAsIs, .keep, .keepCurrentSetup),
        ]

        for (legacy, decision, approved) in expected {
            let migration = contract.migration(forLegacyActionID: legacy.rawValue)
            XCTAssertEqual(migration?.decision, decision, "\(legacy.rawValue) decision")
            XCTAssertEqual(migration?.approvedActionID, approved.rawValue, "\(legacy.rawValue) action")
            XCTAssertEqual(contract.decision(forLegacyActionID: legacy.rawValue), decision)
        }
    }

    // MARK: - Fail-closed behavior

    func testUnknownLegacyActionFailsClosedToWait() {
        XCTAssertEqual(contract.decision(forLegacyActionID: "vibes_from_2019"), .wait)
        XCTAssertEqual(contract.decision(forLegacyActionID: ""), .wait)
        XCTAssertNil(contract.migration(forLegacyActionID: "vibes_from_2019"))
    }

    func testFailClosedPolicyTargets() {
        let policy = contract.failClosedPolicy
        XCTAssertEqual(policy.missingOrUnstableEvidence, .wait)
        XCTAssertEqual(policy.resolvableSubjectAmbiguity, .selectSubject)
        XCTAssertEqual(policy.insufficientEvidence, .abstain)
        XCTAssertEqual(policy.unknownLegacyAction, .wait)
    }

    // MARK: - JSON artifact lockstep

    func testJSONArtifactMatchesInCodeContract() throws {
        let artifactURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/implementation/camera-coach-contract-v2.json")
        let data = try Data(contentsOf: artifactURL)
        let decoded = try JSONDecoder().decode(CameraCoachContractV2.self, from: data)
        XCTAssertEqual(decoded, contract, "the published artifact must equal the in-code contract")
    }
}
