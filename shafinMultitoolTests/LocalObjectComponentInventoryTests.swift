import XCTest
import CoreMedia
@testable import shafinMultitool

final class LocalObjectComponentInventoryTests: XCTestCase {
    private let frameID = "accepted-still"
    private let capturedAt = Date(timeIntervalSince1970: 1_790_000_000)
    private let left = CGRect(x: 0.08, y: 0.17, width: 0.18, height: 0.31)
    private let right = CGRect(x: 0.64, y: 0.53, width: 0.21, height: 0.29)

    func testActualAggregatorRetainsBothSameLabelComponentsAndVisionRegions() throws {
        let detections = siblings() + [object("wall", CGRect(x: 0, y: 0, width: 1, height: 1))]
        let snapshot = snapshot(detections)
        let inventory = try XCTUnwrap(snapshot.objects.localComponentInventory)
        XCTAssertTrue(inventory.isValid)
        XCTAssertEqual(snapshot.objects.totalCount, 2, "Keep existing foreground eligibility semantics")
        XCTAssertEqual(inventory.componentCandidateCount, 2)
        XCTAssertEqual(inventory.omittedComponentCount, 0)
        XCTAssertEqual(inventory.components.map(\.detectorLabel), ["light", "light"])
        XCTAssertEqual(Set(inventory.components.map(\.entityRef)).count, 2)
        XCTAssertTrue(inventory.components.contains { $0.region == normalized(left) })
        XCTAssertTrue(inventory.components.contains { $0.region == normalized(right) })
        XCTAssertEqual(inventory.coordinateSpace, .vision)
        XCTAssertEqual(inventory.geometrySource, .semanticComponent)
        XCTAssertEqual(inventory.detectorSourceFrameID, frameID)
        XCTAssertEqual(inventory.detectorMeasuredAt, capturedAt)
        XCTAssertEqual(inventory.geometryMeasuredAt, capturedAt)
        XCTAssertTrue(inventory.components.allSatisfy { $0.segmentationSupport == 0.8 })
    }

