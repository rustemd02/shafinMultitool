import Foundation
@testable import shafinMultitool

/// Synthetic calibration for contract/lifecycle tests only. These curves are
/// not fitted evidence, are not app resources, and must never enable Release.
/// Positive owner-chain tests name this dependency explicitly; the production
/// default remains unavailable and has separate negative coverage.
enum CameraEpisodeCalibrationFixture {
    static var calibrator: CameraConfidenceCalibrator {
        let actionIDs = Set(
            SemanticActionType.allCases
                .filter { UserMovementObserver.actionFamily(for: $0) != nil }
                .map(\.rawValue)
            + [TechnicalQualityActionType.stabilizeCamera.rawValue]
        )
        let entries = Dictionary(uniqueKeysWithValues: actionIDs.map { actionID in
            (actionID, CameraCalibrationCurveV1(
                actionID: actionID,
                version: 1,
                knots: [
                    CameraCalibrationKnotV1(raw: 0, calibrated: 0.02),
                    CameraCalibrationKnotV1(raw: 0.5, calibrated: 0.65),
                    CameraCalibrationKnotV1(raw: 1, calibrated: 0.98)
                ],
                domainLow: 0,
                domainHigh: 1,
                inputVersion: UserMovementObserver.actionFamily(for: actionID) == .stability
                    ? .technicalStabilityConfidenceV1 : .boundedPlanConfidenceV1
            ))
        })
        return CameraConfidenceCalibrator(schema: CameraActionCalibrationSchemaV1(entries: entries))
    }
}
