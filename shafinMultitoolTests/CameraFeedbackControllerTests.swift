import XCTest
@testable import shafinMultitool

@MainActor
final class CameraFeedbackControllerTests: XCTestCase {

    private final class RecordingHaptic: SETHapticPerforming {
        private(set) var events: [SETHapticEvent] = []
        func perform(_ event: SETHapticEvent) { events.append(event) }
    }

    func testEachProductMomentMapsToItsOwnHapticStyle() {
        let haptic = RecordingHaptic()
        let controller = SETCameraFeedbackController(eventLedger: SETMotionEventLedger(),
                                                     haptic: haptic)
        controller.targetAcquired(eventID: "episode.1")
        controller.adviceChanged(eventID: "hint-a")
        controller.verifiedImproved(eventID: "frame-after")
        controller.failed(eventID: "analysis.7")

        XCTAssertEqual(haptic.events, [.selection, .soft, .rigid, .error],
                       "UI-005 moments: acquired target / advice change / verified improvement / error")
    }

    func testFeedbackIsOneShotPerEventID() {
        let haptic = RecordingHaptic()
        let controller = SETCameraFeedbackController(eventLedger: SETMotionEventLedger(),
                                                     haptic: haptic)
        controller.adviceChanged(eventID: "hint-a")
        controller.adviceChanged(eventID: "hint-a")
        controller.adviceChanged(eventID: "hint-a")
        XCTAssertEqual(haptic.events, [.soft], "recompositions must never replay a haptic")

        controller.adviceChanged(eventID: "hint-b")
        XCTAssertEqual(haptic.events, [.soft, .soft], "a genuinely new advice event still fires")
    }

    func testDifferentMomentsDoNotShareEventIdentity() {
        let haptic = RecordingHaptic()
        let controller = SETCameraFeedbackController(eventLedger: SETMotionEventLedger(),
                                                     haptic: haptic)
        controller.targetAcquired(eventID: "x")
        controller.verifiedImproved(eventID: "x")
        XCTAssertEqual(haptic.events, [.selection, .rigid],
                       "the same id in different moments is two distinct feedback events")
    }

    func testEmptyEventIDNeverFires() {
        let haptic = RecordingHaptic()
        let controller = SETCameraFeedbackController(eventLedger: SETMotionEventLedger(),
                                                     haptic: haptic)
        controller.failed(eventID: "")
        XCTAssertTrue(haptic.events.isEmpty, "anonymous feedback is fail-closed")
    }

    func testLedgerIsSharedWithTheMotionEventLedger() {
        let ledger = SETMotionEventLedger()
        let haptic = RecordingHaptic()
        let controller = SETCameraFeedbackController(eventLedger: ledger, haptic: haptic)
        controller.verifiedImproved(eventID: "frame-9")
        XCTAssertTrue(ledger.hasConsumed("feedback.verified.frame-9"))
    }
}
