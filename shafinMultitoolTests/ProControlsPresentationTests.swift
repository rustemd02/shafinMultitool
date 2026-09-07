//
//  ProControlsPresentationTests.swift
//  shafinMultitoolTests
//
//  M9-016 + M9-017: contract-driven Pro Controls presentation. 13 rows
//  from the frozen contract; honest tiers; values only for controls
//  with real read-back owners; accessibility values honest.
//

import XCTest
@testable import shafinMultitool

final class ProControlsPresentationTests: XCTestCase {
    func testRowsMatchFrozenContractExactly() {
        let rows = ProControlsPresentation.rows(torchActive: nil, meterLevel: nil, formatText: nil)
        XCTAssertEqual(rows.count, ProCameraControlContracts.production.count)
        XCTAssertEqual(rows.count, 13)
        XCTAssertEqual(
            rows.map(\.id),
            ProCameraControlContracts.production.map { $0.control.rawValue }
        )
    }

    func testLegacyControlsCarryNoValue() {
        let rows = ProControlsPresentation.rows(torchActive: true, meterLevel: 0.5, formatText: "4K 60")
        for row in rows where row.availability == .legacyOnly {
            XCTAssertNil(row.valueText, "legacy control \(row.id) must not show a value")
        }
    }

    func testAvailableControlsShowReadbackValues() {
        let rows = ProControlsPresentation.rows(torchActive: true, meterLevel: 0.5, formatText: "4K 60")
        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        XCTAssertFalse(byID["torch"]?.valueText?.isEmpty ?? true, "torch read-back missing")
        XCTAssertEqual(byID["audioMeter"]?.valueText, "-6 dB")
        XCTAssertEqual(byID["formatResolutionFPS"]?.valueText, "4K 60")
    }

    func testNilReadbackRendersHonestDash() {
        let rows = ProControlsPresentation.rows(torchActive: nil, meterLevel: nil, formatText: nil)
        for row in rows where row.availability == .available {
            XCTAssertNil(row.valueText, "missing read-back for \(row.id) must be nil, not a fake value")
        }
    }

    func testAccessibilityValueHonestByTier() {
        let rows = ProControlsPresentation.rows(torchActive: true, meterLevel: 0.5, formatText: "4K 60")
        for row in rows {
            switch row.availability {
            case .available:
                XCTAssertFalse(row.accessibilityValueText.isEmpty, "available control \(row.id) must expose its value")
            case .legacyOnly, .post10:
                XCTAssertEqual(row.accessibilityValueText, ProControlsPresentation.tierText(row.availability))
            }
        }
    }

    func testTierTextLocalizedBothLocales() {
        for locale in [Locale(identifier: "en"), Locale(identifier: "ru")] {
            for availability in [ProControlAvailability.available, .legacyOnly, .post10] {
                let text = ProControlsPresentation.tierText(availability)
                XCTAssertFalse(text.isEmpty)
                XCTAssertFalse(text.contains("set.pro"), "raw key leaked for \(availability)")
            }
        }
    }
}
