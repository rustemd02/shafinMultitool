//
//  SubjectIdentityRegistryTests.swift
//  shafinMultitool
//
//  R03 groundwork contract tests: multi-object identity association, loss
//  aging, overlap resolution, reappearance, capacity and generation fences.
//

import XCTest
@testable import shafinMultitool

final class SubjectIdentityRegistryTests: XCTestCase {

    private func observation(x: Double, y: Double, w: Double, h: Double,
                             confidence: Double = 0.9, label: String? = "lamp") -> SubjectIdentityObservation {
        SubjectIdentityObservation(
            region: NormalizedRect(x: x, y: y, width: w, height: h),
            confidence: confidence,
            label: label
        )
    }

    private func trackIDs(_ registry: SubjectIdentityRegistry) -> [String] {
        registry.identities.map { $0.identity.trackID }.sorted()
    }

    func testFirstFrameCreatesIdentityPerDetection() {
        var registry = SubjectIdentityRegistry(generation: 7)
        let events = registry.observe(
            detections: [observation(x: 0.05, y: 0.1, w: 0.2, h: 0.3), observation(x: 0.6, y: 0.5, w: 0.25, h: 0.3)],
            frameId: "f1"
        )
        XCTAssertEqual(registry.identities.count, 2)
        XCTAssertEqual(events.filter {
            if case .created = $0 { return true }
            return false
        }.count, 2)
        for identity in registry.identities {
            XCTAssertEqual(identity.identity.generation, 7)
            XCTAssertEqual(identity.identity.firstSeenFrameID, "f1")
            XCTAssertEqual(identity.consecutiveMisses, 0)
            XCTAssertEqual(identity.lifetimeFrames, 1)
        }
    }

    func testHighIoUDetectionKeepsStableIdentityAcrossFrames() {
        var registry = SubjectIdentityRegistry(generation: 7)
        registry.observe(detections: [observation(x: 0.05, y: 0.1, w: 0.2, h: 0.3)], frameId: "f1")
        let originalTrackID = registry.identities[0].identity.trackID

        let events = registry.observe(
            detections: [observation(x: 0.07, y: 0.12, w: 0.2, h: 0.3)],
            frameId: "f2"
        )
        XCTAssertEqual(registry.identities.count, 1)
        XCTAssertEqual(registry.identities[0].identity.trackID, originalTrackID)
        XCTAssertEqual(registry.identities[0].lifetimeFrames, 2)
        XCTAssertEqual(events.filter {
            if case .associated = $0 { return true }
            return false
        }.count, 1)
    }

    func testUnmatchedDetectionSpawnsSecondIdentity() {
        var registry = SubjectIdentityRegistry(generation: 7)
        registry.observe(detections: [observation(x: 0.05, y: 0.1, w: 0.2, h: 0.3)], frameId: "f1")

        let events = registry.observe(
            detections: [
                observation(x: 0.06, y: 0.11, w: 0.2, h: 0.3),
                observation(x: 0.7, y: 0.6, w: 0.2, h: 0.25)
            ],
            frameId: "f2"
        )
        XCTAssertEqual(registry.identities.count, 2)
        XCTAssertEqual(events.filter {
            if case .associated = $0 { return true }
            return false
        }.count, 1)
        XCTAssertEqual(events.filter {
            if case .created = $0 { return true }
            return false
        }.count, 1)
    }

    func testIdentityIsLostAfterMissLimit() {
        var registry = SubjectIdentityRegistry(generation: 7)
        registry.observe(detections: [observation(x: 0.05, y: 0.1, w: 0.2, h: 0.3)], frameId: "f1")
        let originalTrackID = registry.identities[0].identity.trackID

        // missLimit = 3: three consecutive empty frames keep it alive, the
        // fourth removes it.
        for frame in 2...4 {
            registry.observe(detections: [], frameId: "f\(frame)")
            XCTAssertEqual(registry.identities.count, 1, "frame \(frame)")
            XCTAssertEqual(registry.identities[0].consecutiveMisses, frame - 1)
        }
        let events = registry.observe(detections: [], frameId: "f5")
        XCTAssertTrue(events.contains {
            if case .lost(let trackID) = $0 { return trackID == originalTrackID }
            return false
        })
        XCTAssertTrue(registry.identities.isEmpty)
    }

