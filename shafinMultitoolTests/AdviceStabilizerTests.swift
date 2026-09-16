//
//  AdviceStabilizerTests.swift
//  shafinMultitoolTests
//
//  M2-022 AdviceTemporalOwner: clock-controlled jitter and scene-change
//  sequences — advice changes at most once per cooldown, brief jitter does
//  not flicker, invalidation removes advice immediately.
//

import XCTest
@testable import shafinMultitool

final class AdviceStabilizerTests: XCTestCase {

    private final class ScriptedClock {
        private(set) var now: Date
        private let step: TimeInterval

        init(start: TimeInterval = 50_000, step: TimeInterval = 1.0) {
            self.now = Date(timeIntervalSince1970: start)
            self.step = step
        }

        func tick() -> Date {
            now = now.addingTimeInterval(step)
            return now
        }
    }

    private func decision(_ kind: CameraCoachDecisionV2,
                          action: String? = nil,
                          frame: Int = 0,
                          targetIdentity: SubjectTrackIdentity? = nil) -> CameraPlannerDecision {
        CameraPlannerDecision(
            decision: kind,
            actionID: action,
            frameID: "f\(frame)",
            calibratedProbability: 0.9,
            targetPoint: action != nil ? (0.5, 0.5) : nil,
            blockReason: nil,
            targetIdentity: targetIdentity
        )
    }

    private let targetA = SubjectTrackIdentity(
        trackID: "target-a",
        firstSeenFrameID: "f-a",
        generation: 7
    )
    private let targetB = SubjectTrackIdentity(
        trackID: "target-b",
        firstSeenFrameID: "f-b",
        generation: 7
    )

    private func stabilizer(clock: @escaping () -> Date,
                            cooldown: TimeInterval = 3.0,
                            hysteresis: Int = 3) -> AdviceStabilizer {
        AdviceStabilizer(cooldownSeconds: cooldown, hysteresisFrames: hysteresis, clock: clock)
    }

    // MARK: - Dwell: first advice needs hysteresis

