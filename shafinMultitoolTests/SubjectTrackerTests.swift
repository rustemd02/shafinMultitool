//
//  SubjectTrackerTests.swift
//  shafinMultitoolTests
//
//  M2-010 SubjectTrackingOwner: scripted bounding-box sequence tests —
//  stable ID through motion/occlusion, explicit loss, reconciliation without
//  identity swap, periodic redetection flag.
//

import XCTest
@testable import shafinMultitool

final class SubjectTrackerTests: XCTestCase {

    private var tracker: SubjectTracker!

    override func setUp() {
        super.setUp()
        tracker = SubjectTracker()
    }

    override func tearDown() {
        tracker = nil
        super.tearDown()
    }

    private func region(x: Double, y: Double = 0.3, w: Double = 0.2, h: Double = 0.4) -> NormalizedRect {
        NormalizedRect(x: x, y: y, width: w, height: h)
    }

    private func candidate(x: Double, id: String = "c", confidence: Double = 0.9) -> SubjectCandidate {
        SubjectCandidate(id: id, kind: .person, region: region(x: x), confidence: confidence)
    }

    private func beginResolution(x: Double = 0.4, frameID: String = "f0") {
        let resolution = try! SubjectResolutionV2(
            resolution: .automatic,
            selected: candidate(x: x, id: "auto"),
            track: nil,
            provenance: .automatic,
            confidence: 0.9,
            ambiguityReasons: [],
            decidedAtFrameID: frameID
        )
        tracker.begin(resolution: resolution, frameID: frameID, generation: 3)
    }

    // MARK: - Stable identity through moderate motion

    func testTrackIDStaysStableThroughModerateMotion() {
        beginResolution(x: 0.4, frameID: "f0")
        let startID = tracker.current?.identity.trackID

        // Small drifts each frame stay above the IoU threshold.
        for (index, x) in [0.41, 0.43, 0.45, 0.48].enumerated() {
            let state = tracker.observe(frameID: "f\(index + 1)", candidates: [candidate(x: x)])
            XCTAssertEqual(state?.identity.trackID, startID, "identity must persist through motion")
            XCTAssertEqual(state?.phase, .active)
        }
    }

    func testPartialOcclusionWithinLimitKeepsTrackActive() {
        beginResolution(frameID: "f0")
        let startID = tracker.current?.identity.trackID

        // 9 consecutive misses (< loss limit 10): track stays active.
        for index in 1...9 {
            let state = tracker.observe(frameID: "f\(index)", candidates: [])
            XCTAssertEqual(state?.phase, .active, "miss \(index) must not lose the track")
        }
        XCTAssertEqual(tracker.current?.identity.trackID, startID)

        // The subject reappears at the remembered position: same identity.
        let state = tracker.observe(frameID: "f10", candidates: [candidate(x: 0.4)])
        XCTAssertEqual(state?.phase, .active)
        XCTAssertEqual(state?.identity.trackID, startID)
        XCTAssertEqual(state?.missedFrames, 0)
    }

    // MARK: - Explicit loss

    func testConsecutiveMissesBeyondLimitLoseTrackExplicitly() {
        beginResolution(frameID: "f0")
        var state: SubjectTrackState?
        for index in 1...11 {
            state = tracker.observe(frameID: "f\(index)", candidates: [])
        }
        XCTAssertEqual(state?.phase, .lost)
        XCTAssertEqual(state?.lostSinceFrameID, "f10")
        XCTAssertTrue(state?.isLost ?? false)

        // Advice consumers see the explicit loss and must invalidate.
        XCTAssertTrue(tracker.current?.isLost ?? false)
    }

    func testMarkLostInvalidatesImmediately() {
        beginResolution(frameID: "f0")
        tracker.markLost(frameID: "fX")
        XCTAssertEqual(tracker.current?.phase, .lost)
        XCTAssertEqual(tracker.current?.lostSinceFrameID, "fX")
    }

    // MARK: - Reconciliation without identity swap

