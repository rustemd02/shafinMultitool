import UIKit
import SwiftUI
import XCTest
@testable import shafinMultitool

final class SETFixtureCatalogTests: XCTestCase {
    func testManifestCoversEveryPhaseZeroScreenFamilyAndState() {
        let expectedIDs: Set<String> = [
            "foundations.palette", "foundations.typography",
            "components.wordmark-horizontal", "components.wordmark-stacked",
            "components.poster-action", "components.hud", "components.marker-reflow",
            "components.roll-capsule", "components.leader",
            "entry.resolving", "entry.requesting", "entry.ready", "entry.intro",
            "entry.permission", "entry.blocked-denied", "entry.blocked-restricted",
            "entry.blocked-unavailable", "entry.blocked-unknown",
            "camera.starting", "camera.interrupted", "camera.failed", "camera.seeking",
            "camera.keep", "camera.corrective", "camera.fallback", "camera.explanation",
            "camera.lens-switching", "camera.resuming", "camera.eco",
            "camera.pause-loading", "camera.pause-success", "camera.pause-empty",
            "camera.pause-failure",
            "generator.preflight", "generator.clarification", "generator.progress",
            "generator.cancelled", "generator.failure", "generator.result",
            "library.contact-sheet", "storyboard.result"
        ]

        XCTAssertEqual(SETFixtureCatalog.requiredFixtureIDs, expectedIDs)
        XCTAssertEqual(Set(SETFixtureCatalog.manifest.map(\.id)), expectedIDs)
        XCTAssertEqual(SETFixtureCatalog.manifest.count, expectedIDs.count)
        XCTAssertEqual(
            Set(SETFixtureCatalog.manifest.map(\.family)),
            Set(SETFixtureFamily.allCases)
        )
    }

    func testManifestHasUniqueIDsAndSafeOrientationContracts() {
        let IDs = SETFixtureCatalog.manifest.map(\.id)
        XCTAssertEqual(Set(IDs).count, IDs.count)
        XCTAssertNil(SETFixtureCatalog.fixture(id: nil))
        XCTAssertNil(SETFixtureCatalog.fixture(id: "unknown.fixture"))

        for descriptor in SETFixtureCatalog.manifest {
            XCTAssertEqual(SETFixtureCatalog.fixture(id: descriptor.id), descriptor)
            switch descriptor.family {
            case .generator, .library, .storyboard:
                XCTAssertEqual(descriptor.orientation, .landscape, descriptor.id)
            case .foundations, .components, .entry, .camera, .pause:
                XCTAssertEqual(descriptor.orientation, .adaptive, descriptor.id)
            }
        }
    }

    func testGalleryRequiresBothLocalesAndAccessibilityVariants() {
        XCTAssertEqual(SETFixtureCatalog.requiredLocales, [.ru, .en])
        XCTAssertEqual(
            SETFixtureCatalog.requiredAccessibilityModes,
            ["default", "reduce-motion", "reduce-transparency", "xxl"]
        )
    }

    func testCameraBitmapFixtureDecodesFromTheApplicationBundle() throws {
        XCTAssertNotNil(
            SETBundledImage.uiImage(named: "SETCameraFrame"),
            "Camera fixture must decode from its copied raw PNG, not only exist on disk"
        )
    }

#if DEBUG
    func testGeneratorFixtureCatalogIncludesProductionDecisionTraceRoute() {
        XCTAssertTrue(
            SETFixtureCatalog.generatorStoryboardFixtureIDs.contains("sheet.decision-trace")
        )
    }

    func testGalleryRootPreemptsBenchmarkAndCommercialBuilders() {
        let root = SceneDelegate.makeRootViewController(
            galleryConfiguration: SETGalleryLaunchConfiguration(fixtureID: "entry.intro"),
            benchmarkConfig: nil,
            benchmarkRootBuilder: { _ in
                XCTFail("Benchmark builder must not run for gallery launch")
                return UIViewController()
            },
            commercialRootBuilder: {
                XCTFail("Commercial builder must not run for gallery launch")
                return UIViewController()
            }
        )

        XCTAssertTrue(root is UIHostingController<DesignSystemPreviews>)
    }

    func testLaunchConfigurationParsesDeterministicGalleryArguments() {
        let configuration = SETGalleryLaunchConfiguration(arguments: [
            SETGalleryLaunchConfiguration.galleryArgument,
            SETGalleryLaunchConfiguration.fixtureArgument, "camera.fallback",
            SETGalleryLaunchConfiguration.localeArgument, "en",
            SETGalleryLaunchConfiguration.reduceMotionArgument, "1",
            SETGalleryLaunchConfiguration.reduceTransparencyArgument, "true",
            SETGalleryLaunchConfiguration.dynamicTypeArgument, "xxl"
        ])

        XCTAssertEqual(configuration.fixtureID, "camera.fallback")
        XCTAssertEqual(configuration.locale, .en)
        XCTAssertTrue(configuration.reduceMotion)
        XCTAssertTrue(configuration.reduceTransparency)
        XCTAssertTrue(configuration.dynamicTypeSize.isAccessibilitySize)
    }

    func testLaunchConfigurationDefaultsToRussianWithoutOptionalVariants() {
        let configuration = SETGalleryLaunchConfiguration(arguments: [
            SETGalleryLaunchConfiguration.galleryArgument
        ])

        XCTAssertNil(configuration.fixtureID)
        XCTAssertEqual(configuration.locale, .ru)
        XCTAssertFalse(configuration.reduceMotion)
        XCTAssertFalse(configuration.reduceTransparency)
        XCTAssertFalse(configuration.dynamicTypeSize.isAccessibilitySize)
    }
#endif
}
