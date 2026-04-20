import Foundation
import XCTest
@testable import shafinMultitool

final class FrameCritiqueEngineTests: XCTestCase {
    private let engine = FrameCritiqueEngine()

    func testDeterminismWithIdenticalInput() {
        let snapshot = makeSnapshot()
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: snapshot.mode)

        let first = engine.analyze(snapshot: snapshot, semantics: semantics)
        let second = engine.analyze(snapshot: snapshot, semantics: semantics)

        XCTAssertEqual(first, second)
    }

    func testGoldenSingleFaceNearEdgeAndBacklightProducesNeedsFix() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.90, verticalOffset: 0.02, subjectAreaRatio: 0.12, saliencyLeftRightBalance: 0.5, saliencyTopBottomBalance: 0.0),
            lighting: .init(exposureBiasHint: -0.40, backlightIndex: 0.95, keyToFillRatio: nil)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.80,
            primaryKind: .face,
            primaryConfidence: 0.88,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.22, backgroundClutterScore: 0.32),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.91, separationScore: 0.22)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)

        XCTAssertEqual(report.verdict, .needsFix)
        XCTAssertTrue(report.issues.contains(where: { $0.type == .subjectTooCloseToEdge }))
        XCTAssertTrue(report.issues.contains(where: { $0.type == .backlightHidesSubject }))
    }

    func testBacklightIssueSuppressesContradictoryGoodLightStrength() {
        let snapshot = makeSnapshot(
            lighting: .init(exposureBiasHint: -0.40, backlightIndex: 0.55, keyToFillRatio: 1.2),
            composition: .init(horizontalOffset: 0.02, verticalOffset: 0.0, subjectAreaRatio: 0.20, saliencyLeftRightBalance: 0.0, saliencyTopBottomBalance: 0.0)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.82,
            primaryKind: .person,
            primaryConfidence: 0.90,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.18, backgroundClutterScore: 0.22),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.12, separationScore: 0.90)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)

        XCTAssertTrue(report.issues.contains(where: { $0.type == .backlightHidesSubject }))
        XCTAssertFalse(report.strengths.contains(where: { $0.type == .goodLightEmphasis }))
    }

    func testGoldenCenteredReadablePortraitProducesGood() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.02, verticalOffset: 0.0, subjectAreaRatio: 0.21, saliencyLeftRightBalance: 0.03, saliencyTopBottomBalance: 0.01),
            lighting: .init(exposureBiasHint: 0.02, backlightIndex: 0.18, keyToFillRatio: 1.3),
            horizon: .init(angleDegrees: 0.4, confidence: 0.92),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.86,
            primaryKind: .person,
            primaryConfidence: 0.92,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.10, backgroundClutterScore: 0.20),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.18, separationScore: 0.88)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)

        XCTAssertEqual(report.verdict, .good)
        XCTAssertTrue(report.issues.isEmpty)
        XCTAssertTrue(report.strengths.contains(where: { $0.type == .goodSubjectIsolation }))
        XCTAssertTrue(report.strengths.contains(where: { $0.type == .clearFocusHierarchy }))
    }

    func testGoldenClutteredWeakSubjectProducesExpectedIssueSet() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.45, verticalOffset: 0.0, subjectAreaRatio: 0.05, saliencyLeftRightBalance: 0.42, saliencyTopBottomBalance: 0.35),
            lighting: .init(exposureBiasHint: -0.1, backlightIndex: 0.52, keyToFillRatio: nil),
            objects: .init(totalCount: 8, topKLabels: ["person", "screen", "lamp"])
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.77,
            primaryKind: .person,
            primaryConfidence: 0.26,
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.88, backgroundClutterScore: 0.91),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.65, separationScore: 0.23)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        let types = Set(report.issues.map(\.type))

        XCTAssertTrue(types.contains(.backgroundCompetesWithSubject))
        XCTAssertTrue(types.contains(.sceneHasNoClearFocus))
        XCTAssertTrue(types.contains(.frameVisuallyOverloaded))
    }

    func testHorizonDistractsThresholdAtConfidencePointThree() {
        let baseSnapshot = makeSnapshot(
            horizon: .init(angleDegrees: 8.0, confidence: 0.29),
            composition: .init(horizontalOffset: 0.0, verticalOffset: 0.0, subjectAreaRatio: 0.2, saliencyLeftRightBalance: 0.0, saliencyTopBottomBalance: 0.0)
        )
        let semantics = makeSemantics(frameId: baseSnapshot.frameId, mode: baseSnapshot.mode)

        let lowConfidence = engine.analyze(snapshot: baseSnapshot, semantics: semantics)
        XCTAssertFalse(lowConfidence.issues.contains(where: { $0.type == .horizonDistracts }))

        let highSnapshot = makeSnapshot(
            horizon: .init(angleDegrees: 8.0, confidence: 0.30),
            composition: .init(horizontalOffset: 0.0, verticalOffset: 0.0, subjectAreaRatio: 0.2, saliencyLeftRightBalance: 0.0, saliencyTopBottomBalance: 0.0)
        )
        let highConfidence = engine.analyze(snapshot: highSnapshot, semantics: semantics)
        XCTAssertTrue(highConfidence.issues.contains(where: { $0.type == .horizonDistracts }))
    }

    func testLookSpaceAdequateNilDoesNotCreateInsufficientLookSpaceIssue() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.92, verticalOffset: 0.0, subjectAreaRatio: 0.10, saliencyLeftRightBalance: 0.8, saliencyTopBottomBalance: 0.0)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .objectInsert,
            sceneTypeConfidence: 0.81,
            primaryKind: .object,
            primaryConfidence: 0.84,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.22, backgroundClutterScore: 0.28),
            readability: .init(subjectReadable: true, lookSpaceAdequate: nil, edgePressureScore: 0.85, separationScore: 0.72)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        XCTAssertFalse(report.issues.contains(where: { $0.type == .insufficientLookSpace }))
    }

    func testDegradedModeOnlyUsesAllowedIssueSubsetAndForcesNonGood() {
        let snapshot = makeSnapshot(
            technicalFlags: [.lowSceneConfidence],
            composition: .init(horizontalOffset: 0.78, verticalOffset: 0.0, subjectAreaRatio: 0.06, saliencyLeftRightBalance: 0.6, saliencyTopBottomBalance: 0.1),
            lighting: .init(exposureBiasHint: -0.33, backlightIndex: 0.81, keyToFillRatio: nil),
            objects: .init(totalCount: 7, topKLabels: ["person", "chair", "screen"]),
            horizon: .init(angleDegrees: 9.0, confidence: 0.89)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .unknown,
            sceneTypeConfidence: 0.18,
            primaryKind: .person,
            primaryConfidence: 0.35,
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.88, backgroundClutterScore: 0.86),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.82, separationScore: 0.24),
            ambiguities: [.init(type: .weakSignal, note: "weak", candidateIds: [])]
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        let allowed: Set<IssueTypeV1> = [.horizonDistracts, .backlightHidesSubject, .subjectNotProminentEnough]

        XCTAssertTrue(report.fallbackUsed)
        XCTAssertLessThanOrEqual(report.verdictConfidence, 0.55)
        XCTAssertTrue(report.strengths.isEmpty)
        XCTAssertNotEqual(report.verdict, .good)
        XCTAssertTrue(report.issues.allSatisfy { allowed.contains($0.type) })
    }

    func testDegradedModeConvertsGoodToMixedWhenNoIssues() {
        let snapshot = makeSnapshot(technicalFlags: [.lowSceneConfidence])
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .unknown,
            sceneTypeConfidence: 0.0,
            primaryKind: .unknown,
            primaryConfidence: 0.0,
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.10, backgroundClutterScore: 0.12),
            readability: .init(subjectReadable: false, lookSpaceAdequate: nil, edgePressureScore: 0.05, separationScore: 0.90),
            ambiguities: [.init(type: .weakSignal, note: "weak", candidateIds: [])]
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)

        XCTAssertTrue(report.fallbackUsed)
        XCTAssertEqual(report.verdict, .mixed)
        XCTAssertTrue(report.strengths.isEmpty)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testIssueTypesAreUniqueAndSortedBySeverityDescending() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.8, verticalOffset: 0.0, subjectAreaRatio: 0.06, saliencyLeftRightBalance: 0.2, saliencyTopBottomBalance: 0.0),
            lighting: .init(exposureBiasHint: -0.40, backlightIndex: 0.88, keyToFillRatio: nil),
            horizon: .init(angleDegrees: 6.5, confidence: 0.9)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.84,
            primaryKind: .person,
            primaryConfidence: 0.82,
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.82, backgroundClutterScore: 0.71),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.88, separationScore: 0.30)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        let issueTypes = report.issues.map(\.type)
        let issueSeverities = report.issues.map(\.severity)

        XCTAssertEqual(Set(issueTypes).count, issueTypes.count)
        XCTAssertEqual(issueSeverities, issueSeverities.sorted(by: >))
    }

    func testStrengthsAreSortedByConfidenceThenTypeAndSequentialIds() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.0, verticalOffset: 0.0, subjectAreaRatio: 0.22, saliencyLeftRightBalance: 0.0, saliencyTopBottomBalance: 0.0),
            lighting: .init(exposureBiasHint: 0.0, backlightIndex: 0.15, keyToFillRatio: 1.2),
            horizon: .init(angleDegrees: 0.0, confidence: 0.80),
            objects: .init(totalCount: 1, topKLabels: ["person"])
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.80,
            primaryKind: .person,
            primaryConfidence: 0.80,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.10, backgroundClutterScore: 0.10),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.12, separationScore: 0.90)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        let strengths = report.strengths

        XCTAssertFalse(strengths.isEmpty)
        XCTAssertEqual(Set(strengths.map(\.type)).count, strengths.count)

        let confidences = strengths.map(\.confidence)
        XCTAssertEqual(confidences, confidences.sorted(by: >))

        for index in 1..<strengths.count {
            let prev = strengths[index - 1]
            let next = strengths[index]
            if abs(prev.confidence - next.confidence) < 0.0001 {
                XCTAssertLessThanOrEqual(prev.type.rawValue, next.type.rawValue)
            }
        }

        let expectedIds = (1...strengths.count).map { offset in
            "str_\(snapshot.frameId)_\(String(format: "%02d", offset))"
        }
        XCTAssertEqual(strengths.map(\.id), expectedIds)
    }

    func testTraceRefsContainIssueStrengthAndSummarySeeds() {
        let snapshot = makeSnapshot()
        let semantics = makeSemantics(frameId: snapshot.frameId, mode: snapshot.mode)
        let report = engine.analyze(snapshot: snapshot, semantics: semantics)

        let summarySeed = "trc_\(snapshot.frameId)_crit_summary_main"
        XCTAssertTrue(report.traceRefs.contains(summarySeed))

        for idx in 1...report.issues.count {
            let seed = "trc_\(snapshot.frameId)_crit_i\(String(format: "%02d", idx))"
            XCTAssertTrue(report.traceRefs.contains(seed))
        }
        for idx in 1...report.strengths.count {
            let seed = "trc_\(snapshot.frameId)_crit_s\(String(format: "%02d", idx))"
            XCTAssertTrue(report.traceRefs.contains(seed))
        }
    }

    func testInvalidExternalSemanticsGuardEnablesNoClearFocusIssue() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.3, verticalOffset: 0.0, subjectAreaRatio: 0.15, saliencyLeftRightBalance: 0.2, saliencyTopBottomBalance: 0.0)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.70,
            primaryKind: .person,
            primaryConfidence: 0.40,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.90, backgroundClutterScore: 0.80),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.6, separationScore: 0.4)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        XCTAssertTrue(report.issues.contains(where: { $0.type == .sceneHasNoClearFocus }))
    }

    func testEvidenceAndFixTypesArePresentForAllIssues() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.88, verticalOffset: 0.0, subjectAreaRatio: 0.1, saliencyLeftRightBalance: 0.4, saliencyTopBottomBalance: 0.0),
            lighting: .init(exposureBiasHint: -0.33, backlightIndex: 0.79, keyToFillRatio: nil)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.78,
            primaryKind: .person,
            primaryConfidence: 0.82,
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.61, backgroundClutterScore: 0.66),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.9, separationScore: 0.32)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        XCTAssertFalse(report.issues.isEmpty)
        for issue in report.issues {
            XCTAssertFalse(issue.evidence.isEmpty)
            XCTAssertFalse(issue.suggestedFixTypes.isEmpty)
            if let region = issue.affectedRegion {
                XCTAssertFalse(region.isDegenerate)
            }
        }
    }

    func testAmbiguityBoostCanPromoteNoClearFocusIssueByPointFifteen() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.1, verticalOffset: 0.0, subjectAreaRatio: 0.12, saliencyLeftRightBalance: 0.1, saliencyTopBottomBalance: 0.0)
        )
        let baseSemantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.80,
            primaryKind: .person,
            primaryConfidence: 0.50,
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.40, backgroundClutterScore: 0.40),
            readability: .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.2, separationScore: 0.6),
            ambiguities: []
        )
        let withAmbiguity = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: baseSemantics.sceneType,
            sceneTypeConfidence: baseSemantics.sceneTypeConfidence,
            primaryKind: baseSemantics.primarySubject.kind,
            primaryConfidence: baseSemantics.primarySubject.confidence,
            dominance: baseSemantics.dominance,
            readability: baseSemantics.readability,
            ambiguities: [.init(type: .multipleSubjectsSimilarConfidence, note: "close candidates", candidateIds: ["a", "b"])]
        )

        let withoutAmbiguity = engine.analyze(snapshot: snapshot, semantics: baseSemantics)
        let withAmbiguityReport = engine.analyze(snapshot: snapshot, semantics: withAmbiguity)
        let rawWithoutAmbiguity = engine.rawIssueScoreForTesting(
            type: .sceneHasNoClearFocus,
            snapshot: snapshot,
            semantics: baseSemantics
        )
        let rawWithAmbiguity = engine.rawIssueScoreForTesting(
            type: .sceneHasNoClearFocus,
            snapshot: snapshot,
            semantics: withAmbiguity
        )

        guard let rawWithoutAmbiguity, let rawWithAmbiguity else {
            XCTFail("Expected raw score for scene_has_no_clear_focus")
            return
        }

        XCTAssertFalse(withoutAmbiguity.issues.contains(where: { $0.type == .sceneHasNoClearFocus }))
        XCTAssertTrue(withAmbiguityReport.issues.contains(where: { $0.type == .sceneHasNoClearFocus }))
        XCTAssertEqual(rawWithAmbiguity - rawWithoutAmbiguity, 0.15, accuracy: 0.0001)
    }

    func testEstablishingLikeFrameModerateClutterAvoidsVisualOverloadIssue() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.25, verticalOffset: 0.0, subjectAreaRatio: 0.14, saliencyLeftRightBalance: 0.2, saliencyTopBottomBalance: 0.0),
            objects: .init(totalCount: 4, topKLabels: ["building", "tree", "car"])
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .establishingLikeFrame,
            sceneTypeConfidence: 0.82,
            primaryKind: .object,
            primaryConfidence: 0.72,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.35, backgroundClutterScore: 0.56),
            readability: .init(subjectReadable: true, lookSpaceAdequate: nil, edgePressureScore: 0.28, separationScore: 0.66)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        XCTAssertFalse(report.issues.contains(where: { $0.type == .frameVisuallyOverloaded }))
    }

    func testSceneTypeTieReducesConfidenceForSceneDependentIssueByTenPercent() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.62, verticalOffset: 0.0, subjectAreaRatio: 0.01, saliencyLeftRightBalance: 0.4, saliencyTopBottomBalance: 0.0)
        )
        let baseSemantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.83,
            primaryKind: .person,
            primaryConfidence: 0.80,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.35, backgroundClutterScore: 0.42),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.5, separationScore: 0.1),
            ambiguities: []
        )
        let tieSemantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: baseSemantics.sceneType,
            sceneTypeConfidence: baseSemantics.sceneTypeConfidence,
            primaryKind: baseSemantics.primarySubject.kind,
            primaryConfidence: baseSemantics.primarySubject.confidence,
            dominance: baseSemantics.dominance,
            readability: baseSemantics.readability,
            ambiguities: [.init(type: .sceneTypeTie, note: "scene tie", candidateIds: ["a", "b"])]
        )

        let withoutTie = engine.analyze(snapshot: snapshot, semantics: baseSemantics)
        let withTie = engine.analyze(snapshot: snapshot, semantics: tieSemantics)

        let type: IssueTypeV1 = .subjectNotProminentEnough
        guard let baseIssue = withoutTie.issues.first(where: { $0.type == type }),
              let tieIssue = withTie.issues.first(where: { $0.type == type }) else {
            XCTFail("Expected \(type.rawValue) issue in both reports")
            return
        }

        XCTAssertEqual(tieIssue.confidence, baseIssue.confidence * 0.90, accuracy: 0.0001)
    }

    func testUnknownSubjectDoesNotCreateInsufficientLookSpaceIssue() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.95, verticalOffset: 0.0, subjectAreaRatio: 0.08, saliencyLeftRightBalance: 0.7, saliencyTopBottomBalance: 0.0)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.76,
            primaryKind: .unknown,
            primaryConfidence: 0.0,
            dominance: .init(hasClearFocus: false, focusCompetitionScore: 0.68, backgroundClutterScore: 0.52),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.84, separationScore: 0.35)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        XCTAssertFalse(report.issues.contains(where: { $0.type == .insufficientLookSpace }))
    }

    func testHighMotionInLiveReducesCompositionIssueSeverity() {
        let baseSnapshot = makeSnapshot(
            mode: .live,
            technicalFlags: [],
            composition: .init(horizontalOffset: 0.80, verticalOffset: 0.0, subjectAreaRatio: 0.14, saliencyLeftRightBalance: 0.3, saliencyTopBottomBalance: 0.0)
        )
        let movingSnapshot = makeSnapshot(
            mode: .live,
            technicalFlags: [.highMotion],
            composition: baseSnapshot.composition
        )
        let semantics = makeSemantics(
            frameId: baseSnapshot.frameId,
            mode: .live,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.84,
            primaryKind: .person,
            primaryConfidence: 0.88,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.2, backgroundClutterScore: 0.3),
            readability: .init(subjectReadable: false, lookSpaceAdequate: false, edgePressureScore: 0.90, separationScore: 0.45)
        )

        let baseReport = engine.analyze(snapshot: baseSnapshot, semantics: semantics)
        let movingReport = engine.analyze(snapshot: movingSnapshot, semantics: semantics)

        guard let baseIssue = baseReport.issues.first(where: { $0.type == .subjectTooCloseToEdge }),
              let movingIssue = movingReport.issues.first(where: { $0.type == .subjectTooCloseToEdge }) else {
            XCTFail("Expected subject_too_close_to_edge issue in both reports")
            return
        }

        XCTAssertLessThan(movingIssue.severity, baseIssue.severity)
        XCTAssertEqual(movingIssue.severity, baseIssue.severity * 0.92, accuracy: 0.0001)
    }

    func testGoodVerdictIsBlockedWhenCriticalIssueExists() {
        let snapshot = makeSnapshot(
            composition: .init(horizontalOffset: 0.95, verticalOffset: 0.0, subjectAreaRatio: 0.12, saliencyLeftRightBalance: 0.5, saliencyTopBottomBalance: 0.0)
        )
        let semantics = makeSemantics(
            frameId: snapshot.frameId,
            mode: snapshot.mode,
            sceneType: .singleCharacterMedium,
            sceneTypeConfidence: 0.88,
            primaryKind: .person,
            primaryConfidence: 0.90,
            dominance: .init(hasClearFocus: true, focusCompetitionScore: 0.12, backgroundClutterScore: 0.24),
            readability: .init(subjectReadable: true, lookSpaceAdequate: false, edgePressureScore: 0.96, separationScore: 0.86)
        )

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)
        XCTAssertTrue(report.issues.contains(where: { $0.severity >= CritiqueReport.criticalIssueThreshold }))
        XCTAssertNotEqual(report.verdict, .good)
    }

    func testMismatchedFrameIdAndModeAreAlignedToSnapshot() {
        let snapshot = makeSnapshot(frameId: "snapshot-id", mode: .pause)
        let semantics = makeSemantics(frameId: "other-id", mode: .live)

        let report = engine.analyze(snapshot: snapshot, semantics: semantics)

        XCTAssertEqual(report.frameId, snapshot.frameId)
        XCTAssertEqual(report.mode, snapshot.mode)
    }
}