    func testReconciliationNearOriginalRegionKeepsIdentity() {
        beginResolution(x: 0.4, frameID: "f0")
        let startID = tracker.current?.identity.trackID
        tracker.markLost(frameID: "fL")

        // The subject reappears at (roughly) the remembered position.
        let state = tracker.observe(frameID: "fR", candidates: [candidate(x: 0.4)])
        XCTAssertEqual(state?.phase, .active)
        XCTAssertEqual(state?.identity.trackID, startID, "reconciliation must keep the identity")
        XCTAssertEqual(state?.reconciliations, 1)
        XCTAssertNil(state?.lostSinceFrameID)
    }

    func testDistantCandidateAfterLossDoesNotAdoptOldIdentity() {
        beginResolution(x: 0.4, frameID: "f0")
        let startID = tracker.current?.identity.trackID
        tracker.markLost(frameID: "fL")

        // A candidate appears far from the remembered region: it must NOT
        // silently adopt the old identity.
        let state = tracker.observe(frameID: "fR", candidates: [candidate(x: 0.05)])
        XCTAssertEqual(state?.phase, .lost, "far candidate must not resurrect the track")
        XCTAssertEqual(state?.identity.trackID, startID)
        XCTAssertEqual(state?.lastRegion, region(x: 0.4), "the remembered region must be kept for later reconciliation")
        XCTAssertEqual(state?.reconciliations, 0)
    }

    func testCenterJumpBeyondThresholdIsRejectedAsIdentitySwap() {
        beginResolution(x: 0.4, frameID: "f0")
        let startID = tracker.current?.identity.trackID

        // High IoU is impossible with a huge jump for similar box sizes; use
        // an oversized candidate that overlaps the old region (IoU passes)
        // but whose center is far away — the swap guard must reject it.
        let swapped = SubjectCandidate(
            id: "swapped",
            kind: .person,
            region: NormalizedRect(x: 0.4, y: 0.3, width: 0.95, height: 0.4),
            confidence: 0.9
        )
        let state = tracker.observe(frameID: "f1", candidates: [swapped])
        XCTAssertEqual(state?.identity.trackID, startID, "identity must not change silently")
        // The jumped candidate is treated as a miss: the tracker stays on the
        // old region and phase within the occlusion tolerance instead of
        // silently adopting the swapped identity.
        XCTAssertEqual(state?.phase, .active)
        XCTAssertEqual(state?.missedFrames, 1)
        XCTAssertEqual(state?.lastRegion, region(x: 0.4), "tracked region must not jump")
    }

    // MARK: - Periodic redetection

    func testRedetectionDueFlagFollowsCadence() {
        beginResolution(frameID: "f0")
        tracker.redetectionIntervalFrames = 5

        var state: SubjectTrackState?
        for index in 1...5 {
            state = tracker.observe(frameID: "f\(index)", candidates: [candidate(x: 0.4)])
            if index < 5 {
                XCTAssertEqual(state?.redetectionDue, false, "frame \(index)")
            }
        }
        XCTAssertEqual(state?.redetectionDue, true, "redetection flag must rise at the cadence")

        // The flag stays until the pipeline performs the redetection pass.
        state = tracker.observe(frameID: "f6", candidates: [candidate(x: 0.4)])
        XCTAssertEqual(state?.redetectionDue, true, "flag latches until redetection is performed")

        tracker.noteRedetectionPerformed()
        XCTAssertFalse(tracker.current?.redetectionDue ?? true)

        state = tracker.observe(frameID: "f7", candidates: [candidate(x: 0.4)])
        XCTAssertEqual(state?.redetectionDue, false, "cadence restarts after redetection")
    }

    // MARK: - Unknown resolution / reset

    func testUnknownResolutionBeginsNoTrack() {
        let unknown = try! SubjectResolutionV2.unknown(reasons: [.noCandidate], decidedAtFrameID: "f0")
        tracker.begin(resolution: unknown, frameID: "f0", generation: 1)
        XCTAssertNil(tracker.current)
        XCTAssertNil(tracker.observe(frameID: "f1", candidates: [candidate(x: 0.4)]))
    }

    func testResetClearsTracking() {
        beginResolution(frameID: "f0")
        tracker.reset()
        XCTAssertNil(tracker.current)
        XCTAssertNil(tracker.observe(frameID: "f1", candidates: [candidate(x: 0.4)]))
    }
}
