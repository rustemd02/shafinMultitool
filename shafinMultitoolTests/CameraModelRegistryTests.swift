import XCTest
@testable import shafinMultitool

/// M4-021: exactly one approved bundled model active; mismatch disables
/// neural advice with honest unavailable state; rollback restores only via
/// app update with a compatible artifact.
final class CameraModelRegistryTests: XCTestCase {

    private func makeVersion(candidate: String = "candidate-a",
                             contract: String = SETCompositionNetContract.contractVersion,
                             calibration: String = "cal1") -> CameraModelVersion {
        CameraModelVersion(
            contractVersion: contract,
            candidateID: candidate,
            trainingReceiptSHA256: String(repeating: "a", count: 64),
            conversionReceiptSHA256: String(repeating: "b", count: 64),
            calibrationVersion: calibration
        )
    }

    func testNoBundledArtifactIsUnavailable() {
        let activation = CameraModelRegistry.activation(
            bundled: nil,
            contractVersion: SETCompositionNetContract.contractVersion,
            calibrationVersion: "cal1"
        )
        XCTAssertEqual(activation, .unavailable(reason: "no approved bundled model artifact"))
    }

    func testMatchingMetadataActivatesExactlyOneModel() {
        let version = makeVersion()
        let activation = CameraModelRegistry.activation(
            bundled: version,
            contractVersion: SETCompositionNetContract.contractVersion,
            calibrationVersion: "cal1"
        )
        XCTAssertEqual(activation, .active(version: version))
    }

    func testContractMismatchDisables() {
        let activation = CameraModelRegistry.activation(
            bundled: makeVersion(contract: "setcompositionnet.v0"),
            contractVersion: SETCompositionNetContract.contractVersion,
            calibrationVersion: "cal1"
        )
        guard case let .mismatchDisabled(detail) = activation else {
            return XCTFail("contract mismatch must disable, got \(activation)")
        }
        XCTAssertTrue(detail.contains("contract"))
    }

    func testCalibrationMismatchDisables() {
        let activation = CameraModelRegistry.activation(
            bundled: makeVersion(calibration: "cal0"),
            contractVersion: SETCompositionNetContract.contractVersion,
            calibrationVersion: "cal1"
        )
        guard case .mismatchDisabled = activation else {
            return XCTFail("calibration mismatch must disable, got \(activation)")
        }
    }

    func testMalformedReceiptDisables() {
        var version = makeVersion()
        version = CameraModelVersion(
            contractVersion: version.contractVersion,
            candidateID: version.candidateID,
            trainingReceiptSHA256: "short",
            conversionReceiptSHA256: version.conversionReceiptSHA256,
            calibrationVersion: version.calibrationVersion
        )
        let activation = CameraModelRegistry.activation(
            bundled: version,
            contractVersion: SETCompositionNetContract.contractVersion,
            calibrationVersion: "cal1"
        )
        guard case .mismatchDisabled = activation else {
            return XCTFail("malformed receipt must disable, got \(activation)")
        }
    }

    func testRollbackTargetsCompatiblePriorVersionOnly() {
        let current = makeVersion(candidate: "candidate-b")
        let good = makeVersion(candidate: "candidate-a")
        XCTAssertEqual(
            CameraModelRegistry.rollbackTarget(
                current: current, lastKnownGood: good,
                contractVersion: SETCompositionNetContract.contractVersion),
            good
        )
        XCTAssertNil(CameraModelRegistry.rollbackTarget(
            current: current,
            lastKnownGood: makeVersion(candidate: "candidate-a", contract: "v0"),
            contractVersion: SETCompositionNetContract.contractVersion),
            "incompatible rollback target must not restore")
        XCTAssertNil(CameraModelRegistry.rollbackTarget(
            current: current, lastKnownGood: current,
            contractVersion: SETCompositionNetContract.contractVersion),
            "same-candidate rollback is a no-op")
    }
}
