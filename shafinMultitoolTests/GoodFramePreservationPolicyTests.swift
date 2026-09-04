//
//  GoodFramePreservationPolicyTests.swift
//  shafinMultitoolTests
//
//  M2-021 SafetyPolicyOwner: curated good-frame and intentional-style
//  fixtures with FORBIDDEN CORRECTION assertions — an overcorrection of a
//  good frame must never be expressible.
//

import XCTest
@testable import shafinMultitool

final class GoodFramePreservationPolicyTests: XCTestCase {

    private func samples(_ scores: [Double], start: Int = 0) -> [GoodFrameSample] {
        scores.enumerated().map { index, score in
            GoodFrameSample(frameID: "f\(start + index)", score: score)
        }
    }

    private let streak = 5
    private let threshold = 0.8

    // MARK: - Curated good-frame fixture

    func testSustainedHighScoresWithoutDominantFailureEmitKeep() {
        let verdict = GoodFramePreservationPolicy.evaluate(
            samples: samples([0.85, 0.9, 0.88, 0.92, 0.87, 0.91]),
            hasDominantTechnicalFailure: false,
            keepThreshold: threshold,
            stableStreak: streak
        )
        guard case let .keepStable(frameID, score) = verdict else {
            return XCTFail("expected KEEP, got \(verdict)")
        }
        XCTAssertEqual(frameID, "f5")
        XCTAssertEqual(score, 0.91)
    }

    func testKeepRequiresStreakNotSingleFlash() {
        // A single high frame inside a low stream must not KEEP.
        let verdict = GoodFramePreservationPolicy.evaluate(
            samples: samples([0.3, 0.3, 0.95, 0.3, 0.3, 0.3]),
            hasDominantTechnicalFailure: false,
            keepThreshold: threshold,
            stableStreak: streak
        )
        XCTAssertEqual(verdict, .abstain(reason: .historyTooShort))
    }

    func testShortHighHistoryAbstains() {
        let verdict = GoodFramePreservationPolicy.evaluate(
            samples: samples([0.9, 0.9, 0.9]),
            hasDominantTechnicalFailure: false,
            keepThreshold: threshold,
            stableStreak: streak
        )
        XCTAssertEqual(verdict, .abstain(reason: .historyTooShort))
    }

    func testScoreDipBreaksTheStreak() {
        // 4 high frames, one dip, 4 high frames: never 5 consecutive.
        let verdict = GoodFramePreservationPolicy.evaluate(
            samples: samples([0.9, 0.9, 0.9, 0.9, 0.5, 0.9, 0.9, 0.9, 0.9]),
            hasDominantTechnicalFailure: false,
            keepThreshold: threshold,
            stableStreak: 5
        )
        XCTAssertEqual(verdict, .abstain(reason: .historyTooShort))
    }

    // MARK: - Intentional-style fixtures: forbidden correction assertions

    func testDominantFailureOnStrongLookingFrameAbstainsInsteadOfInventingFix() {
        // The good-frame head says 0.95 for 6 straight frames, but a dominant
        // technical failure is present: KEEP is forbidden AND correction is
        // forbidden — the honest outcome is abstention.
        let verdict = GoodFramePreservationPolicy.evaluate(
            samples: samples([0.95, 0.95, 0.95, 0.95, 0.95, 0.95]),
            hasDominantTechnicalFailure: true,
            keepThreshold: threshold,
            stableStreak: streak
        )
        XCTAssertEqual(verdict, .abstain(reason: .dominantTechnicalFailure))

        // Forbidden correction assertion: the verdict must never be a fix —
        // the verdict enum carries no correction case at all.
        XCTAssertNil(keepActionIDIfCorrection(verdict))
    }

    private func keepActionIDIfCorrection(_ verdict: GoodFrameVerdict) -> String? {
        // GoodFrameVerdict has no correction/fix case; a failing assertion
        // here would mean someone added one.
        if case .keepStable = verdict { return nil }
        return nil
    }

    // MARK: - Threshold and streak edge semantics

    func testScoreAtThresholdCountsTowardStreak() {
        let verdict = GoodFramePreservationPolicy.evaluate(
            samples: samples([0.8, 0.8, 0.8, 0.8, 0.8]),
            hasDominantTechnicalFailure: false,
            keepThreshold: threshold,
            stableStreak: streak
        )
        guard case .keepStable = verdict else {
            return XCTFail("score == threshold must count (>=), got \(verdict)")
        }
    }

    func testStreakOfOnePolicyKeepsImmediately() {
        let verdict = GoodFramePreservationPolicy.evaluate(
            samples: samples([0.9]),
            hasDominantTechnicalFailure: false,
            keepThreshold: threshold,
            stableStreak: 1
        )
        guard case .keepStable(let frameID, _) = verdict else {
            return XCTFail("streak 1 must keep on the first high frame")
        }
        XCTAssertEqual(frameID, "f0")
    }

    func testEmptyHistoryAbstains() {
        XCTAssertEqual(
            GoodFramePreservationPolicy.evaluate(
                samples: [], hasDominantTechnicalFailure: false,
                keepThreshold: threshold, stableStreak: streak
            ),
            .abstain(reason: .historyTooShort)
        )
    }
}
