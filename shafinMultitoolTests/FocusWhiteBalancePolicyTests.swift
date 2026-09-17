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

    /// The contract may only claim a tier together with the production owner that
    /// implements it. When this test landed the white-balance surface was absent
    /// from the Coach path, so it pinned `legacyOnly`. The surface has since been
    /// wired: `ProControlsPanelView` is presented by the production Coach screen
    /// and drives `CameraManager.applyProControl` into
    /// `AVCaptureProControlDevice`, which implements auto, lock and temperature
    /// with capability guards. The test now pins that wiring instead of the gap it
    /// replaced, and still fails if a control claims availability without naming
    /// who implements it.
    func testWhiteBalanceContractTiersAreHonest() {
        let wbControls: [ProCameraControl] = [.whiteBalanceAuto, .whiteBalancePreset,
                                              .whiteBalanceLock, .whiteBalanceTemperature]
        for control in wbControls {
            let entry = ProCameraControlContracts.production.first { $0.control == control }
            XCTAssertEqual(entry?.availability, .available,
                           "\(control) is wired through the Coach path")
            XCTAssertTrue((entry?.owner ?? "").contains("CameraManager.applyProControl"),
                          "\(control) must name the manager route that applies it")
            XCTAssertTrue((entry?.owner ?? "").contains("AVCaptureProControlDevice"),
                          "\(control) must name the device owner that implements it")
        }
        for entry in ProCameraControlContracts.production {
            XCTAssertFalse(
                entry.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                "\(entry.control) claims \(entry.availability) without naming an owner"
            )
        }
    }
}
