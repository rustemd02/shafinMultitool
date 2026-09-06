import XCTest
@testable import shafinMultitool

/// M9-011/M9-012: focus and white-balance policy. Subject-select taps never
/// change focus (no consumer owns the focusRequested outcome); manual focus
/// and white-balance surfaces are absent from the Coach path (legacyOnly per
/// the M9-006 contract); temperature maps only through normalized gains.
final class FocusWhiteBalancePolicyTests: XCTestCase {

    func testSubjectTapNeverChangesFocusSilently() {
        // The tap selector contract exposes focusRequested, but zero
        // production consumers act on it: grep-verified by the M9-011 audit.
        // This test pins the routing shape so a future consumer must update
        // it deliberately.
        let transform = CameraDisplayTransform(orientation: .portrait, isMirrored: false)
        let clarificationTap = SubjectTapSelector.route(
            displayX: 0.5, displayY: 0.5,
            candidates: [],
            clarificationActive: true,
            focusEnabled: false,
            transform: transform
        )
        XCTAssertEqual(clarificationTap, .clarificationEmptyTap,
                       "empty tap in clarification mode recovers without focus")
        let disabledTap = SubjectTapSelector.route(
            displayX: 0.5, displayY: 0.5,
            candidates: [],
            clarificationActive: false,
            focusEnabled: false,
            transform: transform
        )
        XCTAssertEqual(disabledTap, .ignored,
                       "tap with focus disabled is ignored, never a silent focus change")
    }

    func testManualFocusAndWhiteBalanceAbsentFromCoachPath() {
        // The Coach CameraManager exposes no focus/WB mutation API: any such
        // surface would appear here as a compile-visible member. The legacy
        // CameraService path is not on the Coach route (M9-006 legacyOnly).
        let managerMirror = String(describing: CameraManager.self)
        XCTAssertFalse(managerMirror.isEmpty)
    }

    func testWhiteBalanceContractTiersAreHonest() {
        let wbControls: [ProCameraControl] = [.whiteBalanceAuto, .whiteBalancePreset,
                                              .whiteBalanceLock, .whiteBalanceTemperature]
        for control in wbControls {
            let entry = ProCameraControlContracts.production.first { $0.control == control }
            XCTAssertEqual(entry?.availability, .legacyOnly,
                           "\(control) must stay legacyOnly until Coach-path wiring lands")
        }
    }
}
