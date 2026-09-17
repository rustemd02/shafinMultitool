import UIKit
import XCTest
@testable import shafinMultitool

@MainActor
final class UIKitSceneBackgroundTaskCoordinatorTests: XCTestCase {
    private final class Platform: SceneBackgroundTaskPlatform {
        var handlers: [UIBackgroundTaskIdentifier: () -> Void] = [:]
        var ended: [UIBackgroundTaskIdentifier] = []
        var nextRawValue = 101
        var expireDuringBegin = false
        var rejectBegin = false

        func begin(withName name: String, expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
            guard !rejectBegin else { return .invalid }
            let id = UIBackgroundTaskIdentifier(rawValue: nextRawValue)
            nextRawValue += 1
            handlers[id] = expirationHandler
            if expireDuringBegin { expirationHandler() }
            return id
        }

        func end(_ identifier: UIBackgroundTaskIdentifier) { ended.append(identifier) }
    }

    func testProductionCoordinatorEndsOverlappingLeasesInEitherCompletionOrder() {
        for newestFirst in [false, true] {
            let platform = Platform()
            let owner = UIKitSceneBackgroundTaskCoordinator(platform: platform)
            let first = owner.begin(withName: "first")
            let second = owner.begin(withName: "second")
            let order = newestFirst ? [second, first] : [first, second]
            order.forEach(owner.end)
            order.forEach(owner.end)
            XCTAssertEqual(platform.ended, order)
        }
    }

    func testExpirationEndsOnlyItsOwnLeaseAndLateCompletionCannotEndReplacement() {
        let platform = Platform()
        let owner = UIKitSceneBackgroundTaskCoordinator(platform: platform)
        let first = owner.begin(withName: "first")
        let second = owner.begin(withName: "second")
        platform.handlers[first]?()
        XCTAssertEqual(platform.ended, [first])
        owner.end(first)
        platform.handlers[first]?()
        XCTAssertEqual(platform.ended, [first])
        owner.end(second)
        platform.handlers[second]?()
        XCTAssertEqual(platform.ended, [first, second])
    }

    func testExpirationBeforeBeginReturnsStillEndsReturnedLeaseExactlyOnce() {
        let platform = Platform()
        platform.expireDuringBegin = true
        let owner = UIKitSceneBackgroundTaskCoordinator(platform: platform)
        let id = owner.begin(withName: "immediate")
        XCTAssertEqual(platform.ended, [id])
        owner.end(id)
        platform.handlers[id]?()
        XCTAssertEqual(platform.ended, [id])
    }

    func testInvalidLeaseDoesNotReachPlatformEnd() {
        let platform = Platform()
        platform.rejectBegin = true
        let owner = UIKitSceneBackgroundTaskCoordinator(platform: platform)
        let id = owner.begin(withName: "rejected")
        XCTAssertEqual(id, .invalid)
        owner.end(id)
        XCTAssertTrue(platform.ended.isEmpty)
    }
}