    func testComponentReferencesAreDeterministicWithinFrameAndCannotCreateTemporalIdentity() throws {
        let original = try XCTUnwrap(snapshot(siblings()).objects.localComponentInventory)
        let reordered = try XCTUnwrap(snapshot(Array(siblings().reversed())).objects.localComponentInventory)
        XCTAssertEqual(original.components, reordered.components)
        let next = try XCTUnwrap(snapshot(siblings(), frame: "new-frame").objects.localComponentInventory)
        XCTAssertTrue(Set(original.components.map(\.entityRef)).isDisjoint(with: next.components.map(\.entityRef)))
        let laterLens = try XCTUnwrap(snapshot(siblings(), generation: 8).objects.localComponentInventory)
        XCTAssertTrue(Set(original.components.map(\.entityRef)).isDisjoint(with: laterLens.components.map(\.entityRef)))
        let longFrame = String(repeating: "кадр/\n", count: 100)
        let ref = LocalObjectComponentInventory.entityRef(frameID: longFrame, captureGeneration: 7, ordinal: 23)
        XCTAssertLessThanOrEqual(ref.count, 128)
        XCTAssertFalse(ref.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) })
    }

    func testMissingMismatchedUnknownOrStaleProvenanceCannotPublishComponentInventory() {
        XCTAssertNil(snapshot(siblings(), includeProvenance: false).objects.localComponentInventory)
        XCTAssertNil(snapshot(siblings(), provenanceFrame: "old-frame").objects.localComponentInventory)
        XCTAssertNil(snapshot(siblings(), generation: 0).objects.localComponentInventory)
        XCTAssertNil(snapshot(siblings(), measuredOffset: -10).objects.localComponentInventory)
    }

    func testBoundedInventoryReportsOmissionsWithoutClaimingCompleteScene() throws {
        let detections = (0..<30).map { i in
            object("light", CGRect(x: 0.02 + Double(i % 6) * 0.15,
                                   y: 0.02 + Double(i / 6) * 0.17, width: 0.1, height: 0.1))
        }
        let inventory = try XCTUnwrap(snapshot(detections).objects.localComponentInventory)
        XCTAssertEqual(inventory.componentCandidateCount, 30)
        XCTAssertEqual(inventory.components.count, 24)
        XCTAssertEqual(inventory.omittedComponentCount, 6)
        XCTAssertEqual(Set(inventory.components.map(\.entityRef)).count, 24)
        XCTAssertEqual(inventory.groundedEntities(aliasing: nil).count, 24)
    }

    func testRawInvalidGeometryIsNotClampedIntoGroundedComponent() throws {
        let invalid = [object("light", CGRect(x: -0.1, y: 0.1, width: 0.2, height: 0.2)),
                       object("light", CGRect(x: 0.9, y: 0.1, width: 0.2, height: 0.2)),
                       object("light", CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2), support: 2)]
        let inventory = try XCTUnwrap(snapshot(siblings() + invalid).objects.localComponentInventory)
        XCTAssertEqual(inventory.components.count, 2)
        XCTAssertTrue(inventory.components.allSatisfy { $0.region == normalized(left) || $0.region == normalized(right) })
    }

    func testExactPrimaryAliasDoesNotCollapseSameLabelSiblingOrInventConfidence() throws {
        let inventory = try XCTUnwrap(snapshot(siblings()).objects.localComponentInventory)
        let primary = VLMGroundedEntity(entityRef: "ent-primary-subject", kind: .object, role: .primarySubject,
            region: normalized(left), detectorLabel: "light", detectorConfidence: 0.95,
            displayLabelCandidate: "лампа", displayLabelConfidence: 0.95)
        let entities = inventory.groundedEntities(aliasing: primary)
        XCTAssertEqual(entities.count, 2)
        XCTAssertEqual(entities.filter { $0.entityRef == primary.entityRef }.map(\.region), [normalized(left)])
        XCTAssertEqual(entities.filter { $0.entityRef != primary.entityRef }.map(\.region), [normalized(right)])
        XCTAssertTrue(entities.allSatisfy { $0.detectorConfidence == nil && $0.displayLabelConfidence == 0 })
        XCTAssertFalse(entities.contains { $0.displayLabelCandidate == "лампа" },
                       "A semantic support score does not justify a specific physical lamp label")
    }

    func testHistoricalSummaryDecodesAbsentInventoryAsUnknownAndRoundTripsNewInventory() throws {
        let decoder = JSONDecoder()
        let historical = try decoder.decode(FrameFeatureSnapshot.ObjectDetectionsSummary.self,
            from: Data(#"{"totalCount":2,"topKLabels":["light","light"]}"#.utf8))
        XCTAssertNil(historical.localComponentInventory)
        let current = snapshot(siblings()).objects
        XCTAssertEqual(try decoder.decode(FrameFeatureSnapshot.ObjectDetectionsSummary.self,
                                         from: JSONEncoder().encode(current)), current)
    }

    @MainActor
    func testActualPauseRequestCarriesDistinctFrameComponentsWithUnknownDetectorProbability() throws {
        let snapshot = snapshot(siblings())
        let semantics = SceneSemanticsReport(frameId: frameID, mode: .pause, sceneType: .objectInsert,
            sceneTypeConfidence: 0.8, primarySubject: .init(kind: .object, label: "light", region: normalized(left), confidence: 0.8),
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.5, backgroundClutterScore: 0.2),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.2, separationScore: 0.7),
            ambiguities: [], assumptions: [])
        let critique = CritiqueReport(frameId: frameID, mode: .pause, verdict: .mixed,
            verdictConfidence: 0.5, strengths: [], issues: [],
            summary: .init(id: "component-fixture", shortVerdict: "Insufficient context."), traceRefs: [], fallbackUsed: false)
        let plan = RecommendationPlan(frameId: frameID, mode: .pause, inputVerdict: .mixed,
            primaryAction: nil, secondaryActions: [], deferredActions: [], noChangeRationale: nil, planConfidence: 0.5)
        let request = AnalysisPipeline(reasoningProvider: nil).testingBuildPauseVisualEvidenceRequest(
            snapshot: snapshot, semantics: semantics, critique: critique, plan: plan, neuralOutcome: nil)
        let entities = request.localContext.groundedEntities.filter { $0.kind == .object }
        XCTAssertEqual(entities.count, 2)
        XCTAssertEqual(Set(entities.map(\.entityRef)).count, 2)
        XCTAssertTrue(entities.contains { $0.region == normalized(left) })
        XCTAssertTrue(entities.contains { $0.region == normalized(right) })
        XCTAssertTrue(entities.allSatisfy { $0.detectorConfidence == nil })
        XCTAssertEqual(request.localContext.frameFeatureSnapshotExcerpt["local_component_identity_scope"],
                       "current_frame_component_not_physical_instance")
        XCTAssertEqual(request.localContext.frameFeatureSnapshotExcerpt["local_component_score_semantics"],
                       "segmentation_area_support_not_probability")
        XCTAssertEqual(request.privacyTier, .structuredOnly)
        XCTAssertNil(request.visualInput)
    }

    private func object(_ label: String, _ box: CGRect, support: Double = 0.8) -> FeatureSnapshotDetectedObject {
        .init(boundingBox: box, label: label, confidence: support)
    }

    private func siblings() -> [FeatureSnapshotDetectedObject] { [object("light", left), object("light", right)] }

    private func normalized(_ box: CGRect) -> NormalizedRect {
        .init(x: Double(box.minX), y: Double(box.minY), width: Double(box.width), height: Double(box.height))
    }

    private func snapshot(_ detections: [FeatureSnapshotDetectedObject], frame: String? = nil,
                          provenanceFrame: String? = nil, generation: UInt64 = 7,
                          includeProvenance: Bool = true, measuredOffset: TimeInterval = 0) -> FrameFeatureSnapshot {
        let id = frame ?? frameID
        let provenance = includeProvenance ? FeatureSampleProvenance(
            frameID: provenanceFrame ?? id, captureGeneration: generation, orientation: .up,
            samplePresentationTimestamp: CMTime(value: 1, timescale: 30), sessionGeneration: 1) : nil
        let input = FeatureAggregationInput(frameId: id, mode: .pause, capturedAt: capturedAt,
            motionState: .still, shakeLevel: 0, vision: nil, horizon: nil, lighting: nil,
            detr: FeatureSample(value: FeatureSnapshotDetrPayload(detections: detections),
                measuredAt: capturedAt.addingTimeInterval(measuredOffset), baseConfidence: nil, provenance: provenance),
            aesthetic: nil)
        return FeatureSnapshotAggregator().makeSnapshot(from: input)
    }
}
