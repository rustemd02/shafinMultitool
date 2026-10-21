import AVFoundation
import CoreMedia
import CoreVideo
import Combine
import Foundation
import XCTest
@testable import shafinMultitool

/// Local semantics are injected at the completed-analysis boundary. These tests
/// qualify the selected-still request, S1 admission, existing planner and actual
/// CameraViewModel pause projection; they do not claim model/perception accuracy.
@MainActor
final class CameraCloudPauseIntegrationTests: XCTestCase {
    func testCloudObservationsPreserveExplicitImageGoalAndLateOldReplyCannotReplaceIt() async throws {
        let fixture = try makeFixture(holdResponse: true)
        try await startAnalysis(fixture)
        let goal = CaptureImagePlacementGoal(
            snapshotID: fixture.accepted.snapshotID, frameID: fixture.accepted.sourceFrameId,
            entityRef: "user-roi-" + UUID().uuidString,
            observedRegion: .init(x: 0.1, y: 0.4, width: 0.2, height: 0.2), source: .userRegion
        )
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(goal, expectedSnapshotID: fixture.accepted.snapshotID))
        let local = fixture.viewModel.pausePresentationState
        fixture.client.releaseResponse()
        await assertEventually { fixture.client.finishedCount == 1 }
        await Task.yield()
        XCTAssertEqual(fixture.viewModel.pausePresentationState, local)
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal?.goal, goal)
        XCTAssertTrue(fixture.viewModel.canRequestCloudPauseAnalysis)
        try await startAnalysis(fixture)
        fixture.client.releaseResponse()
        await assertEventually { fixture.viewModel.cloudReviewState == .complete }
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal?.goal, goal)
        XCTAssertFalse(try XCTUnwrap(fixture.viewModel.pauseImagePlacementProposal).isActiveReviewSuggestion)
        let acceptedCloud = fixture.viewModel.pausePresentationState
        XCTAssertTrue(try XCTUnwrap(fixture.viewModel.pauseCritique).actions.contains {
            $0.semanticActionType == .waitForBackgroundClearance
        })
        let changed = CaptureImagePlacementGoal(
            snapshotID: goal.snapshotID, frameID: goal.frameID, entityRef: goal.entityRef,
            observedRegion: .init(x: 0.2, y: 0.4, width: 0.2, height: 0.2), source: .userRegion
        )
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(changed, expectedSnapshotID: goal.snapshotID))
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal?.goal, changed)
        XCTAssertEqual(fixture.viewModel.pausePresentationState, acceptedCloud,
                       "A pure placement edit preserves the exact accepted cloud critique")
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(nil, expectedSnapshotID: goal.snapshotID))
        XCTAssertEqual(fixture.viewModel.pausePresentationState, acceptedCloud)
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(changed, expectedSnapshotID: goal.snapshotID))
        XCTAssertNil(fixture.viewModel.verificationResult)
        XCTAssertEqual(fixture.viewModel.coachingEpisodeState, .idle)
        fixture.viewModel.reportSceneInactive()
        XCTAssertNil(fixture.viewModel.pauseImagePlacementProposal)
        XCTAssertNotNil(fixture.viewModel.acceptedPauseSnapshot)
        await fixture.viewModel.releaseAndWait()
    }

    func testImagePlacementPreservesAcceptedGoodVerdictWithoutInventingIssue() async throws {
        let fixture = try makeFixture(goodFrame: true)
        let before = try XCTUnwrap(fixture.viewModel.pauseCritique)
        XCTAssertEqual(before.verdict, .good)
        let goal = CaptureImagePlacementGoal(
            snapshotID: fixture.accepted.snapshotID, frameID: fixture.accepted.sourceFrameId,
            entityRef: "user-roi-" + UUID().uuidString,
            observedRegion: .init(x: 0.1, y: 0.4, width: 0.2, height: 0.2), source: .userRegion
        )
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(goal, expectedSnapshotID: fixture.accepted.snapshotID))
        let after = try XCTUnwrap(fixture.viewModel.pauseCritique)
        XCTAssertEqual(after.verdict, .good)
        XCTAssertEqual(after.verdictConfidence, before.verdictConfidence)
        XCTAssertEqual(after.issues, before.issues)
        XCTAssertEqual(after.technicalQualityMeasurement, before.technicalQualityMeasurement)
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal?.isActiveReviewSuggestion, true)
        XCTAssertNil(fixture.viewModel.verificationResult)
        XCTAssertEqual(fixture.viewModel.coachingEpisodeState, .idle)
        XCTAssertEqual(fixture.client.analysisCount, 0)
        await fixture.viewModel.releaseAndWait()
    }

    func testImagePlacementRemainsSavedIntentWhenTechnicalAdviceHasPriority() async throws {
        // Injected signal at the completed-analysis boundary; no claim that
        // the generated fixture image was measured as underexposed.
        let signal = TechnicalQualitySignal(issues: [
            .init(type: .underexposure, actionType: .increaseExposure, confidence: 0.9,
                  severity: 0.9, isDominant: true)
        ])
        let fixture = try makeFixture(technicalSignalOverride: signal, isolateTechnicalSignal: true)
        fixture.viewModel.answerPauseSceneControl(category: .lighting, state: .forbidden,
                                                  expectedSnapshotID: fixture.accepted.snapshotID)
        let before = try XCTUnwrap(fixture.viewModel.pauseCritique)
        XCTAssertEqual(before.summaryId, "technical_quality_underexposure")
        let goal = CaptureImagePlacementGoal(
            snapshotID: fixture.accepted.snapshotID, frameID: fixture.accepted.sourceFrameId,
            entityRef: "user-roi-" + UUID().uuidString,
            observedRegion: .init(x: 0.1, y: 0.4, width: 0.2, height: 0.2), source: .userRegion
        )
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(goal, expectedSnapshotID: fixture.accepted.snapshotID))
        let after = try XCTUnwrap(fixture.viewModel.pauseCritique)
        XCTAssertEqual(after, before)
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal?.goal, goal)
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal?.isActiveReviewSuggestion, false)
        XCTAssertNil(fixture.viewModel.verificationResult)
        await fixture.viewModel.releaseAndWait()
    }

    func testImagePlacementReachesActualPauseWithoutPhysicalControlOrCompletion() async throws {
        let fixture = try makeFixture()
        let before = try XCTUnwrap(fixture.viewModel.pauseCritique)
        let oldContext = try XCTUnwrap(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        fixture.viewModel.answerPauseSceneControl(category: .objects, state: .forbidden,
                                                  expectedSnapshotID: fixture.accepted.snapshotID)
        let goal = CaptureImagePlacementGoal(
            snapshotID: fixture.accepted.snapshotID, frameID: fixture.accepted.sourceFrameId,
            entityRef: "user-roi-" + UUID().uuidString,
            observedRegion: .init(x: 0.05, y: 0.3, width: 0.2, height: 0.4), source: .userRegion
        )
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(goal, expectedSnapshotID: fixture.accepted.snapshotID))
        let proposal = try XCTUnwrap(fixture.viewModel.pauseImagePlacementProposal)
        XCTAssertEqual(proposal.goal, goal)
        XCTAssertFalse(proposal.isActiveReviewSuggestion, "Existing supported advice retains priority")
        XCTAssertEqual(fixture.viewModel.pauseSceneControlFacts.objects, .forbidden)
        guard case let .success(id, displayed) = fixture.viewModel.pausePresentationState else {
            return XCTFail("Actual accepted pause must publish the refreshed presentation")
        }
        XCTAssertEqual(id, fixture.accepted.snapshotID)
        XCTAssertEqual(displayed, fixture.pipeline.currentPauseCritique)
        XCTAssertEqual(displayed.verdict, before.verdict)
        XCTAssertEqual(displayed.verdictConfidence, before.verdictConfidence)
        XCTAssertEqual(displayed.technicalQualityMeasurement, before.technicalQualityMeasurement)
        let selectedContext = try XCTUnwrap(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        XCTAssertEqual(selectedContext.imagePlacementRevision, proposal.intentRevision)
        XCTAssertFalse(fixture.pipeline.isCurrentCloudPauseContext(oldContext, acceptedSnapshot: fixture.accepted))
        XCTAssertNil(fixture.viewModel.verificationResult)
        XCTAssertEqual(fixture.viewModel.coachingEpisodeState, .idle)
        XCTAssertEqual(fixture.client.analysisCount, 0)
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(goal, expectedSnapshotID: fixture.accepted.snapshotID))
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal?.intentRevision, proposal.intentRevision)
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(nil, expectedSnapshotID: fixture.accepted.snapshotID))
        XCTAssertNil(fixture.viewModel.pauseImagePlacementProposal)
        let resetContext = try XCTUnwrap(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        XCTAssertNotEqual(resetContext.imagePlacementRevision, oldContext.imagePlacementRevision)
        XCTAssertFalse(fixture.pipeline.isCurrentCloudPauseContext(oldContext, acceptedSnapshot: fixture.accepted))
        await fixture.viewModel.releaseAndWait()
    }

    func testImagePlacementRejectsStaleFrameAndCannotSubstituteObservedRegion() async throws {
        let fixture = try makeFixture(holdResponse: true)
        let candidate = try XCTUnwrap(fixture.viewModel.pauseImagePlacementCandidates.first)
        let exact = CaptureImagePlacementGoal(
            snapshotID: fixture.accepted.snapshotID, frameID: fixture.accepted.sourceFrameId,
            entityRef: candidate.id, observedRegion: candidate.region, source: .observedRegion
        )
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(exact, expectedSnapshotID: exact.snapshotID))
        let initialProposal = fixture.viewModel.pauseImagePlacementProposal
        try await startAnalysis(fixture)
        XCTAssertEqual(fixture.viewModel.cloudReviewState, .analyzing)
        XCTAssertFalse(fixture.viewModel.setPauseImagePlacement(exact, expectedSnapshotID: "stale-snapshot"))
        let wrongFrame = CaptureImagePlacementGoal(
            snapshotID: exact.snapshotID, frameID: "stale-frame", entityRef: exact.entityRef,
            observedRegion: exact.observedRegion, source: .observedRegion
        )
        XCTAssertFalse(fixture.viewModel.setPauseImagePlacement(wrongFrame, expectedSnapshotID: exact.snapshotID))
        let wrongRegion = CaptureImagePlacementGoal(
            snapshotID: exact.snapshotID, frameID: exact.frameID, entityRef: exact.entityRef,
            observedRegion: .init(x: 0.7, y: 0.2, width: 0.2, height: 0.4), source: .observedRegion
        )
        XCTAssertFalse(fixture.viewModel.setPauseImagePlacement(wrongRegion, expectedSnapshotID: exact.snapshotID))
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal, initialProposal)
        XCTAssertEqual(fixture.viewModel.cloudReviewState, .analyzing,
                       "Rejected input must not cancel an admitted current request")
        XCTAssertTrue(fixture.viewModel.setPauseImagePlacement(exact, expectedSnapshotID: exact.snapshotID))
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal, initialProposal)
        XCTAssertEqual(fixture.viewModel.cloudReviewState, .analyzing,
                       "Saving an unchanged goal must not cancel or restart the request")
        XCTAssertEqual(fixture.client.analysisCount, 1)
        fixture.client.releaseResponse()
        await assertEventually { fixture.viewModel.cloudReviewState == .complete }
        XCTAssertEqual(fixture.viewModel.pauseImagePlacementProposal?.goal, exact)
        let newer = try makeFixture(reusingPipeline: fixture.pipeline)
        XCTAssertFalse(fixture.viewModel.setPauseImagePlacement(exact, expectedSnapshotID: exact.snapshotID))
        XCTAssertNil(newer.viewModel.pauseImagePlacementProposal)
        XCTAssertNil(newer.viewModel.verificationResult)
        await fixture.viewModel.releaseAndWait()
        await newer.viewModel.releaseAndWait()
    }

    func testEmptyEvidencePreservesExactLocalPresentationWithoutPublishing() async throws {
        try await assertNoEvidencePreservesLocalPresentation(abstained: false)
    }

    func testAbstainedEvidencePreservesExactLocalPresentationWithoutPublishing() async throws {
        try await assertNoEvidencePreservesLocalPresentation(abstained: true)
    }

    private func assertNoEvidencePreservesLocalPresentation(abstained: Bool) async throws {
        let fixture = try makeFixture(emptyResponse: true, abstained: abstained)
        let original = fixture.viewModel.pausePresentationState
        let localCritique = fixture.pipeline.currentPauseCritique
        var publications = 0
        let subscription = fixture.pipeline.$currentPauseCritique.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        try await startAnalysis(fixture)
        await assertEventually { fixture.viewModel.cloudReviewState == .noAdditionalEvidence }
        XCTAssertEqual(publications, 0, "An empty reply must not replace local/refined wording")
        XCTAssertEqual(fixture.pipeline.currentPauseCritique, localCritique)
        XCTAssertEqual(fixture.viewModel.pausePresentationState, original)
        XCTAssertEqual(fixture.viewModel.pauseCritique, localCritique)
        await fixture.viewModel.releaseAndWait()
    }

    func testActualIntentAnswerInvalidatesOldLocalContextBeforeAnotherDisclosure() async throws {
        let fixture = try makeFixture(pendingTilt: true)
        let original = try XCTUnwrap(fixture.pipeline.currentPauseCritique)
        XCTAssertTrue(original.actions.contains { $0.semanticActionType == .levelHorizon })
        XCTAssertEqual(fixture.pipeline.pendingIntentClarificationCue, .tilt)
        XCTAssertNotNil(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        fixture.viewModel.answerIntentClarification(intended: true)
        XCTAssertEqual(fixture.pipeline.testingIntentAnswer(for: .tilt), true)
        XCTAssertNil(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        XCTAssertFalse(fixture.viewModel.canRequestCloudPauseAnalysis)
        fixture.viewModel.requestCloudPauseAnalysis(locale: "en")
        await Task.yield()
        XCTAssertNil(fixture.viewModel.pendingCloudTransfer)
        XCTAssertEqual(fixture.client.analysisCount, 0)
        guard case let .success(snapshotID, displayed) = fixture.viewModel.pausePresentationState else {
            return XCTFail("Intent refresh must reach the actual associated pause review")
        }
        XCTAssertEqual(snapshotID, fixture.accepted.snapshotID)
        XCTAssertEqual(displayed, fixture.pipeline.currentPauseCritique)
        XCTAssertEqual(displayed, fixture.viewModel.pauseCritique)
        XCTAssertFalse(displayed.actions.contains { $0.semanticActionType == .levelHorizon })
        XCTAssertTrue(displayed.intentionalStylePreserved)
        XCTAssertEqual(displayed.verdict, original.verdict)
        XCTAssertEqual(displayed.verdictConfidence, original.verdictConfidence)
        XCTAssertEqual(displayed.technicalQualityMeasurement, original.technicalQualityMeasurement)
        XCTAssertNil(displayed.linkedEvidence)
        for locale in [Locale(identifier: "ru"), Locale(identifier: "en")] {
            XCTAssertEqual(SETLocalizedPauseCopy.summary(for: displayed, locale: locale),
                           SETCopyKey.pauseIntentPreserved.localizedString(locale: locale))
        }
        await fixture.viewModel.releaseAndWait()
    }

    func testNegativeIntentAnswerKeepsSupportedCorrection() async throws {
        let fixture = try makeFixture(pendingTilt: true)
        fixture.viewModel.answerIntentClarification(intended: false)
        guard case let .success(_, displayed) = fixture.viewModel.pausePresentationState else {
            return XCTFail("Expected accepted review")
        }
        XCTAssertTrue(displayed.actions.contains { $0.semanticActionType == .levelHorizon })
        XCTAssertFalse(displayed.intentionalStylePreserved)
        XCTAssertNil(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        XCTAssertEqual(fixture.client.analysisCount, 0)
        await fixture.viewModel.releaseAndWait()
    }

    func testIntentAnswerDoesNotPromoteUnavailableLocalAssessment() async throws {
        let fixture = try makeFixture(localAvailable: false, pendingTilt: true)
        let original = try XCTUnwrap(fixture.pipeline.currentPauseCritique)
        fixture.viewModel.answerIntentClarification(intended: true)
        let displayed = try XCTUnwrap(fixture.viewModel.pauseCritique)
        XCTAssertEqual(displayed.verdict, original.verdict)
        XCTAssertEqual(displayed.verdictConfidence, original.verdictConfidence)
        XCTAssertEqual(displayed.technicalQualityMeasurement, original.technicalQualityMeasurement)
        XCTAssertFalse(displayed.actions.contains { $0.semanticActionType == .levelHorizon })
        XCTAssertEqual(fixture.client.analysisCount, 0)
        await fixture.viewModel.releaseAndWait()
    }

    func testSelectedStillEvidenceReachesPublishedPauseActionInBothLanguages() async throws {
        for locale in ["ru", "en"] {
            let fixture = try makeFixture()
            let original = try XCTUnwrap(fixture.pipeline.currentPauseCritique)
            XCTAssertFalse(original.actions.contains { $0.semanticActionType == .waitForBackgroundClearance })
            XCTAssertTrue(fixture.viewModel.isPauseProjectionReady)
            XCTAssertTrue(fixture.viewModel.canRequestCloudPauseAnalysis)

            fixture.viewModel.requestCloudPauseAnalysis(locale: locale)
            let disclosed = await waitUntil { fixture.viewModel.pendingCloudTransfer != nil }
            XCTAssertTrue(disclosed)
            let transfer = try XCTUnwrap(fixture.viewModel.pendingCloudTransfer)
            XCTAssertEqual(fixture.client.analysisCount, 0, "Preparation/disclosure cannot send content")
            XCTAssertEqual(transfer.snapshotID, fixture.accepted.snapshotID)
            XCTAssertEqual(transfer.mediaSHA256, CameraCloudTransferPolicy.sha256(transfer.jpegData))
            XCTAssertGreaterThan(transfer.byteCount, 0)

            fixture.viewModel.approveCloudPauseAnalysis(transfer.approval)
            let completed = await waitUntil { fixture.viewModel.cloudReviewState == .complete }
            XCTAssertTrue(completed, "Actual evidence must be useful through the published pause owner")
            guard case let .success(snapshotID, displayed) = fixture.viewModel.pausePresentationState else {
                return XCTFail("Production reads the critique associated with .success")
            }
            XCTAssertEqual(snapshotID, fixture.accepted.snapshotID)
            XCTAssertEqual(displayed, fixture.pipeline.currentPauseCritique)
            XCTAssertEqual(displayed, fixture.viewModel.pauseCritique)
            XCTAssertEqual(displayed.frameId, fixture.accepted.sourceFrameId)
            XCTAssertEqual(displayed.verdict, original.verdict)
            XCTAssertEqual(displayed.issues.map(\.issueId), original.issues.map(\.issueId))
            XCTAssertTrue(displayed.actions.contains { $0.semanticActionType == .waitForBackgroundClearance })
            XCTAssertEqual(fixture.client.lastLocale, locale)
            XCTAssertNil(fixture.viewModel.pendingCloudTransfer)
            XCTAssertNil(fixture.viewModel.verificationResult)
            XCTAssertEqual(fixture.viewModel.coachingEpisodeState, .idle)
            await fixture.viewModel.releaseAndWait()
        }
    }

    func testCancelledDisclosureCannotApproveOrCancelNewerDisclosure() async throws {
        let fixture = try makeFixture()
        fixture.viewModel.requestCloudPauseAnalysis(locale: "ru")
        await assertEventually { fixture.viewModel.pendingCloudTransfer != nil }
        let old = try XCTUnwrap(fixture.viewModel.pendingCloudTransfer)
        fixture.viewModel.cancelCloudPauseAnalysis(requestID: old.requestID)
        fixture.viewModel.requestCloudPauseAnalysis(locale: "en")
        await assertEventually { fixture.viewModel.pendingCloudTransfer != nil }
        let current = try XCTUnwrap(fixture.viewModel.pendingCloudTransfer)
        XCTAssertNotEqual(old.requestID, current.requestID)
        fixture.viewModel.approveCloudPauseAnalysis(old.approval)
        fixture.viewModel.cancelCloudPauseAnalysis(requestID: old.requestID)
        XCTAssertEqual(fixture.viewModel.pendingCloudTransfer, current)
        XCTAssertEqual(fixture.viewModel.cloudReviewState, .awaitingConsent)
        XCTAssertEqual(fixture.client.analysisCount, 0)
        fixture.viewModel.cancelCloudPauseAnalysis(requestID: current.requestID)
        XCTAssertNil(fixture.viewModel.pendingCloudTransfer)
        await fixture.viewModel.releaseAndWait()
    }

    func testLateEvidenceAfterIntentRevisionDoesNotOverwriteCommittedPause() async throws {
        let fixture = try makeFixture(holdResponse: true)
        let original = fixture.viewModel.pausePresentationState
        let originalCritique = fixture.pipeline.currentPauseCritique
        try await startAnalysis(fixture)
        fixture.pipeline.recordIntentClarification(cue: .symmetry, intended: true)
        fixture.client.releaseResponse()
        await assertEventually { fixture.viewModel.cloudReviewState == .idle }
        XCTAssertEqual(fixture.viewModel.pausePresentationState, original)
        XCTAssertEqual(fixture.pipeline.currentPauseCritique, originalCritique)
        XCTAssertNil(fixture.viewModel.pendingCloudTransfer)
        await fixture.viewModel.releaseAndWait()
    }

    func testSceneInactiveCancelsAnalysisWhilePreservingAcceptedReview() async throws {
        let fixture = try makeFixture(holdResponse: true)
        let original = fixture.viewModel.pausePresentationState
        let originalCritique = fixture.pipeline.currentPauseCritique
        try await startAnalysis(fixture)
        fixture.viewModel.reportSceneInactive()
        XCTAssertEqual(fixture.viewModel.cloudReviewState, .idle)
        XCTAssertEqual(fixture.viewModel.pausePresentationState, original)
        fixture.client.releaseResponse()
        await assertEventually { fixture.client.finishedCount == 1 }
        await Task.yield()
        XCTAssertEqual(fixture.pipeline.currentPauseCritique, originalCritique)
        XCTAssertEqual(fixture.viewModel.pausePresentationState, original)
        XCTAssertEqual(fixture.viewModel.acceptedPauseSnapshot?.snapshotID, fixture.accepted.snapshotID)
        await fixture.viewModel.releaseAndWait()
    }

    func testUnavailableLocalAssessmentCannotBePromotedByValidCloudJSON() async throws {
        let fixture = try makeFixture(localAvailable: false)
        let original = fixture.viewModel.pausePresentationState
        try await startAnalysis(fixture)
        await assertEventually { fixture.viewModel.cloudReviewState == .noAdditionalEvidence }
        XCTAssertEqual(fixture.viewModel.pausePresentationState, original)
        XCTAssertNil(fixture.viewModel.verificationResult)
        await fixture.viewModel.releaseAndWait()
    }

    func testObservedTechnicalFaultCannotBeRemovedBySemanticEvidence() async throws {
        let fixture = try makeFixture(overexposed: true)
        let original = fixture.viewModel.pausePresentationState
        let measurement = TechnicalQualityAnalyzer().measurement(pixelBuffer: fixture.accepted.pixelBuffer)
        XCTAssertTrue(try XCTUnwrap(measurement.signal).issues.contains {
            $0.type == .overexposure && $0.isDominant
        })
        try await startAnalysis(fixture)
        await assertEventually { fixture.viewModel.cloudReviewState == .noAdditionalEvidence }
        XCTAssertEqual(fixture.viewModel.pausePresentationState, original)
        await fixture.viewModel.releaseAndWait()
    }

    func testReplacedPauseFenceRejectsOldRequestEvenWithSameFrameID() async throws {
        let fixture = try makeFixture(holdResponse: true)
        try await startAnalysis(fixture)
        let original = fixture.viewModel.pausePresentationState
        fixture.pipeline.clearPausePresentationState(preservingCurrentCritique: true)
        fixture.client.releaseResponse()
        await assertEventually { fixture.viewModel.cloudReviewState == .idle }
        XCTAssertEqual(fixture.viewModel.pausePresentationState, original)
        await fixture.viewModel.releaseAndWait()
    }

    func testSceneControlAnswersReachActualPauseAndStayIndependent() async throws {
        let fixture = try makeFixture(controlScene: true)
        let vm = fixture.viewModel
        let id = fixture.accepted.snapshotID
        XCTAssertTrue(vm.canClarifyPauseSceneControl)
        XCTAssertEqual(vm.pauseSceneControlFacts.objects, .unknown)
        XCTAssertFalse(try XCTUnwrap(vm.pauseCritique).actions.isEmpty, "Camera advice needs no control answer")
        let oldContext = try XCTUnwrap(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        vm.answerPauseSceneControl(category: .objects, state: .allowed, expectedSnapshotID: id)
        guard case .success(let displayedID, let displayed) = vm.pausePresentationState else {
            return XCTFail("The production pause reads its associated success payload")
        }
        XCTAssertEqual(displayedID, id)
        XCTAssertEqual(displayed, fixture.pipeline.currentPauseCritique)
        XCTAssertTrue(displayed.actions.contains { $0.semanticActionType == .moveObjectBack })
        XCTAssertEqual(vm.pauseSceneControlFacts.participants, .unknown)
        XCTAssertEqual(vm.pauseSceneControlFacts.lighting, .unknown)
        let currentContext = try XCTUnwrap(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        XCTAssertGreaterThan(currentContext.sceneControlRevision, oldContext.sceneControlRevision)
        XCTAssertFalse(fixture.pipeline.isCurrentCloudPauseContext(oldContext, acceptedSnapshot: fixture.accepted))
        vm.answerPauseSceneControl(category: .participants, state: .forbidden, expectedSnapshotID: id)
        vm.answerPauseSceneControl(category: .lighting, state: .allowed, expectedSnapshotID: id)
        XCTAssertEqual(vm.pauseSceneControlFacts.objects, .allowed)
        XCTAssertEqual(vm.pauseSceneControlFacts.participants, .forbidden)
        XCTAssertEqual(vm.pauseSceneControlFacts.lighting, .allowed)
        XCTAssertEqual(fixture.client.analysisCount, 0)
        XCTAssertNil(vm.verificationResult)
        XCTAssertEqual(vm.coachingEpisodeState, .idle)
        await vm.releaseAndWait()
    }

    func testSceneControlWrongSnapshotAndUnknownResetDoNotGrantAuthority() async throws {
        let fixture = try makeFixture(controlScene: true)
        let vm = fixture.viewModel
        let id = fixture.accepted.snapshotID
        vm.answerPauseSceneControl(category: .objects, state: .allowed, expectedSnapshotID: "old-sheet")
        XCTAssertEqual(vm.pauseSceneControlFacts.objects, .unknown)
        vm.answerPauseSceneControl(category: .objects, state: .allowed, expectedSnapshotID: id)
        vm.answerPauseSceneControl(category: .lighting, state: .forbidden, expectedSnapshotID: id)
        vm.answerPauseSceneControl(category: .objects, state: .unknown, expectedSnapshotID: id)
        XCTAssertEqual(vm.pauseSceneControlFacts.objects, .unknown)
        XCTAssertEqual(vm.pauseSceneControlFacts.lighting, .forbidden)
        XCTAssertFalse(try XCTUnwrap(vm.pauseCritique).actions.contains { $0.semanticActionType == .moveObjectBack })
        vm.resetPauseSceneControl(expectedSnapshotID: id)
        for category in PauseSceneControlFacts.Category.allCases {
            XCTAssertEqual(vm.pauseSceneControlFacts.state(for: category), .unknown)
        }
        XCTAssertNil(vm.verificationResult)
        await vm.releaseAndWait()
    }

    func testSceneControlChangeCancelsHeldCloudAndLateReplyCannotRestoreOldAdvice() async throws {
        let fixture = try makeFixture(holdResponse: true, controlScene: true)
        try await startAnalysis(fixture)
        fixture.viewModel.answerPauseSceneControl(category: .objects, state: .allowed,
                                                  expectedSnapshotID: fixture.accepted.snapshotID)
        let committed = fixture.viewModel.pausePresentationState
        XCTAssertEqual(fixture.viewModel.cloudReviewState, .idle)
        XCTAssertNil(fixture.viewModel.pendingCloudTransfer)
        fixture.client.releaseResponse()
        await assertEventually { fixture.client.finishedCount == 1 }
        await Task.yield()
        XCTAssertEqual(fixture.viewModel.pausePresentationState, committed)
        XCTAssertNil(fixture.viewModel.verificationResult)
        await fixture.viewModel.releaseAndWait()
    }

    func testSceneControlDoesNotRevalidateCloudAfterStyleIntentChanged() async throws {
        let fixture = try makeFixture(pendingTilt: true)
        fixture.viewModel.answerIntentClarification(intended: true)
        XCTAssertNil(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        fixture.viewModel.answerPauseSceneControl(category: .objects, state: .allowed,
                                                  expectedSnapshotID: fixture.accepted.snapshotID)
        XCTAssertNil(fixture.pipeline.makeCloudPauseContext(acceptedSnapshot: fixture.accepted))
        XCTAssertTrue(try XCTUnwrap(fixture.viewModel.pauseCritique).intentionalStylePreserved)
        XCTAssertEqual(fixture.client.analysisCount, 0)
        await fixture.viewModel.releaseAndWait()
    }

    func testSceneControlResetsOnBackgroundLensAndResume() async throws {
        for boundary in ["background", "lens", "resume"] {
            let fixture = try makeFixture(controlScene: true)
            let vm = fixture.viewModel
            vm.answerPauseSceneControl(category: .objects, state: .allowed,
                                       expectedSnapshotID: fixture.accepted.snapshotID)
            XCTAssertEqual(vm.pauseSceneControlFacts.objects, .allowed)
            switch boundary {
            case "background": vm.reportSceneInactive()
            case "lens": vm.switchLens(to: .ultraWide)
            default: vm.togglePause()
            }
            XCTAssertEqual(vm.pauseSceneControlFacts.objects, .unknown, boundary)
            XCTAssertFalse(vm.pauseCritique?.actions.contains { $0.semanticActionType == .moveObjectBack } ?? false, boundary)
            XCTAssertNil(vm.verificationResult)
            await vm.releaseAndWait()
        }
    }

    func testQueuedOldPauseCleanupDoesNotEraseNewAcceptedReviewOrControlFacts() async throws {
        for preserveCritique in [false, true] {
            let previous = try makeFixture(controlScene: true)
            previous.viewModel.answerPauseSceneControl(
                category: .objects, state: .allowed, expectedSnapshotID: previous.accepted.snapshotID
            )
            previous.pipeline.clearPausePresentationState(preservingCurrentCritique: preserveCritique)
            // Install the next accepted frame synchronously before the old
            // queued main-actor cleanup runs, on the same actual pipeline.
            let current = try makeFixture(controlScene: true, reusingPipeline: previous.pipeline)
            XCTAssertNotEqual(previous.accepted.snapshotID, current.accepted.snapshotID)
            XCTAssertEqual(current.viewModel.pauseSceneControlFacts.objects, .unknown)
            current.viewModel.answerPauseSceneControl(
                category: .lighting, state: .allowed, expectedSnapshotID: current.accepted.snapshotID
            )
            let context = try XCTUnwrap(current.pipeline.makeCloudPauseContext(acceptedSnapshot: current.accepted))
            let presentation = current.viewModel.pausePresentationState
            let critique = try XCTUnwrap(current.pipeline.currentPauseCritique)
            let drained = expectation(description: "Earlier main-queue cleanup drained")
            DispatchQueue.main.async { drained.fulfill() }
            await fulfillment(of: [drained], timeout: 3)
            XCTAssertEqual(current.viewModel.pauseSceneControlFacts.lighting, .allowed)
            XCTAssertEqual(current.viewModel.pauseSceneControlFacts.objects, .unknown)
            XCTAssertEqual(current.pipeline.makeCloudPauseContext(acceptedSnapshot: current.accepted), context)
            XCTAssertEqual(current.pipeline.currentPauseCritique, critique)
            XCTAssertEqual(current.viewModel.pausePresentationState, presentation)
            XCTAssertEqual(current.client.analysisCount, 0)
            await previous.viewModel.releaseAndWait()
            await current.viewModel.releaseAndWait()
        }
    }

    func testSceneControlDoesNotTransferToReplacementAcceptedSnapshot() async throws {
        let first = try makeFixture(controlScene: true)
        let next = try makeFixture(controlScene: true)
        first.viewModel.answerPauseSceneControl(category: .objects, state: .allowed,
                                               expectedSnapshotID: first.accepted.snapshotID)
        first.viewModel.testingInstallCloudPausePresentation(
            acceptedSnapshot: next.accepted, critique: try XCTUnwrap(next.pipeline.currentPauseCritique))
        XCTAssertEqual(first.viewModel.pauseSceneControlFacts.objects, .unknown)
        first.viewModel.answerPauseSceneControl(category: .objects, state: .allowed,
                                               expectedSnapshotID: first.accepted.snapshotID)
        XCTAssertEqual(first.viewModel.pauseSceneControlFacts.objects, .unknown)
        await first.viewModel.releaseAndWait()
        await next.viewModel.releaseAndWait()
    }

    func testTechnicalPauseAlsoWithholdsUnownedLightWithoutChangingMeasurement() async throws {
        // Injected measured-signal fixture exercises the existing technical owner;
        // it does not claim these fixture pixels were measured as underexposed.
        let signal = TechnicalQualitySignal(issues: [
            .init(type: .underexposure, actionType: .increaseExposure, confidence: 0.9, severity: 0.9, isDominant: true)
        ])
        // A supported composition correction takes priority over underexposure
        // in technicalPauseIssue. Isolate the technical signal explicitly, keep
        // the mixed verdict, and retain a separate observed focus strength so
        // this exercises an available structured path without competing advice.
        let fixture = try makeFixture(technicalSignalOverride: signal, isolateTechnicalSignal: true)
        let vm = fixture.viewModel
        vm.answerPauseSceneControl(category: .lighting, state: .allowed,
                                   expectedSnapshotID: fixture.accepted.snapshotID)
        let allowed = try XCTUnwrap(vm.pauseCritique)
        XCTAssertEqual(allowed.summaryId, "technical_quality_underexposure")
        XCTAssertTrue(allowed.actions.contains { $0.semanticActionType == .addFrontFillLight })
        let allowedLightActions = allowed.actions.filter { $0.semanticActionType == .addFrontFillLight }
        XCTAssertEqual(allowedLightActions.count, 1)
        XCTAssertNotNil(allowedLightActions.first?.targetRegion)
        vm.resetPauseSceneControl(expectedSnapshotID: fixture.accepted.snapshotID)
        let unknown = try XCTUnwrap(vm.pauseCritique)
        XCTAssertEqual(unknown.summaryId, "technical_quality_underexposure")
        XCTAssertFalse(unknown.actions.contains { $0.semanticActionType == .addFrontFillLight })
        XCTAssertFalse(unknown.actions.contains { $0.semanticActionType == .rotateSubjectTowardLight })
        XCTAssertEqual(unknown.technicalQualityMeasurement, allowed.technicalQualityMeasurement)
        XCTAssertEqual(unknown.verdict, allowed.verdict)
        XCTAssertEqual(unknown.verdictConfidence, allowed.verdictConfidence)
        XCTAssertNil(vm.verificationResult)
        await vm.releaseAndWait()
    }

    func testUnderexposureWithSemanticCorrectionKeepsExistingPlannerPriority() async throws {
        let signal = TechnicalQualitySignal(issues: [
            .init(type: .underexposure, actionType: .increaseExposure, confidence: 0.9, severity: 0.9, isDominant: true)
        ])
        let fixture = try makeFixture(technicalSignalOverride: signal)
        fixture.viewModel.answerPauseSceneControl(category: .lighting, state: .allowed,
                                                  expectedSnapshotID: fixture.accepted.snapshotID)
        let presentation = try XCTUnwrap(fixture.viewModel.pauseCritique)
        XCTAssertEqual(presentation.summaryId, "summary-clutter")
        XCTAssertTrue(presentation.actions.contains {
            $0.semanticActionType == .changeCameraAngle || $0.semanticActionType == .simplifyBackground
        })
        XCTAssertFalse(presentation.actions.contains { $0.semanticActionType == .addFrontFillLight })
        XCTAssertEqual(presentation.technicalQualityMeasurement, .measured(signal))
        XCTAssertNil(fixture.viewModel.verificationResult)
        await fixture.viewModel.releaseAndWait()
    }

    func testSceneControlSheetCopyKeepsThreeCategoriesAndUnknownExplicitInBothLanguages() {
        XCTAssertEqual(PauseSceneControlFacts.Category.allCases.count, 3)
        XCTAssertEqual(PauseSceneControlFacts.State.allCases.count, 3)
        for locale in [Locale(identifier: "ru"), Locale(identifier: "en")] {
            let keys = PauseSceneControlFacts.Category.allCases.map(PauseSceneControlSheet.questionKey)
                + PauseSceneControlFacts.State.allCases.map(PauseSceneControlSheet.answerKey)
                + [.cameraSceneControlTitle, .cameraSceneControlScope, .cameraSceneControlReset, .cameraSceneControlDone]
            for key in keys {
                let text = key.localizedString(locale: locale)
                XCTAssertFalse(text.isEmpty)
                XCTAssertNotEqual(text, key.rawValue)
            }
            XCTAssertNotEqual(PauseSceneControlSheet.answerKey(for: .unknown).localizedString(locale: locale),
                              PauseSceneControlSheet.answerKey(for: .forbidden).localizedString(locale: locale))
        }
    }

    private func startAnalysis(_ fixture: Fixture) async throws {
        let expectedCount = fixture.client.analysisCount + 1
        fixture.viewModel.requestCloudPauseAnalysis(locale: "en")
        await assertEventually { fixture.viewModel.pendingCloudTransfer != nil }
        let request = try XCTUnwrap(fixture.viewModel.pendingCloudTransfer)
        fixture.viewModel.approveCloudPauseAnalysis(request.approval)
        await assertEventually { fixture.client.analysisCount == expectedCount }
    }

    private struct Fixture {
        let pipeline: AnalysisPipeline
        let viewModel: CameraViewModel
        let client: PauseFixtureCloudClient
        let accepted: LatestFrameEvidenceStore.AcceptedSnapshot
    }

    private func makeFixture(holdResponse: Bool = false, localAvailable: Bool = true,
                             overexposed: Bool = false, emptyResponse: Bool = false,
                             abstained: Bool = false, pendingTilt: Bool = false,
                             controlScene: Bool = false,
                             technicalSignalOverride: TechnicalQualitySignal? = nil,
                             isolateTechnicalSignal: Bool = false,
                             goodFrame: Bool = false,
                             reusingPipeline: AnalysisPipeline? = nil) throws -> Fixture {
        let frameID = "cloud-pause-fixture-" + UUID().uuidString.lowercased()
        let capturedAt = Date(timeIntervalSince1970: 1_789_500_000)
        let pixels = try makePixels(overexposed: overexposed)
        let store = LatestFrameEvidenceStore()
        XCTAssertTrue(store.publish(
            pixelBuffer: pixels, orientation: .up, sourceFrameId: frameID,
            capturedAt: capturedAt, isStable: true, lensID: "test-wide",
            lensGeneration: 3, samplePresentationTimestamp: CMTime(value: 1001, timescale: 600),
            sessionGeneration: 0
        ))
        let unrendered = try XCTUnwrap(store.acceptCurrentSnapshot())
        let accepted = try XCTUnwrap(store.renderDisplayImage(for: unrendered))
        let region = NormalizedRect(x: 0.25, y: 0.2, width: 0.25, height: 0.4)
        let snapshot = FrameFeatureSnapshot(
            frameId: frameID, mode: .pause, capturedAt: capturedAt,
            sources: .init(vision: .init(available: true, freshnessMs: 0, confidence: 0.8),
                           horizon: .init(available: false), lighting: .init(available: false),
                           detr: .init(available: false), aesthetic: .init(available: false)),
            composition: .init(horizontalOffset: 0, verticalOffset: 0, subjectAreaRatio: 0.1,
                               saliencyLeftRightBalance: 0, saliencyTopBottomBalance: 0),
            subjectSignals: .init(faceDetected: false, personDetected: false, personCount: 0,
                                  primaryCandidateRegion: region, primaryCandidateConfidence: 0.8),
            horizon: .init(angleDegrees: pendingTilt ? 3 : 0, confidence: pendingTilt ? 0.8 : 0),
            lighting: .init(exposureBiasHint: 0, backlightIndex: 0, keyToFillRatio: nil),
            motion: .init(state: .still, shakeLevel: 0), aesthetics: .init(),
            objects: .init(totalCount: 0, topKLabels: []), technicalFlags: []
        )
        let semantics = SceneSemanticsReport(
            frameId: frameID, mode: .pause, sceneType: .objectInsert, sceneTypeConfidence: 0.8,
            primarySubject: .init(kind: .object, label: "object", region: region, confidence: 0.8),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: pendingTilt || isolateTechnicalSignal ? 0.1 : 0.65,
                             backgroundClutterScore: pendingTilt || isolateTechnicalSignal ? 0.1 : 0.85),
            readability: .init(subjectReadable: true, lookSpaceAdequate: nil,
                               edgePressureScore: 0.1, separationScore: 0.5),
            ambiguities: [], assumptions: []
        )
        let critique = CritiqueReport(
            frameId: frameID, mode: .pause, verdict: goodFrame ? .good : .mixed,
            verdictConfidence: localAvailable ? 0.8 : 0.1,
            strengths: isolateTechnicalSignal || goodFrame ? [.init(
                id: "fixture-focus-strength", type: .clearFocusHierarchy, confidence: 0.8,
                rationale: "В этом синтетическом сценарии задан отчётливый главный объект.",
                evidence: [.init(source: .semantics, key: "dominance.hasClearFocus", value: "true", confidence: 0.8)],
                supportingRegion: region
            )] : [],
            issues: isolateTechnicalSignal || goodFrame ? [] : [.init(
                id: "issue-clutter", type: pendingTilt ? .horizonDistracts
                    : (controlScene ? .backgroundCompetesWithSubject : .frameVisuallyOverloaded),
                severity: 0.85, confidence: 0.8,
                rationale: pendingTilt ? "Заметен наклон горизонта." : "Фон перегружен.",
                evidence: [.init(source: .semantics,
                                 key: pendingTilt ? "horizon.angleDegrees" : "dominance.backgroundClutterScore",
                                 value: pendingTilt ? "3" : "0.85", confidence: 0.8)],
                affectedRegion: region, suggestedFixTypes: [.reframing]
            )],
            summary: .init(id: goodFrame ? "summary-good-fixture" : (isolateTechnicalSignal ? "summary-technical-fixture" : "summary-clutter"),
                           shortVerdict: goodFrame ? "Композиция читается." : "Кадр можно улучшить.",
                           whyGood: goodFrame ? "Явный сценарий с хорошим кадром." : nil,
                           whyProblematic: goodFrame ? nil : (isolateTechnicalSignal ? "Технический сигнал проверяется отдельно." : "Фон перегружен.")),
            traceRefs: [], fallbackUsed: false
        )
        let plan = RecommendationPlan(
            frameId: frameID, mode: .pause, inputVerdict: goodFrame ? .good : .mixed,
            primaryAction: isolateTechnicalSignal || goodFrame ? nil : .init(
                id: "action-clutter", actionType: pendingTilt ? .levelHorizon : .reduceBackgroundDistractions, priority: 1,
                targetRegion: region, linkedIssueIds: ["issue-clutter"],
                expectedOutcome: "Сделать главный объект заметнее.",
                guardrail: .init(requiresStillCamera: true, minConfidence: 0.4, suppressWhenMoving: true),
                overlayHint: nil
            ),
            secondaryActions: [], deferredActions: [], noChangeRationale: nil,
            planConfidence: localAvailable ? 0.8 : 0.1
        )
        let measurement = technicalSignalOverride.map(TechnicalQualityMeasurement.measured)
            ?? TechnicalQualityAnalyzer().measurement(pixelBuffer: accepted.pixelBuffer)
        let signal = try XCTUnwrap(measurement.signal)
        if !overexposed && technicalSignalOverride == nil { XCTAssertEqual(signal, .empty) }
        let pipeline = reusingPipeline ?? AnalysisPipeline(
            reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil
        )
        pipeline.testingInstallCloudPauseReview(
            acceptedSnapshot: accepted, snapshot: snapshot, semantics: semantics, critique: critique, plan: plan,
            technicalSignal: signal,
            technicalEvidence: FrameTechnicalQualityEvidence(frameID: frameID, capturedAt: capturedAt,
                                                            measurement: measurement)
        )
        let policy = try XCTUnwrap(CameraCloudTransferPolicy(
            serviceEndpoint: URL(string: "https://camera-fixture.example.test/v1")!,
            operatorName: "Test operator", providerName: "local-fixture", providerVersion: "fixture-v1",
            processingRegion: "Test", imageRetention: "Not retained", requestMetadataRetention: "Test only",
            securityIdentityRetention: "Test only", spendRecordRetention: "Test only",
            deletionRequestProcedure: "Local fixture", providerRetention: "Not retained",
            policyVersion: "fixture-v1", policyURL: URL(string: "https://camera-fixture.example.test/privacy")!
        ))
        pipeline.testingUpdateIntentClarification(snapshot: snapshot, semantics: semantics)
        let client = PauseFixtureCloudClient(policy: policy, holdResponse: holdResponse,
                                            emptyResponse: emptyResponse, abstained: abstained)
        let manager = CameraManager(
            scheduler: RealtimeScheduler(), thermalGovernor: ThermalGovernor(), motionGate: MotionGate(),
            sessionRunner: PauseFixtureSessionRunner(), configuration: .ready,
            notificationCenter: NotificationCenter()
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline,
                                        cameraCloudClient: client)
        viewModel.testingInstallCloudPausePresentation(
            acceptedSnapshot: accepted, critique: try XCTUnwrap(pipeline.currentPauseCritique)
        )
        return Fixture(pipeline: pipeline, viewModel: viewModel, client: client, accepted: accepted)
    }

    private func makePixels(overexposed: Bool) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 96, 96, kCVPixelFormatType_32BGRA,
                                          nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        XCTAssertEqual(CVPixelBufferLockBaseAddress(pixels, []), kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(pixels, []) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels))
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0..<96 {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<96 {
                let luma: UInt8 = overexposed ? 255 : (((x / 3 + y / 3) % 2 == 0) ? 70 : 190)
                row[x * 4] = luma; row[x * 4 + 1] = luma; row[x * 4 + 2] = luma; row[x * 4 + 3] = 255
            }
        }
        return pixels
    }

    private func assertEventually(file: StaticString = #filePath, line: UInt = #line,
                                  _ predicate: () -> Bool) async {
        let observed = await waitUntil(predicate)
        XCTAssertTrue(observed, "Expected state did not arrive", file: file, line: line)
    }

    private func waitUntil(_ predicate: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while ContinuousClock.now < deadline {
            if predicate() { return true }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        return predicate()
    }
}

private final class PauseFixtureSessionRunner: CameraSessionRunner {
    var isRunning = false
    func startRunning() { isRunning = true }
    func stopRunning() { isRunning = false }
}

private actor PauseFixtureNoToken: SceneServiceTokenProviding {
    func currentServiceToken() async -> String? { nil }
}

private final class PauseFixtureCloudClient: CameraCloudAnalyzing, @unchecked Sendable {
    let policy: CameraCloudTransferPolicy
    private let encoder: CameraCloudAnalysisClient
    private let lock = NSLock()
    private var shouldHold: Bool
    private let emptyResponse: Bool
    private let abstained: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private var submitted = 0
    private var finished = 0
    private var locale: String?
    var analysisCount: Int { locked { submitted } }
    var finishedCount: Int { locked { finished } }
    var lastLocale: String? { locked { locale } }

    init(policy: CameraCloudTransferPolicy, holdResponse: Bool, emptyResponse: Bool, abstained: Bool) {
        self.policy = policy
        self.shouldHold = holdResponse
        self.emptyResponse = emptyResponse
        self.abstained = abstained
        self.encoder = CameraCloudAnalysisClient(policy: policy, session: .shared,
                                                 tokenProvider: PauseFixtureNoToken())
    }

    func prepare(still: CameraCloudPreparedStill, context: CameraCloudPauseContext,
                 locale: String) throws -> CameraCloudPreparedAnalysis {
        try encoder.prepare(still: still, context: context, locale: locale)
    }

    func analyze(_ prepared: CameraCloudPreparedAnalysis,
                 approval: CameraCloudTransferApproval) async throws -> CameraCloudAnalyzedEvidence {
        guard approval == prepared.transfer.approval else { throw CameraCloudClientError.approvalRequired }
        locked { submitted += 1; locale = prepared.visualRequest.locale }
        await withCheckedContinuation { continuation in
            let held = locked {
                if shouldHold { self.continuation = continuation; return true }
                return false
            }
            if !held { continuation.resume() }
        }
        // Deliberately allow a late callback after cancellation. The VM must reject it.
        let requestJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: prepared.body) as? [String: Any])
        var responseJSON: [String: Any] = [
            "schema_version": CameraCloudEvidenceWire.version,
            "request_id": prepared.wireRequest.request_id,
            "request_sha256": prepared.transfer.requestHash,
            "correlation": try XCTUnwrap(requestJSON["correlation"]),
            "media_sha256": prepared.transfer.mediaSHA256,
            "policy_fingerprint": prepared.transfer.policyFingerprint,
            "evidence": [
                "observations": [[
                    "observation_id": "timing-fixture", "dimension": "clutter",
                    "polarity": "supports_problem", "score": 0.8, "confidence": 0.8,
                    "uncertainty_reasons": [], "entity_refs": ["ent-primary-subject"],
                    "visual_problem_type": "timing_blocker_in_frame",
                    "visual_strength_type": NSNull(), "supporting_issue_ids": ["issue-clutter"],
                    "supporting_strength_ids": [], "rationale": "Объект временно перекрывает фон."
                ]],
                "relations": [], "abstained": false, "abstention_reason": NSNull()
            ]
        ]
        if emptyResponse {
            responseJSON["evidence"] = [
                "observations": [], "relations": [], "abstained": abstained,
                "abstention_reason": abstained ? "Insufficient visual evidence" as Any : NSNull()
            ]
        }
        let decoded = try CameraCloudEvidenceWire.decode(
            JSONSerialization.data(withJSONObject: responseJSON),
            request: prepared.wireRequest, bodyHash: prepared.transfer.requestHash
        )
        let response = CameraCloudEvidenceWire.adapt(
            decoded, request: prepared.visualRequest, policy: policy, latencyMs: 0
        )
        locked { finished += 1 }
        return CameraCloudAnalyzedEvidence(request: prepared.visualRequest, response: response)
    }

    func releaseResponse() {
        let pending = locked {
            shouldHold = false
            let value = continuation
            continuation = nil
            return value
        }
        pending?.resume()
    }

    private func locked<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}
