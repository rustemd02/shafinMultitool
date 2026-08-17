import UIKit
import XCTest
@testable import shafinMultitool

@MainActor
final class CommercialShellModeControlTests: XCTestCase {
    func testCameraRendersOneCompactScenesControl() throws {
        let (_, control) = makeHost(width: 390, height: 844)
        let button = try controlButton(in: control)

        XCTAssertEqual(control.renderedSection, .camera)
        XCTAssertEqual(button.accessibilityIdentifier, "commercial-shell-open-scenes")
        XCTAssertEqual(button.accessibilityLabel, "Сцены")
        XCTAssertTrue(
            button.image(for: .normal)?.isEqual(
                UIImage(systemName: "square.stack.3d.up", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
            ) == true
        )
        XCTAssertNil(button.title(for: .normal))
        XCTAssertEqual(allButtons(in: control).count, 1)
    }

    func testCameraTapEmitsOpenScenesIntentWithoutChangingRenderedRoute() throws {
        let (_, control) = makeHost(width: 390, height: 844)
        var intents: [CommercialShellModeControl.Intent] = []
        control.onIntentRequested = { intents.append($0) }

        try controlButton(in: control).sendActions(for: .touchUpInside)

        XCTAssertEqual(intents, [.openScenes])
        XCTAssertEqual(control.renderedSection, .camera)
        XCTAssertEqual(try controlButton(in: control).accessibilityIdentifier, "commercial-shell-open-scenes")
    }

    func testScenesRendersCameraReturnControlAndEmitsReturnIntent() throws {
        let (_, control) = makeHost(width: 844, height: 390)
        control.render(selectedSection: .scenes, isInteractionLocked: false)
        var intents: [CommercialShellModeControl.Intent] = []
        control.onIntentRequested = { intents.append($0) }

        let button = try controlButton(in: control)
        button.sendActions(for: .touchUpInside)

        XCTAssertEqual(control.renderedSection, .scenes)
        XCTAssertEqual(button.accessibilityIdentifier, "commercial-shell-return-camera")
        XCTAssertEqual(button.accessibilityLabel, "Камера")
        XCTAssertTrue(
            button.image(for: .normal)?.isEqual(
                UIImage(systemName: "camera.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .semibold))
            ) == true
        )
        XCTAssertEqual(intents, [.returnCamera])
    }

    func testHistoryUsesCameraReturnControlWithoutPersistentHistoryAffordance() throws {
        let (_, control) = makeHost(width: 390, height: 844)
        control.render(selectedSection: .history, isInteractionLocked: false)

        let button = try controlButton(in: control)

        XCTAssertEqual(control.renderedSection, .history)
        XCTAssertEqual(button.accessibilityIdentifier, "commercial-shell-return-camera")
        XCTAssertEqual(allButtons(in: control).count, 1)
    }

    func testLockedRenderDisablesIntentAndUnlockedRenderRestoresInteraction() throws {
        let (_, control) = makeHost(width: 390, height: 844)
        var intents: [CommercialShellModeControl.Intent] = []
        control.onIntentRequested = { intents.append($0) }

        control.render(selectedSection: .camera, isInteractionLocked: true)
        let button = try controlButton(in: control)
        button.sendActions(for: .touchUpInside)

        XCTAssertFalse(button.isUserInteractionEnabled)
        XCTAssertTrue(button.accessibilityTraits.contains(.notEnabled))
        XCTAssertEqual(intents, [])

        control.render(selectedSection: .camera, isInteractionLocked: false)
        XCTAssertTrue(button.isUserInteractionEnabled)
        XCTAssertFalse(button.accessibilityTraits.contains(.notEnabled))
        button.sendActions(for: .touchUpInside)
        XCTAssertEqual(intents, [.openScenes])
    }

    func testControlAndButtonRetainAtLeast44PointTargetInPortraitAndLandscape() throws {
        for (width, height) in [(CGFloat(390), CGFloat(844)), (CGFloat(844), CGFloat(390))] {
            let (_, control) = makeHost(width: width, height: height)
            let button = try controlButton(in: control)

            XCTAssertGreaterThanOrEqual(control.bounds.width, 44)
            XCTAssertGreaterThanOrEqual(control.bounds.height, 44)
            XCTAssertGreaterThanOrEqual(button.bounds.width, 44)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
        }
    }

    func testControlHasNoRailCardMenuOrForbiddenVisualLayers() throws {
        let (_, control) = makeHost(width: 390, height: 844)
        let descendants = allViews(in: control)

        XCTAssertFalse(descendants.contains { $0 is UITabBar })
        XCTAssertFalse(descendants.contains { $0 is UIVisualEffectView })
        XCTAssertFalse(descendants.contains { view in
            view.layer.sublayers?.contains { $0 is CAGradientLayer } == true
        })
        XCTAssertEqual(control.layer.cornerRadius, 0)
        XCTAssertEqual(control.layer.shadowOpacity, 0)
        XCTAssertEqual(control.subviews.count, 1)
        XCTAssertTrue(control.subviews.first is UIButton)
        XCTAssertEqual(control.backgroundColor, .clear)
        XCTAssertTrue(allButtons(in: control).allSatisfy { $0.backgroundColor == .clear })
    }

    private func makeHost(width: CGFloat, height: CGFloat) -> (UIViewController, CommercialShellModeControl) {
        let host = UIViewController()
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let control = CommercialShellModeControl()
        host.view.addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: host.view.centerXAnchor),
            control.centerYAnchor.constraint(equalTo: host.view.centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: 44),
            control.heightAnchor.constraint(equalToConstant: 44)
        ])
        host.view.layoutIfNeeded()
        return (host, control)
    }

    private func controlButton(
        in control: CommercialShellModeControl,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UIButton {
        guard let button = allButtons(in: control).first else {
            XCTFail("Missing compact mode control button", file: file, line: line)
            throw XCTSkip("Missing compact mode control button")
        }
        return button
    }

    private func allButtons(in control: CommercialShellModeControl) -> [UIButton] {
        allViews(in: control).compactMap { $0 as? UIButton }
    }

    private func allViews(in root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap(allViews)
    }
}
