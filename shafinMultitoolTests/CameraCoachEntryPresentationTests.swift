import Foundation
import XCTest
@testable import shafinMultitool

final class CameraCoachEntryPresentationTests: XCTestCase {
    func testS01CopyAndActionIdentifierAreConcrete() {
        XCTAssertEqual(CameraCoachEntryCopy.introTitle, "Снимайте увереннее")
        XCTAssertEqual(
            CameraCoachEntryCopy.introBody,
            "Camera Coach подсказывает, что улучшить в кадре. Базовый анализ работает на устройстве."
        )
        XCTAssertEqual(CameraCoachEntryCopy.introAction, "Открыть камеру")
        XCTAssertEqual(
            CameraCoachEntryView.primaryActionIdentifier(for: .intro),
            CameraCoachEntryAccessibilityID.openCameraAction
        )
    }

    func testS02CopyAndActionIdentifierExplainOnlyCameraAccess() {
        XCTAssertEqual(CameraCoachEntryCopy.permissionContextTitle, "Разрешите доступ к камере")
        XCTAssertEqual(
            CameraCoachEntryCopy.permissionContextBody,
            "Камера нужна, чтобы показать кадр и проверить изменение."
        )
        XCTAssertEqual(CameraCoachEntryCopy.localProcessingSentence, "Базовый анализ работает на устройстве.")
        XCTAssertEqual(CameraCoachEntryCopy.permissionContextAction, "Продолжить")
        XCTAssertEqual(
            CameraCoachEntryView.primaryActionIdentifier(for: .permissionContext),
            CameraCoachEntryAccessibilityID.continueAction
        )
        XCTAssertFalse(CameraCoachEntryCopy.permissionContextBody.contains("микрофон"))
        XCTAssertFalse(CameraCoachEntryCopy.permissionContextBody.contains("Фото"))
        XCTAssertFalse(CameraCoachEntryCopy.permissionContextBody.contains("речь"))
    }

    func testS03HasDistinctReasonsAndOnePrimaryActionPerVariant() {
        let cases: [(CameraCoachCameraBlockReason, String, String)] = [
            (.denied, CameraCoachEntryCopy.deniedTitle, CameraCoachEntryAccessibilityID.openSettingsAction),
            (.restricted, CameraCoachEntryCopy.restrictedTitle, CameraCoachEntryAccessibilityID.recheckAction),
            (.unavailable, CameraCoachEntryCopy.unavailableTitle, CameraCoachEntryAccessibilityID.recheckAction),
            (.unknown, CameraCoachEntryCopy.unknownTitle, CameraCoachEntryAccessibilityID.recheckAction)
        ]

        for (reason, title, primaryIdentifier) in cases {
            let phase = CameraCoachEntryPhase.blocked(reason)
            XCTAssertEqual(
                CameraCoachEntryView.primaryActionIdentifier(for: phase),
                primaryIdentifier,
                String(describing: reason)
            )
            XCTAssertTrue(title.lowercased().contains("камер"), title)
            XCTAssertFalse(CameraCoachEntryCopy.blockedBody.isEmpty)
        }

        XCTAssertEqual(CameraCoachEntryCopy.settingsAction, "Открыть Настройки")
        XCTAssertEqual(CameraCoachEntryCopy.recheckAction, "Проверить снова")
        XCTAssertTrue(CameraCoachEntryCopy.settingsFallback.contains("Настройки"))
    }

    func testEveryRenderedPhaseHasStableRootAndActionIdentifiers() {
        let phases: [CameraCoachEntryPhase] = [
            .resolving,
            .intro,
            .permissionContext,
            .requesting,
            .ready,
            .blocked(.denied),
            .blocked(.restricted),
            .blocked(.unavailable),
            .blocked(.unknown)
        ]

        let roots = phases.map(CameraCoachEntryView.rootAccessibilityIdentifier(for:))
        XCTAssertEqual(Set(roots).count, roots.count)
        XCTAssertTrue(roots.allSatisfy { $0.hasPrefix("camera-coach-entry-") })

        let actions = [
            CameraCoachEntryAccessibilityID.openCameraAction,
            CameraCoachEntryAccessibilityID.continueAction,
            CameraCoachEntryAccessibilityID.openSettingsAction,
            CameraCoachEntryAccessibilityID.recheckAction
        ]
        XCTAssertEqual(Set(actions).count, actions.count)
        XCTAssertTrue(actions.allSatisfy { $0.hasPrefix("camera-coach-entry-") })
    }

    func testResolvingAndRequestingHaveNoActionAndReadyHasNoEntryAction() {
        XCTAssertNil(CameraCoachEntryView.primaryActionIdentifier(for: .resolving))
        XCTAssertNil(CameraCoachEntryView.primaryActionIdentifier(for: .requesting))
        XCTAssertNil(CameraCoachEntryView.primaryActionIdentifier(for: .ready))
    }

    func testEntryVisualContractUsesSourceMarkersAndContainsNoFakeCameraSurface() throws {
        XCTAssertEqual(
            CameraCoachEntryVisualPolicy.sourceMarkers,
            [
                "neutral-surface",
                "typography-spacing-hierarchy",
                "no-camera-preview",
                "no-card-pill-glass-blur-gradient"
            ]
        )

        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        XCTAssertFalse(source.contains("CameraPreview"))
        XCTAssertFalse(source.contains("ProgressView"))
        XCTAssertFalse(source.contains("regularMaterial"))
        XCTAssertFalse(source.contains("RoundedRectangle"))
        XCTAssertFalse(source.contains("LinearGradient"))
    }

    func testEntrySurfaceDoesNotExposeLiveControls() {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Multitool2Module/EntryFlow/CameraCoachEntryView.swift")
        let source = (try? String(contentsOf: sourceURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(source.contains("record"))
        XCTAssertFalse(source.contains("pause"))
        XCTAssertFalse(source.contains("Deep Review"))
    }
}
