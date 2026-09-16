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

    private func objectCandidate(
        x: Double,
        label: String? = "lamp",
        id: String = "detector",
        confidence: Double = 0.9,
        width: Double = 0.15,
        height: Double = 0.2
    ) -> SubjectCandidate {
        SubjectCandidate(
            id: id,
            kind: .object,
            label: label,
            region: NormalizedRect(x: x, y: 0.35, width: width, height: height),
            confidence: confidence
        )
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

    // MARK: - Bounded local object tracking

    func testObjectsKeepIdentityThroughReorderAndModerateMotion() {
        let first = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.1, label: "lamp", id: "frame-0-a"),
                objectCandidate(x: 0.7, label: "chair", id: "frame-0-b"),
            ],
            frameID: "o0",
            generation: 1,
            sampleSequence: 1
        )
        let idsByLabel = Dictionary(uniqueKeysWithValues: first.map { ($0.label!, $0.identity) })
        XCTAssertNotEqual(idsByLabel["lamp"], idsByLabel["chair"])

        let second = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.73, label: "chair", id: "frame-1-b"),
                objectCandidate(x: 0.13, label: "lamp", id: "frame-1-a"),
            ],
            frameID: "o1",
            generation: 1,
            sampleSequence: 2
        )
        XCTAssertEqual(second.count, 2)
        XCTAssertTrue(second.allSatisfy { $0.phase == .active })
        XCTAssertEqual(second.first(where: { $0.label == "lamp" })?.identity, idsByLabel["lamp"])
        XCTAssertEqual(second.first(where: { $0.label == "chair" })?.identity, idsByLabel["chair"])
        XCTAssertEqual(second.map(\.frameID), ["o1", "o1"])
        XCTAssertEqual(second.map(\.sampleSequence), [2, 2])
    }

    func testSimilarObjectAmbiguityLosesTrackWithoutChoosingNearest() {
        let initial = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.4, label: "cup")],
            frameID: "a0",
            generation: 1,
            sampleSequence: 1
        )
        let originalID = initial[0].identity

        let ambiguous = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.39, label: "cup", id: "left"),
                objectCandidate(x: 0.41, label: "cup", id: "right"),
            ],
            frameID: "a1",
            generation: 1,
            sampleSequence: 2
        )
        XCTAssertEqual(ambiguous.count, 1)
        XCTAssertEqual(ambiguous[0].identity, originalID)
        XCTAssertEqual(ambiguous[0].phase, .lost)
        XCTAssertEqual(ambiguous[0].frameID, "a1")
        XCTAssertNil(ambiguous[0].region)
        XCTAssertEqual(ambiguous[0].lastObservedFrameID, "a0")
        XCTAssertEqual(ambiguous[0].lastObservedSampleSequence, 1)
    }

    func testCompetingCandidatesForOneTrackDoNotBecomeFreshTracks() {
        let initial = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.25, label: "box", width: 0.5)],
            frameID: "c0",
            generation: 1,
            sampleSequence: 1
        )
        let originalID = initial[0].identity

        let competing = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.2, label: "box", id: "left", width: 0.25),
                objectCandidate(x: 0.55, label: "box", id: "right", width: 0.25),
            ],
            frameID: "c1",
            generation: 1,
            sampleSequence: 2
        )
        XCTAssertEqual(competing.count, 1)
        XCTAssertEqual(competing[0].identity, originalID)
        XCTAssertEqual(competing[0].phase, .lost)
        XCTAssertNil(competing[0].region)
    }

    func testCompetingTracksDoNotChooseOneCandidateOrCreateFreshIdentity() {
        // Lower the threshold only to make one candidate plausibly overlap
        // both otherwise-separated tracks; the ambiguity must still fail
        // closed instead of selecting either track.
        tracker.iouMatchThreshold = 0.05
        let initial = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.1, label: "box"),
                objectCandidate(x: 0.7, label: "box")
            ],
            frameID: "ct0",
            generation: 1,
            sampleSequence: 1
        )
        XCTAssertEqual(initial.count, 2)
        let firstID = initial[0].identity
        let secondID = initial[1].identity

        let competing = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.2, label: "box", width: 0.6)],
            frameID: "ct1",
            generation: 1,
            sampleSequence: 2
        )
        XCTAssertEqual(competing.count, 2)
        XCTAssertTrue(competing.allSatisfy { $0.phase == .lost })
        XCTAssertTrue(competing.contains { $0.identity == firstID })
        XCTAssertTrue(competing.contains { $0.identity == secondID })
    }

    func testActiveAndLostCompatibleTracksRejectSharedObservation() {
        let initial = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.1, label: "box"),
                objectCandidate(x: 0.3, label: "box")
            ],
            frameID: "shared0",
            generation: 1,
            sampleSequence: 1
        )
        XCTAssertEqual(initial.count, 2)
        let firstID = initial[0].identity
        let secondID = initial[1].identity

        let oneSeen = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.1, label: "box")],
            frameID: "shared1",
            generation: 1,
            sampleSequence: 2
        )
        XCTAssertTrue(oneSeen.contains { $0.identity == firstID && $0.phase == .active })
        XCTAssertTrue(oneSeen.contains { $0.identity == secondID && $0.phase == .lost })

        let shared = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.1, label: "box", width: 0.35)],
            frameID: "shared2",
            generation: 1,
            sampleSequence: 3
        )
        XCTAssertEqual(shared.count, 2)
        XCTAssertTrue(shared.allSatisfy { $0.phase == .lost })
        XCTAssertTrue(shared.contains { $0.identity == firstID })
        XCTAssertTrue(shared.contains { $0.identity == secondID })
        XCTAssertTrue(shared.allSatisfy { $0.region == nil })
        XCTAssertTrue(shared.allSatisfy { $0.frameID == "shared2" && $0.sampleSequence == 3 })
        XCTAssertEqual(shared.first(where: { $0.identity == firstID })?.lastObservedFrameID, "shared1")
        XCTAssertEqual(shared.first(where: { $0.identity == firstID })?.lastObservedSampleSequence, 2)
        XCTAssertEqual(shared.first(where: { $0.identity == secondID })?.lastObservedFrameID, "shared0")
        XCTAssertEqual(shared.first(where: { $0.identity == secondID })?.lastObservedSampleSequence, 1)
    }

    func testWrongLabelCannotReuseActiveIdentity() {
        let initial = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.4, label: "cup")],
            frameID: "m0",
            generation: 1,
            sampleSequence: 1
        )
        let originalID = initial[0].identity

        let wrongLabel = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.4, label: "bottle")],
            frameID: "m1",
            generation: 1,
            sampleSequence: 2
        )
        XCTAssertTrue(wrongLabel.contains { $0.identity == originalID && $0.phase == .lost })
        XCTAssertTrue(wrongLabel.contains { $0.label == "bottle" && $0.phase == .active })
        XCTAssertNotEqual(
            wrongLabel.first(where: { $0.label == "bottle" })?.identity,
            originalID
        )
    }

    func testSameLabelReappearanceAfterLossGetsFreshIdentity() {
        let initial = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.4, label: "cup")],
            frameID: "r0",
            generation: 1,
            sampleSequence: 1
        )
        let originalID = initial[0].identity
        _ = tracker.updateObjects(
            candidates: [],
            frameID: "r1",
            generation: 1,
            sampleSequence: 2
        )

        let reappeared = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.4, label: "cup")],
            frameID: "r2",
            generation: 1,
            sampleSequence: 3
        )
        XCTAssertEqual(reappeared.count, 1)
        XCTAssertEqual(reappeared[0].phase, .active)
        XCTAssertNotEqual(reappeared[0].identity, originalID)
        XCTAssertEqual(reappeared[0].lastObservedFrameID, "r2")
        XCTAssertEqual(reappeared[0].lastObservedSampleSequence, 3)
    }

    func testCenterJumpDoesNotReuseIdentity() {
        tracker.centerJumpThreshold = 0.02
        let initial = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.1, label: "cup")],
            frameID: "j0",
            generation: 1,
            sampleSequence: 1
        )
        let originalID = initial[0].identity

        let jumped = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.13, label: "cup")],
            frameID: "j1",
            generation: 1,
            sampleSequence: 2
        )
        XCTAssertTrue(jumped.contains { $0.identity == originalID && $0.phase == .lost })
        XCTAssertTrue(jumped.contains { $0.phase == .active && $0.label == "cup" })
        XCTAssertNotEqual(jumped.first(where: { $0.phase == .active })?.identity, originalID)
    }

    func testGenerationChangeStartsFreshObjectIdentities() {
        let first = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.3, label: "lamp")],
            frameID: "g0",
            generation: 1,
            sampleSequence: 9
        )
        let second = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.3, label: "lamp")],
            frameID: "g1",
            generation: 2,
            sampleSequence: 1
        )
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].identity.generation, 2)
        XCTAssertNotEqual(second[0].identity, first[0].identity)
    }

    func testLowerGenerationCannotReplaceCurrentObjectEpoch() {
        let accepted = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.2, label: "lamp")],
            frameID: "g2",
            generation: 2,
            sampleSequence: 10
        )
        let rejected = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.7, label: "lamp")],
            frameID: "g1",
            generation: 1,
            sampleSequence: 1
        )
        XCTAssertEqual(rejected, accepted)
        XCTAssertEqual(tracker.currentObjects, accepted)
        XCTAssertEqual(tracker.currentObjects[0].identity.generation, 2)
        XCTAssertEqual(tracker.currentObjects[0].frameID, "g2")
        XCTAssertEqual(tracker.currentObjects[0].sampleSequence, 10)
    }

    func testRepeatedOrOutOfOrderObjectSequenceDoesNotOverwriteCurrentProvenance() {
        _ = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.2, label: "lamp")],
            frameID: "s0",
            generation: 1,
            sampleSequence: 4
        )
        let accepted = tracker.currentObjects

        let rejected = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.7, label: "lamp")],
            frameID: "stale",
            generation: 1,
            sampleSequence: 4
        )
        XCTAssertEqual(rejected, accepted)
        XCTAssertEqual(tracker.currentObjects, accepted)
        XCTAssertEqual(tracker.currentObjects[0].frameID, "s0")
        XCTAssertEqual(tracker.currentObjects[0].sampleSequence, 4)

        let rejectedLower = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.8, label: "lamp")],
            frameID: "older",
            generation: 1,
            sampleSequence: 3
        )
        XCTAssertEqual(rejectedLower, accepted)
    }

    func testObjectCapacityAndCandidateValidation() {
        let states = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.02, label: "a"),
                objectCandidate(x: 0.22, label: "b"),
                objectCandidate(x: 0.42, label: "c"),
                objectCandidate(x: 0.62, label: "d"),
                objectCandidate(x: 0.82, label: "e"),
                SubjectCandidate(
                    id: "person",
                    kind: .person,
                    region: region(x: 0.05, y: 0.35, w: 0.15, h: 0.2),
                    confidence: 0.99
                ),
                objectCandidate(x: 0.05, label: "low", confidence: 0.54),
                objectCandidate(x: 0.05, label: "degenerate", width: 0),
                // Use an earliest-sorted overrun so acceptance cannot be
                // hidden by the four-object capacity cap. Negative x is
                // clamped by NormalizedRect's initializer.
                objectCandidate(x: 0.01, label: "out-of-bounds", width: 1.0)
            ],
            frameID: "v0",
            generation: 1,
            sampleSequence: 1
        )
        XCTAssertEqual(states.count, 4)
        XCTAssertEqual(states.map(\.label), ["a", "b", "c", "d"])
        XCTAssertTrue(states.allSatisfy { $0.phase == .active })
    }

    func testExactDuplicateObjectBoxesCreateOneIdentity() {
        let states = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.25, label: "lamp", id: "first", confidence: 0.7),
                objectCandidate(x: 0.25, label: "lamp", id: "second", confidence: 0.95),
            ],
            frameID: "d0",
            generation: 1,
            sampleSequence: 1
        )
        XCTAssertEqual(states.count, 1)
        XCTAssertEqual(states[0].label, "lamp")
        XCTAssertEqual(states[0].phase, .active)
    }

    func testResetAndInvalidateClearObjectStateEvenWithoutPrimary() {
        _ = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.2, label: "lamp")],
            frameID: "l0",
            generation: 1,
            sampleSequence: 1
        )
        XCTAssertNil(tracker.invalidate(cause: .lensChange, frameID: "l1"))
        XCTAssertTrue(tracker.currentObjects.allSatisfy { $0.phase == .lost })
        XCTAssertEqual(tracker.currentObjects[0].frameID, "l1")
        XCTAssertNil(tracker.currentObjects[0].region)
        XCTAssertEqual(tracker.currentObjects[0].lastObservedFrameID, "l0")

        tracker.reset()
        XCTAssertTrue(tracker.currentObjects.isEmpty)
        XCTAssertNil(tracker.current)
    }

    // MARK: - C03 stable selected object through swap and loss

    func testBoundObjectDoesNotFollowTwoLampSwap() throws {
        let generation: UInt64 = 5
        let first = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.05, label: "lamp", id: "detector-left"),
                objectCandidate(x: 0.75, label: "lamp", id: "detector-right")
            ],
            frameID: "f1",
            generation: generation,
            sampleSequence: 1
        )
        XCTAssertEqual(first.count, 2)
        let leftTrack = try XCTUnwrap(first.first { ($0.lastObservedRegion?.x ?? 1) < 0.5 })
        let binding = ObjectTargetBinding(
            trackID: leftTrack.identity.trackID,
            displayLabel: "lamp",
            generation: generation,
            boundAtFrameID: "f1"
        )
        XCTAssertEqual(
            binding.resolve(in: first, generation: generation),
            .bound(region: try XCTUnwrap(leftTrack.lastObservedRegion))
        )

        // The two same-label lamps pass through each other and swap sides. The
        // old tracks no longer overlap either candidate, so the tracker must
        // create fresh identities instead of silently re-pointing the selected
        // lamp at the other lamp.
        let swapped = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.45, label: "lamp", id: "detector-left"),
                objectCandidate(x: 0.15, label: "lamp", id: "detector-right")
            ],
            frameID: "f2",
            generation: generation,
            sampleSequence: 2
        )
        XCTAssertFalse(
            swapped.contains {
                $0.identity.trackID == leftTrack.identity.trackID && $0.phase == .active
            },
            "the selected lamp must not silently become the other lamp"
        )
        XCTAssertEqual(
            binding.resolve(in: swapped, generation: generation),
            .unresolved(reason: .trackLost)
        )
        // A fresh same-label identity (the other lamp) never satisfies the
        // frozen binding.
        let freshTrackIDs = Set(swapped.filter { $0.phase == .active }.map(\.identity.trackID))
        XCTAssertFalse(freshTrackIDs.contains(leftTrack.identity.trackID))
    }

    func testLostBoundTrackInvalidatesWithoutReassigningAnotherObject() throws {
        let generation: UInt64 = 6
        let first = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.2, label: "lamp", id: "d1")],
            frameID: "f1",
            generation: generation,
            sampleSequence: 1
        )
        let trackID = try XCTUnwrap(first.first).identity.trackID
        let binding = ObjectTargetBinding(
            trackID: trackID,
            displayLabel: "lamp",
            generation: generation,
            boundAtFrameID: "f1"
        )

        // The selected lamp leaves the frame; a different same-label lamp
        // enters. The fresh identity must never satisfy the old binding.
        let after = tracker.updateObjects(
            candidates: [objectCandidate(x: 0.7, label: "lamp", id: "d2")],
            frameID: "f2",
            generation: generation,
            sampleSequence: 2
        )
        let fresh = try XCTUnwrap(after.first { $0.phase == .active })
        XCTAssertNotEqual(fresh.identity.trackID, trackID)

        switch binding.resolve(in: after, generation: generation) {
        case .bound:
            XCTFail("a lost selection must not be reassigned to another object")
        case let .unresolved(reason):
            XCTAssertEqual(reason, .trackLost)
        }

        // The episode boundary invalidates the tracked objects as well.
        _ = tracker.invalidate(cause: .routeExit, frameID: "f2")
        XCTAssertTrue(tracker.currentObjects.allSatisfy { $0.phase == .lost })
    }

    func testSameLabelSiblingDoesNotProveIdentity() throws {
        let generation: UInt64 = 8
        let objects = tracker.updateObjects(
            candidates: [
                objectCandidate(x: 0.1, label: "lamp", id: "a"),
                objectCandidate(x: 0.7, label: "lamp", id: "b")
            ],
            frameID: "f1",
            generation: generation,
            sampleSequence: 1
        )
        let right = try XCTUnwrap(objects.first { ($0.lastObservedRegion?.x ?? 0) > 0.5 })
        let sibling = try XCTUnwrap(objects.first { $0.identity.trackID != right.identity.trackID })
        let binding = ObjectTargetBinding(
            trackID: right.identity.trackID,
            displayLabel: "lamp",
            generation: generation,
            boundAtFrameID: "f1"
        )

        // Both objects carry the same label; only the bound trackID resolves,
        // and it resolves to the bound region, not the sibling's.
        switch binding.resolve(in: objects, generation: generation) {
        case let .bound(region):
            XCTAssertEqual(region.x, try XCTUnwrap(right.lastObservedRegion).x, accuracy: 1e-12)
            XCTAssertNotEqual(region.x, try XCTUnwrap(sibling.lastObservedRegion).x)
        case .unresolved:
            XCTFail("a live exact track must resolve")
        }

        // A generation change retires the identity entirely.
        XCTAssertEqual(
            binding.resolve(in: objects, generation: generation + 1),
            .unresolved(reason: .generationChanged)
        )
    }
}
