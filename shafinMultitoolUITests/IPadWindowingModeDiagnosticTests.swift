import XCTest
import UIKit

extension XCTestCase {
    /// A reversible Simulator setting for explicit landscape layout checks.
    /// Windowed-mode denial remains a separate recorded result; this does not
    /// restrict the application's supported modes or touch physical devices.
    func prepareSimulatorIPadFullScreenLayout() throws {
#if targetEnvironment(simulator)
        guard UIDevice.current.userInterfaceIdiom == .pad else { return }
        guard #available(iOS 26.0, *) else { return }
        let settings = try IPadWindowingSettings.open()
        defer { settings.terminate() }
        let selected = IPadWindowingSettings.modeIDs.filter { settings.buttons[$0].isSelected }
        guard selected.count == 1 else {
            IPadWindowingSettings.attach(settings, to: self, name: "windowing-original-mode-ambiguous")
            throw NSError(domain: "SETOSWindowingFixture", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Exactly one original windowing mode must be observed"])
        }
        let originalID = selected[0]
        IPadWindowingSettings.attach(settings, to: self, name: "windowing-original-mode")
        addTeardownBlock { [weak self] in
            let restoredSettings = try IPadWindowingSettings.open()
            defer { restoredSettings.terminate() }
            if let self { IPadWindowingSettings.attach(restoredSettings, to: self, name: "windowing-before-original-mode-restore") }
            let original = restoredSettings.buttons[originalID]
            if !original.isSelected { original.tap() }
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: original)
            let result = XCTWaiter.wait(for: [restored], timeout: 5)
            if let self { IPadWindowingSettings.attach(restoredSettings, to: self, name: "windowing-original-mode-restored") }
            XCTAssertEqual(result, .completed, "The test must restore the observed Simulator windowing mode")
        }
        let fullscreen = settings.buttons[IPadWindowingSettings.fullScreenID]
        if !fullscreen.isSelected { fullscreen.tap() }
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: fullscreen)
        let result = XCTWaiter.wait(for: [ready], timeout: 5)
        IPadWindowingSettings.attach(settings, to: self, name: "windowing-full-screen-layout-mode")
        XCTAssertEqual(result, .completed, "Full Screen Apps must be observed before the landscape check")
        // Selection in the current Settings view alone is not proof that the
        // preference survived its process. Observe a new Settings launch before
        // starting the AUT; keep this distinct from the AUT's scene geometry.
        settings.terminate()
        let reopenedSettings = try IPadWindowingSettings.open()
        defer { reopenedSettings.terminate() }
        IPadWindowingSettings.attach(reopenedSettings, to: self, name: "windowing-full-screen-mode-after-settings-relaunch")
        let persistedIDs = IPadWindowingSettings.modeIDs.filter { reopenedSettings.buttons[$0].isSelected }
        XCTAssertEqual(persistedIDs, [IPadWindowingSettings.fullScreenID],
                       "Full Screen Apps selection must survive Settings relaunch before AUT launch")
#endif
    }
}

private enum IPadWindowingSettings {
    static let fullScreenID = "com.apple.settings.multitaskingAndGestures.fullScreenApps"
    static let modeIDs = [fullScreenID,
                          "com.apple.settings.multitaskingAndGestures.windowedApps",
                          "com.apple.settings.multitaskingAndGestures.stageManager"]

    static func open() throws -> XCUIApplication {
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        if !settings.buttons[fullScreenID].waitForExistence(timeout: 3) {
            let entry = settings.buttons["com.apple.settings.multitaskingAndGestures"]
            guard entry.waitForExistence(timeout: 5), entry.isHittable else {
                settings.terminate()
                throw NSError(domain: "SETOSWindowingFixture", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "The observed Multitasking settings entry is unavailable"])
            }
            entry.tap()
        }
        guard settings.buttons[fullScreenID].waitForExistence(timeout: 5) else {
            settings.terminate()
            throw NSError(domain: "SETOSWindowingFixture", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "The observed windowing controls are unavailable"])
        }
        return settings
    }

    static func attach(_ settings: XCUIApplication, to test: XCTestCase, name: String) {
        let process = ProcessInfo.processInfo
        let runnerIdentity = [
            "runnerBundle=\(Bundle.main.bundleIdentifier ?? "unreported")",
            "runnerPID=\(process.processIdentifier)",
            "runnerSimulatorUDID=\(process.environment["SIMULATOR_UDID"] ?? "unreported")",
            "runnerSimulatorDevice=\(process.environment["SIMULATOR_DEVICE_NAME"] ?? "unreported")",
            "configuredSettingsBundle=com.apple.Preferences",
            "observation=selected_settings_preference_not_AUT_scene_mode"
        ].joined(separator: "\n")
        let text = runnerIdentity + "\n" + modeIDs.map { id in "\(id): exists=\(settings.buttons[id].exists), selected=\(settings.buttons[id].isSelected)" }.joined(separator: "\n")
        let state = XCTAttachment(string: text)
        state.name = name + "-state"
        state.lifetime = .keepAlways
        test.add(state)
        let screenshot = XCTAttachment(screenshot: settings.screenshot())
        screenshot.name = name + "-screen"
        screenshot.lifetime = .keepAlways
        test.add(screenshot)
    }
}

/// Reads the dedicated Simulator's windowing controls without changing a mode.
final class IPadWindowingModeDiagnosticTests: XCTestCase {
    func testInspectIPadMultitaskingControls() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            XCTFail("This diagnostic requires the selected iPad Simulator")
            return
        }
        continueAfterFailure = false
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        settings.launch()
        defer { settings.terminate() }
        let labels = ["Multitasking & Gestures", "Multitasking and Gestures", "Многозадачность и жесты"]
        let predicate = NSPredicate(format: "label IN %@", labels)
        let entry = settings.descendants(matching: .any).matching(predicate).firstMatch
        for _ in 0..<6 {
            if entry.exists && entry.isHittable { break }
            settings.swipeUp()
        }
        guard entry.exists && entry.isHittable else {
            attach(settings, name: "ipad-settings-multitasking-entry-unavailable")
            XCTFail("Could not locate the exact Multitasking & Gestures entry")
            return
        }
        entry.tap()
        let modes = settings.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@ OR label CONTAINS[c] %@", "Windowed", "Full Screen", "Stage Manager"))
        _ = modes.firstMatch.waitForExistence(timeout: 5)
        attach(settings, name: "ipad-multitasking-controls-read-only")
        XCTAssertGreaterThan(modes.count, 0, "The windowing controls must be observed before any mode change")
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = name + "-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name + "-screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
