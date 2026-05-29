import XCTest
@testable import shafinMultitool

final class CameraOverlayUXPresentationTests: XCTestCase {
    func testLiveWithoutHintShowsNonBlockingWaitingStatus() {
        let state = CameraOverlayUXPresentation.make(
            isPaused: false,
            liveHint: nil,
            pauseCritique: nil,
            previewSuggestions: []
        )

        XCTAssertTrue(state.showsLiveWaitingHint)
        XCTAssertEqual(state.liveWaitingTitle, "Анализ кадра активен")
        XCTAssertFalse(state.canShowDecisionTrace)
        XCTAssertFalse(state.showsPausePanel)
    }

    func testPauseWithoutResultsShowsAnalyzingPanelWithContinueAction() {
        let state = CameraOverlayUXPresentation.make(
            isPaused: true,
            liveHint: nil,
            pauseCritique: nil,
            previewSuggestions: []
        )

        XCTAssertFalse(state.showsLiveWaitingHint)
        XCTAssertTrue(state.showsPausePanel)
        XCTAssertEqual(state.pausePanelTitle, "Анализирую кадр")
        XCTAssertEqual(state.pausePrimaryActionTitle, "Продолжить")
        XCTAssertFalse(state.canShowDecisionTrace)
    }

    func testPauseCritiqueReadyEnablesDecisionTraceAndContinueAction() {
        let state = CameraOverlayUXPresentation.make(
            isPaused: true,
            liveHint: nil,
            pauseCritique: PauseCritiquePresentation(
                frameId: "frame_pause",
                verdict: .mixed,
                verdictConfidence: 0.72,
                summaryId: "summary_pause",
                shortVerdict: "Кадр можно улучшить.",
                whyGood: nil,
                whyProblematic: "Фон спорит с субъектом.",
                strengths: [],
                issues: [],
                actions: [],
                noChangeRationale: nil,
                assumptions: [],
                traceRootIds: ["trace_pause"],
                fallbackUsed: false
            ),
            previewSuggestions: []
        )

        XCTAssertTrue(state.showsPausePanel)
        XCTAssertEqual(state.pausePanelTitle, "Разбор кадра")
        XCTAssertEqual(state.pausePrimaryActionTitle, "Продолжить")
        XCTAssertTrue(state.canShowDecisionTrace)
    }

    func testPauseFallbackSuggestionsStillHaveExitPath() {
        let state = CameraOverlayUXPresentation.make(
            isPaused: true,
            liveHint: nil,
            pauseCritique: nil,
            previewSuggestions: [
                Suggestion(
                    text: "Выпрями горизонт.",
                    priority: .critical,
                    type: .horizon,
                    ttl: 4.5,
                    createdAt: Date(timeIntervalSince1970: 1)
                )
            ]
        )

        XCTAssertTrue(state.showsPausePanel)
        XCTAssertEqual(state.pausePanelTitle, "Быстрые подсказки")
        XCTAssertEqual(state.pausePrimaryActionTitle, "Продолжить")
        XCTAssertFalse(state.canShowDecisionTrace)
    }
}
