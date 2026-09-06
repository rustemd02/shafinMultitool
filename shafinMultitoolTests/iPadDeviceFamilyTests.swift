import SwiftUI
import UIKit
import XCTest
@testable import shafinMultitool

/// M10-003: device family and route-aware orientations. Routes declare
/// their own masks and the shell delegates to the active route instead of
/// forcing one mask; the universal binary itself is pinned by
/// iPadPlatformContractTests.
@MainActor
final class iPadDeviceFamilyTests: XCTestCase {

    func testCameraRouteSupportsAllOrientations() {
        let controller = CommercialCameraCoachHostingController(rootView: EmptyView())
        XCTAssertEqual(controller.supportedInterfaceOrientations, .all)
    }

    func testSceneRouteIsLandscapeOnly() {
        let controller = CommercialSceneNavigationController()
        XCTAssertEqual(controller.supportedInterfaceOrientations, .landscape)
    }

    func testShellDelegatesMaskToActiveRoute() {
        // The shell has no mask of its own: it forwards to the active child
        // or falls back to .all before the first route is installed.
        let shell = CommercialShellViewController(routeFactory: { _ in
            CommercialHistoryRoute(viewController: UIViewController())
        })
        shell.loadViewIfNeeded()
        XCTAssertEqual(shell.supportedInterfaceOrientations, .all)
    }
}