private extension FrameCritiqueEngineTests {
    func makeSnapshot(
        frameId: String = "f-crit-1",
        mode: AnalysisMode = .pause,
        technicalFlags: [TechnicalFlag] = [],
        composition: FrameFeatureSnapshot.CompositionFeatures = .init(
            horizontalOffset: 0.18,
            verticalOffset: 0.0,
            subjectAreaRatio: 0.18,
            saliencyLeftRightBalance: 0.1,
            saliencyTopBottomBalance: 0.0
        ),
        lighting: FrameFeatureSnapshot.LightingFeatures = .init(exposureBiasHint: -0.05, backlightIndex: 0.35, keyToFillRatio: 1.1),
        horizon: FrameFeatureSnapshot.HorizonFeatures = .init(angleDegrees: 1.2, confidence: 0.86),
        objects: FrameFeatureSnapshot.ObjectDetectionsSummary = .init(totalCount: 3, topKLabels: ["person", "chair", "screen"])
    ) -> FrameFeatureSnapshot {
        FrameFeatureSnapshot(
            frameId: frameId,
            mode: mode,
            capturedAt: Date(timeIntervalSince1970: 1_768_100_000),
            sources: .init(
                vision: .init(available: true, freshnessMs: 30, confidence: 0.88),
                horizon: .init(available: true, freshnessMs: 25, confidence: 0.86),
                lighting: .init(available: true, freshnessMs: 40, confidence: 0.84),
                detr: .init(available: true, freshnessMs: 600, confidence: 0.80),
                aesthetic: .init(available: true, freshnessMs: 1200, confidence: 0.7)
            ),
            composition: composition,
            subjectSignals: .init(
                faceDetected: true,
                personDetected: true,
                personCount: 1,
                topObjectLabel: "person",
                topObjectConfidence: 0.8,
                primaryCandidateRegion: .init(x: 0.32, y: 0.2, width: 0.30, height: 0.52),
                primaryCandidateConfidence: 0.9
            ),
            horizon: horizon,
            lighting: lighting,
            motion: .init(state: mode == .live ? .moving : .still, shakeLevel: mode == .live ? 0.4 : 0.1),
            aesthetics: .init(score: 0.65, scoreConfidence: 0.74),
            objects: objects,
            technicalFlags: technicalFlags
        )
    }

