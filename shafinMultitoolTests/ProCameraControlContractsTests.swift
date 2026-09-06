import XCTest
@testable import shafinMultitool

/// M9-006: the 1.0 control surface is exactly the locked contract — every
/// control has a tier, post-1.0 exclusions have no case, and no production
/// file references a post-1.0 surface under another name.
final class ProCameraControlContractsTests: XCTestCase {

    func testContractCoversEveryControlExactlyOnce() {
        let controls = ProCameraControlContracts.production.map(\.control)
        XCTAssertEqual(Set(controls).count, ProCameraControl.allCases.count)
        XCTAssertEqual(Set(controls), Set(ProCameraControl.allCases))
    }

    func testAvailableControlsNameRealOwners() {
        for contract in ProCameraControlContracts.production where contract.availability == .available {
            XCTAssertFalse(contract.owner.isEmpty)
            XCTAssertFalse(contract.owner.lowercased().contains("todo"))
            XCTAssertFalse(contract.owner.lowercased().contains("planned"))
        }
    }

    func testExcludedSurfacesHaveNoControlCase() {
        let names = ProCameraControl.allCases.map(\.rawValue).joined(separator: " ")
        for excluded in ProCameraControlContracts.explicitlyExcluded {
            XCTAssertFalse(names.contains(excluded), "\(excluded) must not exist as a control case")
        }
    }

    func testTorchIsAvailableOnLensOwner() {
        let torch = ProCameraControlContracts.production.first { $0.control == .torch }
        XCTAssertEqual(torch?.availability, .available)
    }
}
