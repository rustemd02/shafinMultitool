import XCTest
@testable import shafinMultitool

final class ProControlsPresentationTests: XCTestCase {
    private let en = Locale(identifier: "en")

    func testMissingDeviceNeverManufacturesValuesOrSupport() {
        let rows = ProControlsPresentation.rows(snapshot: nil, meterLevel: 0.5, locale: en)
        XCTAssertEqual(rows.map(\.id), ProCameraControl.allCases.map(\.rawValue))
        XCTAssertEqual(rows.count, 13)
        for row in rows {
            XCTAssertNil(row.valueText)
            XCTAssertFalse(row.isSupported)
            XCTAssertEqual(row.accessibilityValueText(locale: en),
                           SETCopyKey.proControlUnsupported.localizedString(locale: en))
        }
    }

    func testReadbackShowsConfiguredDimensionsFrameRateAndTrueRMS() {
        var observation = CameraProControlReadback()
        observation.width = 3840
        observation.height = 2160
        observation.fixedFPS = 60
        observation.exposureDuration = 1.0 / 120
        observation.iso = 320
        observation.torchActive = true
        let state = CameraProControlsSnapshot(deviceID: "back", captureGeneration: 4,
            capabilities: .init(), readback: observation)
        let values = Dictionary(uniqueKeysWithValues: ProControlsPresentation.rows(
            snapshot: state, meterLevel: 0.5, locale: en).map { ($0.id, $0.valueText) })
        XCTAssertEqual(values["formatResolutionFPS"]!, "3840×2160 · 60 FPS")
        XCTAssertEqual(values["exposureManualShutterAngleISO"]!, "180° · ISO 320")
        XCTAssertEqual(values["audioMeter"]!, "-6 dBFS")
        XCTAssertEqual(values["torch"]!, SETCopyKey.proControlValueOn.localizedString(locale: en))
    }

    func testUnknownFrameRateKeepsActualDimensionsWithoutInventingAngle() {
        var observation = CameraProControlReadback()
        observation.width = 1920
        observation.height = 1080
        observation.exposureDuration = 0.01
        observation.iso = 100
        let format = ProControlsPresentation.valueText(for: .formatResolutionFPS,
                                                       readback: observation, locale: en)
        XCTAssertEqual(format, "1920×1080 · \(SETCopyKey.proControlVariableFPS.localizedString(locale: en))")
        XCTAssertNil(ProControlsPresentation.valueText(for: .exposureManualShutterAngleISO,
                                                      readback: observation, locale: en))
    }

    func testMissingAndInvalidMicrophoneSamplesRemainUnknown() {
        for level: Float? in [nil, .nan, .infinity, -0.1, 1.1] {
            XCTAssertNil(ProControlsPresentation.valueText(for: .audioMeter, readback: .init(),
                                                           meterLevel: level, locale: en))
        }
        XCTAssertEqual(ProControlsPresentation.valueText(for: .audioMeter, readback: .init(),
                                                         meterLevel: 0, locale: en), "-80 dBFS")
    }

    func testObservationDoesNotImplyManualFocusCapability() {
        var observation = CameraProControlReadback()
        observation.lensPosition = 0.75
        let state = CameraProControlsSnapshot(deviceID: "fixed-focus", captureGeneration: 1,
                                             capabilities: .init(), readback: observation)
        let row = ProControlsPresentation.rows(snapshot: state, meterLevel: nil, locale: en)
            .first { $0.id == ProCameraControl.focusManual.rawValue }!
        XCTAssertEqual(row.valueText, "0.75")
        XCTAssertFalse(row.isSupported)
        XCTAssertEqual(row.accessibilityValueText(locale: en),
                       SETCopyKey.proControlUnsupported.localizedString(locale: en))
    }

    func testEveryControlFailureHasLocalizedRecoveryText() {
        let errors: [CameraProControlError] = [.unavailable, .unsupported, .invalidValue,
            .configurationFailed, .stale, .busy, .focusTimeout, .applicationTimeout, .microphoneDenied]
        for error in errors {
            let key = ProControlsPresentation.errorKey(error)
            let english = key.localizedString(locale: en)
            let russian = key.localizedString(locale: Locale(identifier: "ru"))
            XCTAssertFalse(english.isEmpty)
            XCTAssertFalse(russian.isEmpty)
            XCTAssertNotEqual(english, key.rawValue)
            XCTAssertNotEqual(russian, key.rawValue)
            XCTAssertNotEqual(english, russian)
        }
    }
}
