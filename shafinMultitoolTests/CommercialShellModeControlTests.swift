import UIKit
import XCTest
@testable import shafinMultitool

@MainActor
final class CommercialShellModeControlTests: XCTestCase {
    func testABRollCapsuleHasTwoLabeledSegmentsAndSharedTargets() {
        XCTAssertEqual(SETABRollCapsuleContract.title, "A/B ROLL")
        XCTAssertEqual(SETABRollCapsuleContract.segments, [.camera, .scenes])
        XCTAssertEqual(
            Set(SETABRollCapsuleContract.segments.map(\.accessibilityIdentifier)),
            ["commercial-shell-return-camera", "commercial-shell-open-scenes"]
        )
        XCTAssertGreaterThanOrEqual(
            SETABRollCapsuleContract.minimumSegmentSize.width,
            SETComponentMetric.minimumHitTarget
        )
        XCTAssertGreaterThanOrEqual(
            SETABRollCapsuleContract.minimumSegmentSize.height,
            SETComponentMetric.minimumHitTarget
        )
        XCTAssertFalse(SETABRollCapsuleContract.usesMaterial)
        XCTAssertFalse(SETABRollCapsuleContract.usesBlur)
        XCTAssertFalse(SETABRollCapsuleContract.usesShadow)
    }

    func testCameraSelectionKeepsCameraBrightAndScenesTapEmitsOpenScenes() throws {
        let (_, control) = makeHost()
        var intents: [CommercialShellModeControl.Intent] = []
        control.onIntentRequested = { intents.append($0) }

        let cameraButton = try button(in: control, identifier: "commercial-shell-return-camera")
        let scenesButton = try button(in: control, identifier: "commercial-shell-open-scenes")
        XCTAssertTrue(cameraButton.accessibilityTraits.contains(.selected))
        XCTAssertEqual(cameraButton.titleColor(for: .normal), SETPalette.textPrimary.uiColor)
        XCTAssertTrue(cameraButton.isUserInteractionEnabled)
        XCTAssertTrue(scenesButton.isUserInteractionEnabled)

        cameraButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(intents, [])
        scenesButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(intents, [.openScenes])
        XCTAssertEqual(control.renderedSection, .camera)
    }

    func testScenesSelectionKeepsScenesBrightAndCameraTapReturns() throws {
        let (_, control) = makeHost()
        control.render(selectedSection: .scenes, isInteractionLocked: false)
        var intents: [CommercialShellModeControl.Intent] = []
        control.onIntentRequested = { intents.append($0) }

        let cameraButton = try button(in: control, identifier: "commercial-shell-return-camera")
        let scenesButton = try button(in: control, identifier: "commercial-shell-open-scenes")
        XCTAssertTrue(scenesButton.accessibilityTraits.contains(.selected))
        XCTAssertEqual(scenesButton.titleColor(for: .normal), SETPalette.textPrimary.uiColor)
        XCTAssertTrue(cameraButton.isUserInteractionEnabled)
        XCTAssertTrue(scenesButton.isUserInteractionEnabled)

        scenesButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(intents, [])
        cameraButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(intents, [.returnCamera])
        XCTAssertEqual(control.renderedSection, .scenes)
    }

    func testHistoryHasNoSelectedRollAndCameraReturnRemainsAvailable() throws {
        let (_, control) = makeHost()
        control.render(selectedSection: .history, isInteractionLocked: false)
        var intents: [CommercialShellModeControl.Intent] = []
        control.onIntentRequested = { intents.append($0) }

        let cameraButton = try button(in: control, identifier: "commercial-shell-return-camera")
        let scenesButton = try button(in: control, identifier: "commercial-shell-open-scenes")
        XCTAssertFalse(cameraButton.accessibilityTraits.contains(.selected))
        XCTAssertFalse(scenesButton.accessibilityTraits.contains(.selected))
        XCTAssertTrue(cameraButton.isUserInteractionEnabled)
        XCTAssertTrue(scenesButton.isUserInteractionEnabled)

        cameraButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(intents, [.returnCamera])
    }

