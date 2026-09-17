#if DEBUG
import SwiftUI
import CoreMedia
import CoreVideo

/// Generated evidence seeds the existing accepted-pause owner once. All visible
/// controls and answers then use the production surface, ViewModel and planner.
/// This fixture does not establish perception accuracy or physical completion.
@MainActor
struct SETCameraSceneControlFixtureRoot: View {
    let configuration: SETCameraCoachFixtureConfiguration
    @StateObject private var fixture = CameraSceneControlUIFixture()

    var body: some View {
        Group {
            if let viewModel = fixture.viewModel, let manager = fixture.manager {
                CameraSceneControlUIFixtureSurface(viewModel: viewModel, manager: manager)
            } else {
                Text("Scene control fixture preparation failed")
                    .accessibilityIdentifier("camera_scene_control_fixture_error")
            }
        }
        .environment(\.locale, configuration.locale)
        .environment(\.dynamicTypeSize, configuration.dynamicTypeSize)
        .environment(\.setReduceMotionOverride, configuration.reduceMotion)
        .environment(\.setReduceTransparencyOverride, configuration.reduceTransparency)
        .preferredColorScheme(.dark)
    }
}

@MainActor
private struct CameraSceneControlUIFixtureSurface: View {
    @ObservedObject var viewModel: CameraViewModel
    let manager: CameraManager

    var body: some View {
        SETCameraCoachProductionView(viewModel: viewModel, cameraManager: manager)
            .background(alignment: .topLeading) {
                // The test reads actual owner state after dismissing the sheet;
                // this probe never writes a fact or a presentation result.
                Text(state)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("camera_scene_control_fixture_state")
                    .allowsHitTesting(false)
                Text(placementAssessmentState)
                    .font(.system(size: 1))
                    .frame(width: 1, height: 1)
                    .accessibilityIdentifier("camera_placement_fixture_assessment")
                    .allowsHitTesting(false)
                if ProcessInfo.processInfo.environment["SHAFIN_UI_TEST_PARTIAL_COVERAGE"] == "1" {
                    Text(technicalCoverageState)
                        .font(.system(size: 1))
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("camera_partial_coverage_fixture_state")
                        .allowsHitTesting(false)
                }
            }
            // A compact-height sheet can cover this surface completely. Its
            // disappearance is not a camera route exit; the fixture process
            // owns these no-network/no-capture dependencies until termination.
    }

    private var state: String {
        let facts = viewModel.pauseSceneControlFacts
        let associatedActions: [PauseActionRow]
        if case .success(_, let critique) = viewModel.pausePresentationState {
            associatedActions = critique.actions
        } else {
            associatedActions = []
        }
        return "objects=\(facts.objects.rawValue);participants=\(facts.participants.rawValue);lighting=\(facts.lighting.rawValue);physicalObjectAdvice=\(associatedActions.contains { $0.semanticActionType == .moveObjectBack });verification=\(viewModel.verificationResult == nil ? "none" : "present")"
    }

    private var placementAssessmentState: String {
        guard case .success(_, let critique) = viewModel.pausePresentationState else { return "unavailable" }
        return "verdict=\(critique.verdict.rawValue);issues=\(critique.issues.count);actions=\(critique.actions.count);verification=\(viewModel.verificationResult == nil ? "none" : "present")"
    }

    /// Reads the same accepted owner output rendered by the production review;
    /// this probe never substitutes uncertainty copy or a desired verdict.
    private var technicalCoverageState: String {
        guard case .success(_, let critique) = viewModel.pausePresentationState,
              case let .partial(signal, reason, _) = critique.technicalQualityMeasurement else {
            return "partial-owner-output-unavailable"
        }
        let review = CameraReviewPresentation.make(critique: critique, locale: Locale(identifier: "en"))
        let limited = review.uncertainties.contains { $0.reason == .limitedToAvailableSignals }
        return "coverage=partial;reason=\(reason.rawValue);signalIssues=\(signal.issues.count);verdict=\(critique.verdict.rawValue);actions=\(critique.actions.count);limitedCoverage=\(limited);fallback=\(critique.fallbackUsed);verification=\(viewModel.verificationResult == nil ? "none" : "present")"
    }
}

