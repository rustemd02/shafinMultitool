import CoreGraphics
import XCTest
@testable import shafinMultitool

/// UI-008 focused checks: the presentation-layer wrappers behind the VoiceOver
/// surface. These tests own the parts a physical VoiceOver journey cannot
/// prove here: the announcement cadence gate, the verbal target-region
/// alternative and the RU/EN existence of every accessibility copy key this
/// surface depends on.
final class CameraCoachAccessibilityPresentationTests: XCTestCase {

    // MARK: - Live region cadence (UI-008c)

    func testAnnouncementGateAdmitsEachChangedCopyExactlyOnce() {
        var gate = CameraCoachHintAnnouncementGate()

        XCTAssertTrue(gate.shouldAnnounce(copy: "Сдвиньте кадр влево"))
        XCTAssertFalse(gate.shouldAnnounce(copy: "Сдвиньте кадр влево"), "same copy must not re-announce")

        XCTAssertTrue(gate.shouldAnnounce(copy: "Кадр можно сравнить"), "changed copy is announced once")
        XCTAssertFalse(gate.shouldAnnounce(copy: "Кадр можно сравнить"))
    }

    func testAnnouncementGateRejectsEmptyCopyWithoutClobberingLastAnnouncement() {
        var gate = CameraCoachHintAnnouncementGate()

        XCTAssertTrue(gate.shouldAnnounce(copy: "Выровняйте горизонт"))
        XCTAssertFalse(gate.shouldAnnounce(copy: ""))
        XCTAssertFalse(gate.shouldAnnounce(copy: "   "), "whitespace-only copy is empty copy")
        XCTAssertFalse(gate.shouldAnnounce(copy: "Выровняйте горизонт"), "empty copy must not reset the dedupe window")
        XCTAssertTrue(gate.shouldAnnounce(copy: "Приблизьтесь к объекту"))
    }

    // MARK: - Target overlay alternative (UI-008d)

    func testRegionWordsCoverAllNineBandsInEnglishAndRussian() {
        let en = Locale(identifier: "en")
        let ru = Locale(identifier: "ru")
        let xBands: [(String, Double)] = [("left", 0.0), ("centre", 0.4), ("right", 0.8)]
        let yBands: [(String, Double)] = [("top", 0.0), ("middle", 0.4), ("bottom", 0.8)]

        for (_, x) in xBands {
            for (_, y) in yBands {
                let region = NormalizedRect(x: x, y: y, width: 0.2, height: 0.2)
                let english = CameraOverlayUXPresentation.regionWords(for: region, locale: en)
                let russian = CameraOverlayUXPresentation.regionWords(for: region, locale: ru)

                XCTAssertTrue(english.hasPrefix("Target area"), english)
                XCTAssertTrue(russian.hasPrefix("Целевая область"), russian)
                XCTAssertFalse(english.contains(where: { $0.isNumber }), english)
                XCTAssertFalse(russian.contains(where: { $0.isNumber }), russian)
                XCTAssertFalse(english.isEmpty)
                XCTAssertFalse(russian.isEmpty)
            }
        }

        XCTAssertEqual(
            CameraOverlayUXPresentation.regionWords(
                for: NormalizedRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
                locale: en
            ),
            "Target area: upper part, on the left"
        )
        XCTAssertEqual(
            CameraOverlayUXPresentation.regionWords(
                for: NormalizedRect(x: 0.0, y: 0.0, width: 0.2, height: 0.2),
                locale: ru
            ),
            "Целевая область: верхняя часть, слева"
        )
        XCTAssertEqual(
            CameraOverlayUXPresentation.regionWords(
                for: NormalizedRect(x: 0.8, y: 0.8, width: 0.2, height: 0.2),
                locale: en
            ),
            "Target area: lower part, on the right"
        )
    }

    func testRegionWordsFailClosedOnDegenerateRegion() {
        let degenerate = NormalizedRect(x: 0.5, y: 0.5, width: 0, height: 0)
        XCTAssertEqual(
            CameraOverlayUXPresentation.regionWords(for: degenerate, locale: .current),
            ""
        )
    }

    func testTargetRegionAccessibilityValueMirrorsSpatialEvidencePresence() {
        var presentation = makePresentation()
        XCTAssertNil(presentation.targetRegion)
        XCTAssertNil(presentation.targetRegionAccessibilityValue)

        presentation = makePresentation(
            targetRegion: NormalizedRect(x: 0.6, y: 0.3, width: 0.2, height: 0.3)
        )
        XCTAssertEqual(
            presentation.targetRegionAccessibilityValue,
            CameraOverlayUXPresentation.regionWords(
                for: NormalizedRect(x: 0.6, y: 0.3, width: 0.2, height: 0.3),
                locale: .current
            )
        )
    }

    // MARK: - Localized accessibility copy (UI-008a/b)

