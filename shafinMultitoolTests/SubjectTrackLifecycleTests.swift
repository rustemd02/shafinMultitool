//
//  SubjectTrackLifecycleTests.swift
//  shafinMultitoolTests
//
//  M2-011 SubjectTrackingOwner: sequence tests — rotation, lens switch,
//  stop/restart, background, and scene cut each invalidate the track and
//  rotate the coaching episode token, so no advice or verifier result
//  survives an invalidating change.
//

import XCTest
@testable import shafinMultitool

final class SubjectTrackLifecycleTests: XCTestCase {

    private func context(generation: UInt64 = 3,
                         orientation: CameraCoachOrientation = .portrait,
                         lensID: String? = "wide",
                         routeActive: Bool = true,
                         backgrounded: Bool = false,
                         sceneSignature: String? = "scene-a") -> SubjectTrackLifecycleContext {
        SubjectTrackLifecycleContext(
            generation: generation,
            orientation: orientation,
            lensID: lensID,
            routeActive: routeActive,
            isAppBackgrounded: backgrounded,
            sceneSignature: sceneSignature
        )
    }

    // MARK: - Cause detection

    func testEachInvalidatingChangeIsDetected() {
        var guardState = SubjectTrackLifecycleGuard(context: context())
        var invalidations: [SubjectTrackInvalidationCause] = []

        // Cumulative sequence: each context keeps the changes applied so far
        // and adds exactly one new invalidating change.
        let sequence: [SubjectTrackLifecycleContext] = [
            context(generation: 4),                                          // camera generation
            context(generation: 4, lensID: "tele"),                          // lens switch
            context(generation: 4, orientation: .landscapeLeft, lensID: "tele"),          // rotation
            context(generation: 4, orientation: .landscapeLeft, lensID: "tele", routeActive: false),      // stop
            context(generation: 4, orientation: .landscapeLeft, lensID: "tele", routeActive: false, backgrounded: true), // background
            context(generation: 4, orientation: .landscapeLeft, lensID: "tele", routeActive: false, backgrounded: true, sceneSignature: "scene-b"), // scene cut
        ]
        for (index, newContext) in sequence.enumerated() {
            let invalidation = guardState.validate(newContext, frameID: "f\(index)")
            XCTAssertNotNil(invalidation, "change \(index) must invalidate")
            invalidations.append(invalidation!.cause)
        }

        XCTAssertEqual(invalidations, [
            .cameraGenerationChange, .lensChange, .orientationChange,
            .routeExit, .background, .sceneCut,
        ])
    }

    func testUnchangedContextDoesNotInvalidate() {
        var guardState = SubjectTrackLifecycleGuard(context: context())
        XCTAssertNil(guardState.validate(context(), frameID: "f1"))
        XCTAssertNil(guardState.validate(context(), frameID: "f2"))
    }

    func testRouteRestartIsANewEpisodeWithoutRouteExitCause() {
        // The route exit itself already invalidated; the restart only moves
        // the context forward (no duplicate cause).
        var guardState = SubjectTrackLifecycleGuard(context: context())
        XCTAssertNotNil(guardState.validate(context(routeActive: false), frameID: "f1"))
        XCTAssertNil(guardState.validate(context(routeActive: true), frameID: "f2"))
        let restartSignature = context(routeActive: true, sceneSignature: "scene-b")
        XCTAssertEqual(guardState.validate(restartSignature, frameID: "f3")?.cause, .sceneCut)
    }

    // MARK: - Episode token invalidation

    func testEpisodeTokenRotatesOnInvalidationAndOnlyThen() {
        var guardState = SubjectTrackLifecycleGuard(context: context())
        let initialToken = guardState.episode

        XCTAssertNil(guardState.validate(context(), frameID: "f1"))
        XCTAssertEqual(guardState.episode, initialToken, "unchanged context keeps the episode")

        XCTAssertNotNil(guardState.validate(context(generation: 9), frameID: "f2"))
        XCTAssertNotEqual(guardState.episode, initialToken, "invalidation rotates the episode")

        // A result produced under the old token is stale; the new token is
        // current; a nil token always fails closed.
        XCTAssertTrue(guardState.isStale(initialToken))
        XCTAssertFalse(guardState.isStale(guardState.episode))
        XCTAssertTrue(guardState.isStale(nil))
    }

    func testVerifierResultCannotSurviveGenerationChange() {
        var guardState = SubjectTrackLifecycleGuard(context: context())
        let stamp = guardState.episode
        XCTAssertFalse(guardState.isStale(stamp), "precondition: the result was current")

        // A camera generation change happens after the verifier result was
        // produced under the old episode stamp.
        XCTAssertNotNil(guardState.validate(context(generation: 10), frameID: "fV"))

        XCTAssertTrue(guardState.isStale(stamp),
                      "verifier result must not survive a generation change")
    }

    // MARK: - Tracker integration

    func testInvalidationLosesActiveTrackAndReportsIdentity() {
        let tracker = SubjectTracker()
        let resolution = try! SubjectResolutionV2(
            resolution: .automatic,
            selected: SubjectCandidate(
                id: "auto",
                kind: .person,
                region: NormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.4),
                confidence: 0.9
            ),
            track: nil,
            provenance: .automatic,
            confidence: 0.9,
            ambiguityReasons: [],
            decidedAtFrameID: "f0"
        )
        tracker.begin(resolution: resolution, frameID: "f0", generation: 3)
        let trackID = tracker.current?.identity.trackID

        let invalidated = tracker.invalidate(cause: .lensChange, frameID: "fL")
        XCTAssertEqual(invalidated, trackID)
        XCTAssertEqual(tracker.current?.phase, .lost)
        XCTAssertEqual(tracker.current?.lostSinceFrameID, "fL")

        // A second invalidation with no active track reports nil cleanly.
        XCTAssertNil(tracker.invalidate(cause: .orientationChange, frameID: "fL2"))
    }

    func testSceneCutSequenceInvalidatesTrackAndEpisodeTogether() {
        let tracker = SubjectTracker()
        var guardState = SubjectTrackLifecycleGuard(context: context())
        let episodeBefore = guardState.episode

        let resolution = try! SubjectResolutionV2(
            resolution: .automatic,
            selected: SubjectCandidate(
                id: "auto",
                kind: .person,
                region: NormalizedRect(x: 0.4, y: 0.3, width: 0.2, height: 0.4),
                confidence: 0.9
            ),
            track: nil,
            provenance: .automatic,
            confidence: 0.9,
            ambiguityReasons: [],
            decidedAtFrameID: "f0"
        )
        tracker.begin(resolution: resolution, frameID: "f0", generation: 3)

        // Scene cut: guard detects, tracker loses, episode rotates.
        let invalidation = guardState.validate(context(sceneSignature: "scene-z"), frameID: "fC")
        XCTAssertEqual(invalidation?.cause, .sceneCut)
        let invalidatedID = tracker.invalidate(
            cause: invalidation!.cause,
            frameID: invalidation!.frameID
        )
        XCTAssertNotNil(invalidatedID, "an active track must be reported as invalidated")
        XCTAssertTrue(invalidatedID?.hasPrefix("track-") ?? false)
        XCTAssertTrue(tracker.current?.isLost ?? false)
        XCTAssertNotEqual(guardState.episode, episodeBefore)
        XCTAssertTrue(guardState.isStale(episodeBefore), "advice from the old episode is stale")
    }
}