    func testLockedDisablesBothSegmentsAndUnlockedRestoresBothIntents() throws {
        let (_, control) = makeHost()
        var intents: [CommercialShellModeControl.Intent] = []
        control.onIntentRequested = { intents.append($0) }

        control.render(selectedSection: .camera, isInteractionLocked: true)
        let cameraButton = try button(in: control, identifier: "commercial-shell-return-camera")
        let scenesButton = try button(in: control, identifier: "commercial-shell-open-scenes")
        XCTAssertFalse(cameraButton.isUserInteractionEnabled)
        XCTAssertFalse(scenesButton.isUserInteractionEnabled)
        XCTAssertTrue(cameraButton.accessibilityTraits.contains(.notEnabled))
        XCTAssertTrue(scenesButton.accessibilityTraits.contains(.notEnabled))
        cameraButton.sendActions(for: .touchUpInside)
        scenesButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(intents, [])

        control.render(selectedSection: .camera, isInteractionLocked: false)
        XCTAssertTrue(cameraButton.isUserInteractionEnabled)
        XCTAssertTrue(scenesButton.isUserInteractionEnabled)
        XCTAssertFalse(cameraButton.accessibilityTraits.contains(.notEnabled))
        XCTAssertFalse(scenesButton.accessibilityTraits.contains(.notEnabled))
        cameraButton.sendActions(for: .touchUpInside)
        scenesButton.sendActions(for: .touchUpInside)
        XCTAssertEqual(intents, [.openScenes])
    }

    func testBothSegmentBoundsMeetTheMinimumInPortraitAndLandscape() throws {
        for size in [CGSize(width: 390, height: 844), CGSize(width: 844, height: 390)] {
            let (_, control) = makeHost(size: size)
            XCTAssertEqual(control.bounds.size, SETABRollCapsuleContract.minimumControlSize)
            for identifier in ["commercial-shell-return-camera", "commercial-shell-open-scenes"] {
                let button = try self.button(in: control, identifier: identifier)
                XCTAssertGreaterThanOrEqual(button.bounds.width, SETComponentMetric.minimumHitTarget)
                XCTAssertGreaterThanOrEqual(button.bounds.height, SETComponentMetric.minimumHitTarget)
            }
        }
    }

    func testTitleAndCapsuleOccupyThePublishedControlContract() throws {
        let (_, control) = makeHost()
        let title = try XCTUnwrap(control.subviews.compactMap { $0 as? UILabel }.first)
        let capsule = try XCTUnwrap(
            control.subviews.first { view in
                view.subviews.contains { $0 is UIButton }
            }
        )

        XCTAssertEqual(title.frame.minY, 0, accuracy: 0.5)
        XCTAssertEqual(title.frame.height, SETTypographySize.micro, accuracy: 0.5)
        XCTAssertEqual(capsule.frame.minY, SETTypographySize.micro + SETSpacing.x1, accuracy: 0.5)
        XCTAssertEqual(capsule.frame.width, SETABRollCapsuleContract.minimumControlSize.width, accuracy: 0.5)
        XCTAssertEqual(capsule.frame.height, SETABRollCapsuleContract.minimumSegmentSize.height, accuracy: 0.5)
        XCTAssertEqual(capsule.layer.cornerRadius, capsule.frame.height / 2, accuracy: 0.5)
        XCTAssertFalse(capsule.isHidden)
        XCTAssertEqual(capsule.alpha, 1, accuracy: 0.01)
    }

    func testControlHasNoForbiddenVisualLayers() {
        let (_, control) = makeHost()
        let descendants = allViews(in: control)
        XCTAssertFalse(descendants.contains { $0 is UITabBar })
        XCTAssertFalse(descendants.contains { $0 is UIVisualEffectView })
        XCTAssertFalse(descendants.contains { view in
            view.layer.sublayers?.contains { $0 is CAGradientLayer } == true
        })
        XCTAssertEqual(control.layer.cornerRadius, 0)
        XCTAssertEqual(control.layer.shadowOpacity, 0)
        XCTAssertEqual(control.backgroundColor, .clear)
        XCTAssertTrue(allButtons(in: control).allSatisfy { $0.backgroundColor == .clear })
    }

    private func makeHost(
        size: CGSize = CGSize(width: 390, height: 844)
    ) -> (UIViewController, CommercialShellModeControl) {
        let host = UIViewController()
        host.loadViewIfNeeded()
        host.view.frame = CGRect(origin: .zero, size: size)

        let control = CommercialShellModeControl()
        host.view.addSubview(control)
        control.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: host.view.centerXAnchor),
            control.centerYAnchor.constraint(equalTo: host.view.centerYAnchor),
            control.widthAnchor.constraint(equalToConstant: SETABRollCapsuleContract.minimumControlSize.width),
            control.heightAnchor.constraint(equalToConstant: SETABRollCapsuleContract.minimumControlSize.height)
        ])
        host.view.layoutIfNeeded()
        control.layoutIfNeeded()
        return (host, control)
    }

    private func button(
        in control: CommercialShellModeControl,
        identifier: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> UIButton {
        guard let button = allButtons(in: control).first(where: { $0.accessibilityIdentifier == identifier }) else {
            XCTFail("Missing shell segment \(identifier)", file: file, line: line)
            throw XCTSkip("Missing shell segment")
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