    func testOverlapResolvesByBestIoUWithoutDoubleClaim() {
        var registry = SubjectIdentityRegistry(generation: 7)
        registry.observe(detections: [observation(x: 0.3, y: 0.3, w: 0.3, h: 0.3)], frameId: "f1")
        let trackID = registry.identities[0].identity.trackID

        // Two detections overlap the identity: exact region (IoU 1.0) and a
        // shifted one (IoU ~0.43). The best must claim the identity; the
        // other must spawn a new one instead of double-claiming.
        let events = registry.observe(
            detections: [
                observation(x: 0.3, y: 0.3, w: 0.3, h: 0.3),
                observation(x: 0.45, y: 0.3, w: 0.3, h: 0.3)
            ],
            frameId: "f2"
        )
        let associated = registry.identity(forTrackID: trackID)
        XCTAssertNotNil(associated)
        XCTAssertEqual(associated?.region, NormalizedRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3))
        let distinctTrackIDs = Set(registry.identities.map { $0.identity.trackID })
        XCTAssertEqual(distinctTrackIDs.count, registry.identities.count)
        XCTAssertTrue(registry.identities.count >= 2)
    }

    func testReappearanceWithinGraceWindowKeepsIdentity() {
        var registry = SubjectIdentityRegistry(generation: 7)
        registry.observe(detections: [observation(x: 0.1, y: 0.1, w: 0.25, h: 0.3)], frameId: "f1")
        let trackID = registry.identities[0].identity.trackID

        registry.observe(detections: [], frameId: "f2")
        registry.observe(detections: [], frameId: "f3")

        let events = registry.observe(
            detections: [observation(x: 0.1, y: 0.1, w: 0.25, h: 0.3)],
            frameId: "f4"
        )
        XCTAssertEqual(registry.identities.count, 1)
        XCTAssertEqual(registry.identities[0].identity.trackID, trackID)
        XCTAssertTrue(events.contains {
            if case .associated(let id, _) = $0 { return id == trackID }
            return false
        })
    }

    func testCapacityLimitBoundsIdentitiesAndReportsExcess() {
        var registry = SubjectIdentityRegistry(generation: 7)
        var detections: [SubjectIdentityObservation] = []
        for index in 0..<8 {
            let x = Double(index % 4) * 0.25
            let y = Double(index / 4) * 0.5
            detections.append(observation(x: x, y: y, w: 0.2, h: 0.2))
        }
        let events = registry.observe(detections: detections, frameId: "f1")
        XCTAssertEqual(registry.identities.count, SubjectIdentityRegistry.maxIdentities)
        XCTAssertEqual(events.filter {
            if case .capacityExceeded = $0 { return true }
            return false
        }.count, 2)
    }

    func testGenerationFenceSeparatesRegistries() {
        var registryA = SubjectIdentityRegistry(generation: 1)
        var registryB = SubjectIdentityRegistry(generation: 2)
        registryA.observe(detections: [observation(x: 0.1, y: 0.1, w: 0.2, h: 0.3)], frameId: "f1")
        registryB.observe(detections: [observation(x: 0.1, y: 0.1, w: 0.2, h: 0.3)], frameId: "f1")
        XCTAssertEqual(registryA.identities[0].identity.generation, 1)
        XCTAssertEqual(registryB.identities[0].identity.generation, 2)
        XCTAssertNotEqual(registryA.identities[0].identity.trackID, registryB.identities[0].identity.trackID)
    }

    func testMultiObjectSummaryReportsTwoLampsWithoutOverlap() {
        var registry = SubjectIdentityRegistry(generation: 7)
        registry.observe(detections: [
            observation(x: 0.05, y: 0.2, w: 0.2, h: 0.3, label: "lamp"),
            observation(x: 0.65, y: 0.2, w: 0.2, h: 0.3, label: "lamp")
        ], frameId: "f1")
        let summary = registry.multiObjectSummary()
        XCTAssertEqual(summary.identityCount, 2)
        XCTAssertEqual(summary.identityCountByLabel["lamp"], 2)
        XCTAssertTrue(summary.overlappingTrackIDPairs.isEmpty, "spatially separate lamps must not overlap")
        XCTAssertTrue(summary.edgeCutTrackIDs.isEmpty)
    }

    func testMultiObjectSummaryFlagsOverlappingPairAndEdgeCut() {
        var registry = SubjectIdentityRegistry(generation: 7)
        // Two lamp identities whose regions overlap (O05); the left one is
        // additionally cut by the frame edge.
        registry.observe(detections: [
            observation(x: 0.01, y: 0.2, w: 0.25, h: 0.3, label: "lamp"),
            observation(x: 0.15, y: 0.2, w: 0.25, h: 0.3, label: "lamp")
        ], frameId: "f1")
        let summary = registry.multiObjectSummary()
        XCTAssertEqual(summary.identityCountByLabel["lamp"], 2)
        XCTAssertEqual(summary.overlappingTrackIDPairs.count, 1, "the two lamp regions overlap")
        XCTAssertEqual(summary.edgeCutTrackIDs.count, 1, "exactly one region is cut by the edge")
    }

    func testZeroAreaDetectionCannotClaimLaterRealDetection() {
        var registry = SubjectIdentityRegistry(generation: 7)
        // A degenerate zero-area region has IoU 0 with everything: it
        // registers, but can never absorb a later real detection.
        registry.observe(detections: [observation(x: 0.5, y: 0.5, w: 0.0, h: 0.0)], frameId: "f1")
        let events = registry.observe(
            detections: [observation(x: 0.1, y: 0.1, w: 0.2, h: 0.3)],
            frameId: "f2"
        )
        XCTAssertEqual(events.filter {
            if case .created = $0 { return true }
            return false
        }.count, 1, "the real detection must spawn its own identity")
        XCTAssertEqual(registry.identities.count, 2)
    }

    func testIdentityFieldsSurviveAssociationWithoutLabelDrift() {
        var registry = SubjectIdentityRegistry(generation: 7)
        registry.observe(detections: [observation(x: 0.1, y: 0.1, w: 0.2, h: 0.3, label: "lamp")], frameId: "f1")
        registry.observe(
            detections: [observation(x: 0.11, y: 0.1, w: 0.2, h: 0.3, label: nil)],
            frameId: "f2"
        )
        XCTAssertEqual(registry.identities[0].label, "lamp", "nil label must not overwrite a known label")
    }

    // MARK: - C03 identity separation, reflections and labels

    func testReflectionDetectionNeverBecomesIdentity() {
        var registry = SubjectIdentityRegistry(generation: 1)
        let events = registry.observe(
            detections: [
                observation(x: 0.1, y: 0.2, w: 0.2, h: 0.3, label: "lamp"),
                SubjectIdentityObservation(
                    region: NormalizedRect(x: 0.6, y: 0.2, width: 0.2, height: 0.3),
                    confidence: 0.9,
                    label: "lamp",
                    entityID: "mirror-1",
                    isReflection: true
                )
            ],
            frameId: "f1"
        )
        XCTAssertEqual(registry.identities.count, 1, "a reflection is not a rearrangeable object")
        XCTAssertEqual(events.filter {
            if case .created = $0 { return true }
            return false
        }.count, 1)
        XCTAssertFalse(registry.identities.contains { $0.lastEntityID == "mirror-1" })
    }

    func testEntityIDTrackIDAndLabelStaySeparate() {
        var registry = SubjectIdentityRegistry(generation: 4)
        registry.observe(
            detections: [SubjectIdentityObservation(
                region: NormalizedRect(x: 0.1, y: 0.2, width: 0.2, height: 0.3),
                confidence: 0.9,
                label: "lamp",
                entityID: "frame-1-entity-7"
            )],
            frameId: "f1"
        )
        let trackID = registry.identities[0].identity.trackID
        registry.observe(
            detections: [SubjectIdentityObservation(
                region: NormalizedRect(x: 0.11, y: 0.2, width: 0.2, height: 0.3),
                confidence: 0.9,
                label: "lamp",
                entityID: "frame-2-entity-3"
            )],
            frameId: "f2"
        )
        let reference = registry.entityReferences()[0]
        XCTAssertEqual(reference.trackID, trackID, "session identity must stay stable across frames")
        XCTAssertEqual(reference.entityID, "frame-2-entity-3", "frame-local entity id is not the track id")
        XCTAssertEqual(reference.frameID, "f2")
        XCTAssertEqual(reference.displayLabel, "lamp")
        XCTAssertNotEqual(reference.entityID, reference.trackID)
    }

    func testSafeDisplayLabelSanitizesUntrustedProviderText() {
        XCTAssertNil(SubjectEntityReference.safeDisplayLabel(nil))
        XCTAssertNil(SubjectEntityReference.safeDisplayLabel("   \n\t "))
        XCTAssertEqual(
            SubjectEntityReference.safeDisplayLabel("  \u{0007}lamp\u{200B}  "),
            "lamp"
        )
        XCTAssertEqual(
            SubjectEntityReference.safeDisplayLabel(String(repeating: "a", count: 100))?.count,
            64
        )
    }
}
