import UIKit
import XCTest
@testable import shafinMultitool

@MainActor
final class CommercialShellSectionSwitcherTests: XCTestCase {
    func testDefaultRenderExposesThreeControlsInContractOrder() {
        let (_, switcher) = makeHost(width: 390, height: 844)
        let buttons = controlButtons(in: switcher)

        XCTAssertEqual(buttons.map(\.accessibilityIdentifier), [
            "commercial-shell-section-camera",
            "commercial-shell-section-scenes",
            "commercial-shell-section-history"
        ])
        XCTAssertEqual(buttons.map { $0.title(for: .normal) }, ["Камера", "Сцены", "История"])

        let expectedSymbols = ["camera.fill", "square.stack.3d.up", "clock"]
        for (button, symbolName) in zip(buttons, expectedSymbols) {
            XCTAssertTrue(
                button.image(for: .normal)?.isEqual(UIImage(systemName: symbolName)) == true,
                "Expected SF Symbol \(symbolName)"
            )
            XCTAssertEqual(button.accessibilityLabel, button.title(for: .normal))
        }
    }

    func testCameraRenderReportsCameraSelectedAndOthersNotSelected() {
        let (_, switcher) = makeHost(width: 390, height: 844)
        switcher.render(selectedSection: .camera, isInteractionLocked: false)

        XCTAssertEqual(switcher.selectedSection, .camera)
        XCTAssertTrue(button(in: switcher, identifier: "commercial-shell-section-camera").accessibilityTraits.contains(.selected))
        XCTAssertEqual(button(in: switcher, identifier: "commercial-shell-section-camera").accessibilityValue, "Выбрано")
        XCTAssertFalse(button(in: switcher, identifier: "commercial-shell-section-scenes").accessibilityTraits.contains(.selected))
        XCTAssertFalse(button(in: switcher, identifier: "commercial-shell-section-history").accessibilityTraits.contains(.selected))
        XCTAssertEqual(button(in: switcher, identifier: "commercial-shell-section-scenes").accessibilityValue, "Не выбрано")
    }

    func testRenderingScenesChangesOnlyDisplayStateAndSendsNoCallback() {
        let (_, switcher) = makeHost(width: 390, height: 844)
        var callbackCount = 0
        switcher.onSelectionRequested = { _ in callbackCount += 1 }

        switcher.render(selectedSection: .scenes, isInteractionLocked: false)

        XCTAssertEqual(switcher.selectedSection, .scenes)
        XCTAssertEqual(callbackCount, 0)
        XCTAssertTrue(button(in: switcher, identifier: "commercial-shell-section-scenes").accessibilityTraits.contains(.selected))
    }

    func testScenesControlTapEmitsExactlyOnceWithoutOptimisticSelection() {
        let (_, switcher) = makeHost(width: 390, height: 844)
        var requestedSections: [CommercialSection] = []
        switcher.onSelectionRequested = { requestedSections.append($0) }

        button(in: switcher, identifier: "commercial-shell-section-scenes")
            .sendActions(for: .touchUpInside)

        XCTAssertEqual(requestedSections, [.scenes])
        XCTAssertEqual(switcher.selectedSection, .camera)
        XCTAssertTrue(button(in: switcher, identifier: "commercial-shell-section-camera").accessibilityTraits.contains(.selected))
    }

    func testLockedRenderDisablesControlsAndUnlockedRenderRestoresInteraction() {
        let (_, switcher) = makeHost(width: 390, height: 844)
        switcher.render(selectedSection: .camera, isInteractionLocked: true)

        XCTAssertEqual(switcher.selectedSection, .camera)
        XCTAssertTrue(controlButtons(in: switcher).allSatisfy { !$0.isUserInteractionEnabled })
        XCTAssertTrue(button(in: switcher, identifier: "commercial-shell-section-camera").accessibilityTraits.contains(.selected))

        switcher.render(selectedSection: .camera, isInteractionLocked: false)

        XCTAssertTrue(controlButtons(in: switcher).allSatisfy { $0.isUserInteractionEnabled })
        XCTAssertTrue(button(in: switcher, identifier: "commercial-shell-section-camera").accessibilityTraits.contains(.selected))
    }

    func testEveryControlHasAtLeast44PointHitTargetInPortraitAndCompactLandscape() {
        assertControlSizes(width: 390, height: 844)
        assertControlSizes(width: 844, height: 390)
    }

    func testRailHasNoSystemTabBarBlurGradientShadowOrRoundedOuterCard() {
        let (_, switcher) = makeHost(width: 390, height: 844)
        let descendants = allViews(in: switcher)

        XCTAssertFalse(descendants.contains { $0 is UITabBar })
        XCTAssertFalse(descendants.contains { $0 is UIVisualEffectView })
        XCTAssertFalse(descendants.contains { $0.layer.sublayers?.contains { $0 is CAGradientLayer } == true })
        XCTAssertEqual(switcher.layer.shadowOpacity, 0)
        XCTAssertEqual(switcher.layer.cornerRadius, 0)
        XCTAssertEqual(switcher.backgroundColor, CommercialShellSectionSwitcher.surfaceColor)
        XCTAssertTrue(switcher.isOpaque)
    }

    private func assertControlSizes(width: CGFloat, height: CGFloat, file: StaticString = #filePath, line: UInt = #line) {
        let (_, switcher) = makeHost(width: width, height: height)
        for button in controlButtons(in: switcher) {
            XCTAssertGreaterThanOrEqual(button.bounds.width, 44, file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44, file: file, line: line)
        }
    }

    private func makeHost(width: CGFloat, height: CGFloat) -> (UIViewController, CommercialShellSectionSwitcher) {
        let host = UIViewController()
        host.loadViewIfNeeded()
        host.view.frame = CGRect(x: 0, y: 0, width: width, height: height)

        let switcher = CommercialShellSectionSwitcher()
        host.view.addSubview(switcher)
        switcher.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            switcher.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
            switcher.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
            switcher.bottomAnchor.constraint(equalTo: host.view.bottomAnchor)
        ])
        host.view.layoutIfNeeded()
        return (host, switcher)
    }

    private func controlButtons(in switcher: CommercialShellSectionSwitcher) -> [UIButton] {
        allViews(in: switcher)
            .compactMap { $0 as? UIButton }
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    private func button(in switcher: CommercialShellSectionSwitcher, identifier: String) -> UIButton {
        guard let button = controlButtons(in: switcher).first(where: { $0.accessibilityIdentifier == identifier }) else {
            XCTFail("Missing switcher control \(identifier)")
            return UIButton(type: .system)
        }
        return button
    }

    private func allViews(in root: UIView) -> [UIView] {
        [root] + root.subviews.flatMap(allViews)
    }
}