    func testCycleControlAndClarityLabelsAreNonEmptyInBothLocales() {
        let locales = [Locale(identifier: "en"), Locale(identifier: "ru")]
        for locale in locales {
            for control in CameraCoachCycleControl.allCases {
                let label = control.label(locale: locale)
                XCTAssertFalse(label.trimmingCharacters(in: .whitespaces).isEmpty, "\(control) [\(locale)]")
            }
            for clarity in CameraOverlayUXPresentation.VerificationClarity.allCases {
                let label = clarity.label(locale: locale)
                XCTAssertFalse(label.trimmingCharacters(in: .whitespaces).isEmpty, "\(clarity) [\(locale)]")
            }
        }
    }

    func testRegionAndConversationAccessibilityKeysExistInCatalogForRuAndEn() throws {
        let strings = try catalogStrings()
        let keys = [
            "set.a11y.region.target", "set.a11y.region.top", "set.a11y.region.middle",
            "set.a11y.region.bottom", "set.a11y.region.left", "set.a11y.region.centre",
            "set.a11y.region.right",
            "set.camera.hint.repeat", "set.camera.hint.skip", "set.camera.hint.pause",
            "set.camera.hint.resume", "set.camera.status.comparable", "set.camera.status.unknown"
        ]
        for key in keys {
            for language in ["en", "ru"] {
                let value = try localizedValue(key, language, in: strings)
                XCTAssertFalse(value.trimmingCharacters(in: .whitespaces).isEmpty, "\(key) [\(language)]")
            }
        }
    }

    func testRepresentativeProjectionStatesKeepNonEmptyLocalizedVoiceOverCopy() {
        let locales = [Locale(identifier: "en"), Locale(identifier: "ru")]
        let contexts: [CameraOverlayUXContext] = [
            CameraOverlayUXContext(lifecycleState: .starting),
            CameraOverlayUXContext(lifecycleState: .stopping),
            CameraOverlayUXContext(analysisStatus: .failed),
            CameraOverlayUXContext(lensState: .switching(.wide)),
            CameraOverlayUXContext(pauseState: .loading(snapshotID: "fixture"))
        ]
        for locale in locales {
            for context in contexts {
                let presentation = CameraOverlayUXPresentation.make(liveHint: nil, context: context, locale: locale)
                let label = presentation.accessibilityLabel.trimmingCharacters(in: .whitespaces)
                XCTAssertFalse(label.isEmpty, "\(presentation.state) [\(locale)]")
            }
            for liveHint in [makeKeepHint(), nil] {
                let presentation = CameraOverlayUXPresentation.make(liveHint: liveHint, locale: locale)
                XCTAssertFalse(
                    presentation.accessibilityLabel.trimmingCharacters(in: .whitespaces).isEmpty,
                    "\(presentation.state) [\(locale)]"
                )
            }
        }
    }

    // MARK: - Helpers

    private func makePresentation(
        targetRegion: NormalizedRect? = nil
    ) -> CameraOverlayUXPresentation {
        CameraOverlayUXPresentation(
            state: .stableTip,
            baseState: .stableTip,
            observation: "observation",
            actionInstruction: "instruction",
            explanation: nil,
            supportingObservation: nil,
            showsWhy: false,
            isFallback: false,
            liveHintID: nil,
            episodeToken: nil,
            targetRegion: targetRegion,
            overlayHint: nil,
            eventID: nil,
            effectivePerformanceMode: .nominal,
            analysisStatus: .healthy
        )
    }

    private func makeKeepHint() -> LiveHintPresentation {
        LiveHintPresentation(
            id: "hint-keep",
            frameId: "frame-1",
            text: "Кадр сбалансирован.",
            confidence: 0.9,
            actionType: .leaveFrameAsIs,
            actionId: "leave_frame_as_is",
            linkedIssueIds: [],
            summaryId: nil,
            traceRootIds: [],
            targetRegion: nil,
            overlayHint: nil,
            isFallback: false,
            expandedVerdict: nil
        )
    }

    private func catalogStrings() throws -> [String: [String: Any]] {
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Resources/Localizable.xcstrings")
        let data = try JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any]
        return try XCTUnwrap(data?["strings"] as? [String: [String: Any]])
    }

    private func localizedValue(
        _ key: String, _ lang: String, in strings: [String: [String: Any]]
    ) throws -> String {
        let entry = try XCTUnwrap(strings[key], key)
        let localizations = try XCTUnwrap(entry["localizations"] as? [String: Any], key)
        let unit = try XCTUnwrap(localizations[lang] as? [String: Any], "\(key) [\(lang)]")
        let stringUnit = try XCTUnwrap(unit["stringUnit"] as? [String: Any], "\(key) [\(lang)]")
        return try XCTUnwrap(stringUnit["value"] as? String, "\(key) [\(lang)]")
    }
}
