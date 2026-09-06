import XCTest
@testable import shafinMultitool

/// M11-010: one-shot motion ownership — recomposition/rotation/resizing
/// cannot replay a consumed event; cancellation and owner release reset
/// explicitly through the owning ledger.
final class MotionEventOwnershipTests: XCTestCase {

    func testConsumeIsOneShotAcrossRepeatedCalls() {
        let ledger = SETMotionEventLedger()
        XCTAssertTrue(ledger.consume(eventID: "evt-1"))
        XCTAssertFalse(ledger.consume(eventID: "evt-1"), "recomposition must not replay")
        XCTAssertTrue(ledger.hasConsumed("evt-1"))
        XCTAssertEqual(ledger.consumedCount, 1)
    }

    func testEmptyEventIDNeverConsumes() {
        let ledger = SETMotionEventLedger()
        XCTAssertFalse(ledger.consume(eventID: ""))
        XCTAssertEqual(ledger.consumedCount, 0)
    }

    func testResetIsExplicitOwnerRelease() {
        let ledger = SETMotionEventLedger()
        XCTAssertTrue(ledger.consume(eventID: "evt-1"))
        ledger.reset()
        XCTAssertFalse(ledger.hasConsumed("evt-1"))
        XCTAssertTrue(ledger.consume(eventID: "evt-1"), "post-reset consumption is a new explicit owner")
    }

    func testConcurrentConsumeHasExactlyOneWinner() {
        let ledger = SETMotionEventLedger()
        var wins = 0
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: 32) { _ in
            if ledger.consume(eventID: "evt-race") {
                lock.lock(); wins += 1; lock.unlock()
            }
        }
        XCTAssertEqual(wins, 1)
    }
}
