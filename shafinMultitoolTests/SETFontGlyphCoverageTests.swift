import CoreText
import CryptoKit
import Foundation
import XCTest
@testable import shafinMultitool

final class SETFontGlyphCoverageTests: XCTestCase {
    func testPinnedFontAssetsAreBundledWithExpectedHashesAndPostScriptNames() throws {
        for asset in SETTypography.assets {
            let url = try XCTUnwrap(fontURL(for: asset), "Missing bundled font \(asset.filename)")
            let digest = SHA256.hash(data: try Data(contentsOf: url))
                .map { String(format: "%02x", $0) }
                .joined()
            XCTAssertEqual(digest, asset.sha256, asset.filename)

            let descriptors = try XCTUnwrap(
                CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                "Font descriptors unavailable for \(asset.filename)"
            )
            XCTAssertTrue(
                descriptors.contains { descriptor in
                    let font = CTFontCreateWithFontDescriptor(descriptor, 17, nil)
                    return String(CTFontCopyPostScriptName(font)) == asset.postScriptName
                },
                "Unexpected PostScript names for \(asset.filename)"
            )
        }
    }

    func testLocalizedFontRolesCoverTheRequiredRussianAndEnglishCharacters() throws {
        let characters = Array(SETTypography.productCharacterSet.utf16)

        for asset in SETTypography.assets where asset.role.localizedTextAllowed {
            let url = try XCTUnwrap(fontURL(for: asset), "Missing bundled font \(asset.filename)")
            let descriptors = try XCTUnwrap(
                CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]
            )
            let descriptor = try XCTUnwrap(
                descriptors.first { descriptor in
                    let font = CTFontCreateWithFontDescriptor(descriptor, 17, nil)
                    return String(CTFontCopyPostScriptName(font)) == asset.postScriptName
                },
                "No regular face for \(asset.filename)"
            )
            let font = CTFontCreateWithFontDescriptor(descriptor, 17, nil)
            var glyphs = [CGGlyph](repeating: 0, count: characters.count)
            let resolved = characters.withUnsafeBufferPointer { characterBuffer in
                glyphs.withUnsafeMutableBufferPointer { glyphBuffer in
                    CTFontGetGlyphsForCharacters(
                        font,
                        characterBuffer.baseAddress!,
                        glyphBuffer.baseAddress!,
                        characterBuffer.count
                    )
                }
            }

            XCTAssertTrue(resolved, asset.filename)
            XCTAssertFalse(glyphs.contains(0), "Missing glyph in \(asset.filename)")
        }
    }

    private func fontURL(for asset: SETFontAsset) -> URL? {
        let bundles = [Bundle.main, Bundle(for: SETFontGlyphCoverageTests.self)] + Bundle.allBundles
        for bundle in bundles {
            if let url = bundle.url(forResource: asset.filename.replacingOccurrences(of: ".ttf", with: ""), withExtension: "ttf") {
                return url
            }
        }
        return nil
    }
}