    func testFirstCorrectionNeedsHysteresisFrames() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() })

        // Two frames of CORRECT: below the 3-frame dwell, nothing published.
        XCTAssertNil(stabilizer.observe(decision(.correct, action: "a", frame: 0)).map { $0.decision })
        XCTAssertNil(stabilizer.currentAdvice)
        XCTAssertNil(stabilizer.observe(decision(.correct, action: "a", frame: 1)).map { $0.decision })
        XCTAssertNil(stabilizer.currentAdvice)
        // Third frame publishes.
        let published = stabilizer.observe(decision(.correct, action: "a", frame: 2))
        XCTAssertEqual(published?.decision, .correct)
        XCTAssertEqual(stabilizer.currentAdvice?.actionID, "a")
    }

    func testSameSemanticActionRefreshesCurrentFrameProvenance() {
        let clock = ScriptedClock()
        var stabilizer = stabilizer(clock: { clock.tick() })

        for frame in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: frame))
        }
        XCTAssertEqual(stabilizer.currentAdvice?.frameID, "f2")

        let refreshed = stabilizer.observe(decision(.correct, action: "a", frame: 99))
        XCTAssertEqual(refreshed?.actionID, "a")
        XCTAssertEqual(refreshed?.frameID, "f99")
        XCTAssertEqual(stabilizer.currentAdvice?.frameID, "f99")
    }

    func testSameTargetIdentityRefreshesCurrentFrameProvenance() {
        let clock = ScriptedClock()
        var stabilizer = stabilizer(clock: { clock.tick() })

        for frame in 0..<3 {
            _ = stabilizer.observe(decision(
                .correct,
                action: "a",
                frame: frame,
                targetIdentity: targetA
            ))
        }

        let refreshed = stabilizer.observe(decision(
            .correct,
            action: "a",
            frame: 99,
            targetIdentity: targetA
        ))
        XCTAssertEqual(refreshed?.frameID, "f99")
        XCTAssertEqual(refreshed?.targetIdentity, targetA)
    }

    func testPendingTargetChangeResetsHysteresis() {
        let clock = ScriptedClock()
        var stabilizer = stabilizer(clock: { clock.tick() })

        _ = stabilizer.observe(decision(.correct, action: "a", frame: 0, targetIdentity: targetA))
        _ = stabilizer.observe(decision(.correct, action: "a", frame: 1, targetIdentity: targetA))
        XCTAssertNil(stabilizer.currentAdvice)

        _ = stabilizer.observe(decision(.correct, action: "a", frame: 2, targetIdentity: targetB))
        _ = stabilizer.observe(decision(.correct, action: "a", frame: 3, targetIdentity: targetB))
        XCTAssertNil(stabilizer.currentAdvice)
        let published = stabilizer.observe(decision(.correct, action: "a", frame: 4, targetIdentity: targetB))
        XCTAssertEqual(published?.targetIdentity, targetB)
    }

    func testPublishedTargetChangeRemovesOldAdviceImmediatelyAndRequiresFreshDwell() {
        let clock = ScriptedClock()
        var stabilizer = stabilizer(clock: { clock.tick() }, cooldown: 60.0)

        for frame in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: frame, targetIdentity: targetA))
        }
        XCTAssertEqual(stabilizer.currentAdvice?.targetIdentity, targetA)

        XCTAssertNil(stabilizer.observe(decision(.correct, action: "a", frame: 3, targetIdentity: targetB)))
        XCTAssertNil(stabilizer.currentAdvice)
        XCTAssertNil(stabilizer.observe(decision(.correct, action: "a", frame: 4, targetIdentity: targetB)))
        XCTAssertEqual(
            stabilizer.observe(decision(.correct, action: "a", frame: 5, targetIdentity: targetB))?.targetIdentity,
            targetB
        )
    }

    func testNonCorrectionDecisionPublishesImmediately() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() })

        let published = stabilizer.observe(decision(.wait, frame: 0))
        XCTAssertEqual(published?.decision, .wait)
    }

    // MARK: - Jitter: brief alternation must not flicker advice

    func testBriefJitterDoesNotChangePublishedAdvice() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() })

        // Publish CORRECT(a).
        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0))
            _ = now()
        }
        XCTAssertEqual(stabilizer.currentAdvice?.actionID, "a")

        // Two frames of jitter toward WAIT: below the 3-frame hysteresis.
        _ = stabilizer.observe(decision(.wait, frame: 3))
        _ = now()
        _ = stabilizer.observe(decision(.wait, frame: 4))
        _ = now()

        XCTAssertEqual(stabilizer.currentAdvice?.decision, .correct,
                       "brief jitter must not flicker the published advice")
    }

    // MARK: - Cooldown: change at most once per window

    func testAdviceChangesAtMostOncePerCooldownWindow() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() }, cooldown: 10.0, hysteresis: 3)

        // Publish CORRECT(a) at t≈3.
        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0))
            _ = now()
        }
        let firstChange = clock.now

        // Sustained CORRECT(b) for 6 more seconds (hysteresis met well before
        // the cooldown expires): the published advice must stay "a" while the
        // cooldown runs, then flip once.
        var flippedAt: Date?
        for index in 0..<12 {
            let presented = stabilizer.observe(decision(.correct, action: "b", frame: 10 + index))
            _ = now()
            if presented?.actionID == "b", flippedAt == nil {
                flippedAt = clock.now
            }
        }
        XCTAssertEqual(stabilizer.currentAdvice?.actionID, "b")
        guard let flippedAt else {
            return XCTFail("expected a single flip within the window")
        }
        XCTAssertGreaterThanOrEqual(
            flippedAt.timeIntervalSince(firstChange),
            10.0 - 0.001,
            "the flip must not happen before the cooldown expires"
        )
    }

    // MARK: - Material change: immediate removal

    func testMaterialChangeRemovesAdviceImmediatelyBypassingCooldown() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() }, cooldown: 60.0, hysteresis: 3)

        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0))
            _ = now()
        }
        XCTAssertNotNil(stabilizer.currentAdvice)

        // Scene cut / lens change / generation change: immediate removal even
        // though the 60 s cooldown has not run.
        let removed = stabilizer.invalidate(frameID: "fCut", reason: "scene_cut")
        XCTAssertEqual(removed?.actionID, "a")
        XCTAssertNil(stabilizer.currentAdvice)
    }

    func testAdviceAfterInvalidationPublishesWithoutCooldownDebt() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() }, cooldown: 60.0, hysteresis: 3)

        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0))
            _ = now()
        }
        _ = stabilizer.invalidate(frameID: "fCut", reason: "scene_cut")

        // Fresh episode: the new advice publishes after hysteresis only, with
        // no cooldown debt from the removed advice.
        var published: StabilizedAdvice?
        for index in 0..<3 {
            published = stabilizer.observe(decision(.correct, action: "b", frame: 10 + index))
            _ = now()
        }
        XCTAssertEqual(published?.actionID, "b")
        XCTAssertEqual(stabilizer.currentAdvice?.actionID, "b")
    }

    func testInvalidationClearsPendingTargetState() {
        let clock = ScriptedClock()
        var stabilizer = stabilizer(clock: { clock.tick() }, cooldown: 60.0)

        _ = stabilizer.observe(decision(.correct, action: "a", frame: 0, targetIdentity: targetA))
        _ = stabilizer.observe(decision(.correct, action: "a", frame: 1, targetIdentity: targetA))
        _ = stabilizer.invalidate(frameID: "fCut", reason: "scene_cut")

        _ = stabilizer.observe(decision(.correct, action: "a", frame: 2, targetIdentity: targetA))
        _ = stabilizer.observe(decision(.correct, action: "a", frame: 3, targetIdentity: targetA))
        XCTAssertNil(stabilizer.currentAdvice)
        XCTAssertEqual(
            stabilizer.observe(decision(.correct, action: "a", frame: 4, targetIdentity: targetA))?.targetIdentity,
            targetA
        )
    }

    // MARK: - Scene-change sequence (end to end)

    func testSceneChangeSequenceMatchesSpec() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() }, cooldown: 3.0, hysteresis: 3)

        // Advice A publishes.
        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0))
            _ = now()
        }
        // Jitter: two frames of B — suppressed.
        _ = stabilizer.observe(decision(.correct, action: "b", frame: 3))
        _ = now()
        _ = stabilizer.observe(decision(.correct, action: "b", frame: 4))
        _ = now()
        XCTAssertEqual(stabilizer.currentAdvice?.actionID, "a")

        // Sustained B after the cooldown expires: flips once.
        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "b", frame: 5))
            _ = now()
        }
        XCTAssertEqual(stabilizer.currentAdvice?.actionID, "b")

        // Scene cut: immediate removal.
        _ = stabilizer.invalidate(frameID: "fCut", reason: "scene_cut")
        XCTAssertNil(stabilizer.currentAdvice)
    }

    // MARK: - C05 user dismissal (cancel is not a quality verdict)

    func testDismissedAdviceIsNotImmediatelyReturned() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() }, cooldown: 3.0, hysteresis: 3)

        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0))
            _ = now()
        }
        XCTAssertEqual(stabilizer.currentAdvice?.actionID, "a")

        // User declines the advice: it is removed and suppressed.
        _ = stabilizer.dismiss(actionID: "a", targetIdentity: nil)
        XCTAssertNil(stabilizer.currentAdvice)
        XCTAssertTrue(stabilizer.isDismissed)

        // Even with sustained identical evidence, the same unfit advice does
        // not come straight back.
        for frame in 3..<8 {
            XCTAssertNil(
                stabilizer.observe(decision(.correct, action: "a", frame: frame)),
                "dismissed advice must not be returned without a new analysis"
            )
            _ = now()
        }
        XCTAssertNil(stabilizer.currentAdvice)
    }

    func testMateriallyDifferentAdviceIsAllowedAfterDismissal() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() }, cooldown: 3.0, hysteresis: 3)

        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0))
            _ = now()
        }
        _ = stabilizer.dismiss(actionID: "a", targetIdentity: nil)

        var published: StabilizedAdvice?
        for frame in 3..<6 {
            published = stabilizer.observe(decision(.correct, action: "b", frame: frame))
            _ = now()
        }
        XCTAssertEqual(published?.actionID, "b")
        XCTAssertFalse(stabilizer.isDismissed)
    }

    func testInvalidateClearsDismissalForNewAnalysis() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() }, cooldown: 3.0, hysteresis: 3)

        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0))
            _ = now()
        }
        _ = stabilizer.dismiss(actionID: "a", targetIdentity: nil)
        XCTAssertTrue(stabilizer.isDismissed)

        _ = stabilizer.invalidate(frameID: "sceneCut", reason: "scene_cut")
        XCTAssertFalse(stabilizer.isDismissed)

        var published: StabilizedAdvice?
        for frame in 3..<6 {
            published = stabilizer.observe(decision(.correct, action: "a", frame: frame))
            _ = now()
        }
        XCTAssertEqual(published?.actionID, "a", "a new analysis may legitimately re-propose the action")
    }

    func testDismissalIsScopedToTargetNotTheWholeSession() {
        let clock = ScriptedClock()
        var now = { clock.tick() }
        var stabilizer = stabilizer(clock: { now() }, cooldown: 3.0, hysteresis: 3)

        for _ in 0..<3 {
            _ = stabilizer.observe(decision(.correct, action: "a", frame: 0, targetIdentity: targetA))
            _ = now()
        }
        _ = stabilizer.dismiss(actionID: "a", targetIdentity: targetA)

        var published: StabilizedAdvice?
        for frame in 3..<6 {
            published = stabilizer.observe(decision(.correct, action: "a", frame: frame, targetIdentity: targetB))
            _ = now()
        }
        XCTAssertEqual(published?.targetIdentity, targetB)
    }
}
