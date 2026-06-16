//
//  DeviceBenchmarkUITests.swift
//  shafinMultitoolTests
//
//  Created by Codex on 15.06.2026.
//

import XCTest
@testable import shafinMultitool

final class DeviceBenchmarkUITests: XCTestCase {
    func testBenchmarkModeLaunchesAndCompletesQuickRun() throws {
        throw XCTSkip(
            "Requires a dedicated UI test target. The current benchmark harness runs via the app-hosted XCTest bundle, so XCUIApplication-based live automation would be misleading here."
        )
    }
}
