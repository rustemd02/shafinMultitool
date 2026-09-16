//
//  SETCompositionNetScorerTests.swift
//  shafinMultitool
//
//  Integration guard for the locally trained SETCompositionNet candidate:
//  the artifact must load from the app bundle and declare exactly the frozen
//  v1 IO contract, and the loader must fail closed when the artifact is
//  missing or the inputs are incomplete.
//

import XCTest
@testable import shafinMultitool

final class SETCompositionNetScorerTests: XCTestCase {

    func testCandidateLoadsAndDeclaresTheFrozenIOContract() throws {
        let scorer = SETCompositionNetScorer()
        guard scorer.isAvailable else {
            throw XCTSkip("SETCompositionNet-Stage2-Local artifact is not present in this bundle")
        }
        let io = try XCTUnwrap(scorer.declaredIO())
        XCTAssertEqual(
            io.inputs,
            Set(SETCompositionNetInputName.allCases.map(\.rawValue)),
            "candidate inputs drifted from the frozen contract"
        )
        XCTAssertEqual(
            io.outputs,
            Set(SETCompositionNetOutputName.allCases.map(\.rawValue)),
            "candidate outputs drifted from the frozen contract"
        )
    }

    func testPredictFailsClosedWithIncompleteInputs() throws {
        let scorer = SETCompositionNetScorer()
        guard scorer.isAvailable else {
            throw XCTSkip("SETCompositionNet-Stage2-Local artifact is not present in this bundle")
        }
        XCTAssertNil(
            scorer.predict(features: [:]),
            "an incomplete feature set must return nil, never fabricated scores"
        )
    }
}