@MainActor
private final class CameraSceneControlUIFixture: ObservableObject {
    let viewModel: CameraViewModel?
    let manager: CameraManager?

    init() {
        do {
            let result = try Self.make()
            viewModel = result.0
            manager = result.1
        } catch {
            viewModel = nil
            manager = nil
        }
    }

    private enum PreparationError: Error { case invalidGeneratedEvidence }

    private static func make() throws -> (CameraViewModel, CameraManager) {
        // Explicit test-only no-action input, not a perception result. The
        // default fixture continues to exercise scene-control advice priority.
        let placementFixture = ProcessInfo.processInfo.environment["SHAFIN_UI_TEST_IMAGE_PLACEMENT_ACTIVE"] == "1"
        let partialCoverageFixture = ProcessInfo.processInfo.environment["SHAFIN_UI_TEST_PARTIAL_COVERAGE"] == "1"
        guard !(placementFixture && partialCoverageFixture) else {
            throw PreparationError.invalidGeneratedEvidence
        }
        let noActionInput = placementFixture || partialCoverageFixture
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, 96, 96, kCVPixelFormatType_32BGRA,
                                  nil, &buffer) == kCVReturnSuccess,
              let pixels = buffer,
              CVPixelBufferLockBaseAddress(pixels, []) == kCVReturnSuccess else {
            throw PreparationError.invalidGeneratedEvidence
        }
        guard let base = CVPixelBufferGetBaseAddress(pixels) else {
            CVPixelBufferUnlockBaseAddress(pixels, [])
            throw PreparationError.invalidGeneratedEvidence
        }
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        for y in 0..<96 {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<96 {
                // Flat mid-gray provides actual ambiguous detail with no
                // exposure defect. It cannot establish optical defocus.
                let luma: UInt8 = partialCoverageFixture ? 128 : ((x / 3 + y / 3) % 2 == 0 ? 70 : 190)
                row[x * 4] = luma
                row[x * 4 + 1] = luma
                row[x * 4 + 2] = luma
                row[x * 4 + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let frameID = "generated-scene-control-ui-frame"
        let capturedAt = Date(timeIntervalSince1970: 1_789_500_000)
        let store = LatestFrameEvidenceStore()
        guard store.publish(pixelBuffer: pixels, orientation: .up, sourceFrameId: frameID,
                            capturedAt: capturedAt, isStable: true, lensID: "fixture-wide",
                            lensGeneration: 1, samplePresentationTimestamp: CMTime(value: 1001, timescale: 600),
                            sessionGeneration: 0),
              let unrendered = store.acceptCurrentSnapshot(),
              let accepted = store.renderDisplayImage(for: unrendered) else {
            throw PreparationError.invalidGeneratedEvidence
        }
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
            horizon: .init(angleDegrees: 0, confidence: 0),
            lighting: .init(exposureBiasHint: 0, backlightIndex: 0, keyToFillRatio: nil),
            motion: .init(state: .still, shakeLevel: 0), aesthetics: .init(),
            objects: .init(totalCount: 0, topKLabels: []), technicalFlags: []
        )
        let semantics = SceneSemanticsReport(
            frameId: frameID, mode: .pause, sceneType: .objectInsert, sceneTypeConfidence: 0.8,
            primarySubject: .init(kind: .object, label: "object", region: region, confidence: 0.8),
            dominance: .init(hasClearFocus: true, focusCompetitionScore: noActionInput ? 0.05 : 0.65,
                             backgroundClutterScore: noActionInput ? 0.05 : 0.85),
            readability: .init(subjectReadable: true, lookSpaceAdequate: nil, edgePressureScore: 0.1, separationScore: 0.5),
            ambiguities: [], assumptions: [.init(
                id: "generated-ui-fixture-provenance",
                text: "Generated UI fixture; semantic values are injected, not inferred from pixels.",
                confidence: 1
            )]
        )
        let localCritique = CritiqueReport(
            frameId: frameID, mode: .pause, verdict: .mixed, verdictConfidence: 0.8, strengths: [],
            issues: [.init(id: "fixture-clutter", type: .backgroundCompetesWithSubject,
                           severity: 0.85, confidence: 0.8, rationale: "Фон отвлекает внимание от предмета.",
                           evidence: [.init(source: .semantics, key: "dominance.backgroundClutterScore", value: "0.85", confidence: 0.8)],
                           affectedRegion: region, suggestedFixTypes: [.reframing])],
            summary: .init(id: "fixture-summary", shortVerdict: "Кадр можно улучшить.",
                           whyGood: nil, whyProblematic: "Фон отвлекает внимание от предмета."),
            traceRefs: ["generated-ui-fixture-trace"], fallbackUsed: false
        )
        let localPlan = RecommendationPlan(
            frameId: frameID, mode: .pause, inputVerdict: .mixed,
            primaryAction: .init(id: "fixture-reframe", actionType: .reduceBackgroundDistractions, priority: 1,
                                 targetRegion: region, linkedIssueIds: ["fixture-clutter"],
                                 expectedOutcome: "Сделать главный объект заметнее.",
                                 guardrail: .init(requiresStillCamera: true, minConfidence: 0.4, suppressWhenMoving: true),
                                 overlayHint: nil),
            secondaryActions: [], deferredActions: [], noChangeRationale: nil, planConfidence: 0.8
        )
        let critique = noActionInput ? CritiqueReport(
            frameId: frameID, mode: .pause, verdict: .good, verdictConfidence: 0.8,
            strengths: [], issues: [],
            summary: .init(id: "generated-placement-good", shortVerdict: "Generated no-action UI input",
                           whyGood: nil, whyProblematic: nil),
            traceRefs: ["generated-ui-fixture-trace"], fallbackUsed: false
        ) : localCritique
        let plan = noActionInput ? RecommendationPlan(
            frameId: frameID, mode: .pause, inputVerdict: .good, primaryAction: nil,
            secondaryActions: [], deferredActions: [], noChangeRationale: "Generated no-action UI input",
            planConfidence: 0.8
        ) : localPlan
        let measurement = TechnicalQualityAnalyzer().measurement(pixelBuffer: accepted.pixelBuffer)
        guard let signal = measurement.signal else { throw PreparationError.invalidGeneratedEvidence }
        if partialCoverageFixture {
            guard case let .partial(observedSignal, reason, detail) = measurement,
                  reason == .sharpnessCauseUnobservable, observedSignal.issues.isEmpty,
                  detail.sampleWidth == 96, detail.sampleHeight == 96,
                  detail.gradientMean == 0, detail.gradientVariance == 0 else {
                throw PreparationError.invalidGeneratedEvidence
            }
        }
        let pipeline = AnalysisPipeline(reasoningProvider: nil, visualEvidenceProvider: nil, neuralEvidenceService: nil)
        pipeline.testingInstallCloudPauseReview(
            acceptedSnapshot: accepted, snapshot: snapshot, semantics: semantics, critique: critique, plan: plan,
            technicalSignal: signal,
            technicalEvidence: FrameTechnicalQualityEvidence(frameID: frameID, capturedAt: capturedAt, measurement: measurement)
        )
        guard let presentation = pipeline.currentPauseCritique else { throw PreparationError.invalidGeneratedEvidence }
        if placementFixture {
            guard presentation.verdict == .good,
                  presentation.actions.allSatisfy({ $0.semanticActionType == .keepCurrentSetup }) else {
                throw PreparationError.invalidGeneratedEvidence
            }
        }
        let manager = CameraManager(
            scheduler: RealtimeScheduler(), thermalGovernor: ThermalGovernor(), motionGate: MotionGate(),
            sessionRunner: CameraSceneControlUISessionRunner(), configuration: .ready, notificationCenter: NotificationCenter()
        )
        let viewModel = CameraViewModel(cameraManager: manager, analysisPipeline: pipeline, cameraCloudClient: nil)
        viewModel.testingInstallCloudPausePresentation(acceptedSnapshot: accepted, critique: presentation)
        return (viewModel, manager)
    }
}

private final class CameraSceneControlUISessionRunner: CameraSessionRunner {
    var isRunning = false
    func startRunning() { isRunning = true }
    func stopRunning() { isRunning = false }
}
#endif