    func makeSemantics(
        frameId: String,
        mode: AnalysisMode,
        sceneType: SceneTypeV1 = .singleCharacterMedium,
        sceneTypeConfidence: Double = 0.82,
        primaryKind: SubjectKind = .person,
        primaryConfidence: Double = 0.88,
        dominance: SceneSemanticsReport.VisualDominanceState = .init(hasClearFocus: true, focusCompetitionScore: 0.2, backgroundClutterScore: 0.3),
        readability: SceneSemanticsReport.SemanticReadabilityState = .init(subjectReadable: true, lookSpaceAdequate: true, edgePressureScore: 0.22, separationScore: 0.76),
        ambiguities: [SemanticsAmbiguity] = []
    ) -> SceneSemanticsReport {
        SceneSemanticsReport(
            frameId: frameId,
            mode: mode,
            sceneType: sceneType,
            sceneTypeConfidence: sceneTypeConfidence,
            primarySubject: .init(
                kind: primaryKind,
                label: primaryKind == .object ? "object" : nil,
                region: primaryKind == .unknown ? nil : .init(x: 0.32, y: 0.2, width: 0.30, height: 0.52),
                confidence: primaryConfidence,
                competingCandidates: []
            ),
            dominance: dominance,
            readability: readability,
            ambiguities: ambiguities,
            assumptions: []
        )
    }
}
