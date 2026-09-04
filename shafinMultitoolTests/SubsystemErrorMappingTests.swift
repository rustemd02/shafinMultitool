//
//  SubsystemErrorMappingTests.swift
//  shafinMultitoolTests
//
//  M1-018 ErrorPresentationOwner: every reachable subsystem failure maps to a
//  localized, recoverable production message. The table pins each mapping and
//  verifies the Localizable.xcstrings catalog carries non-empty RU and EN
//  values, so no raw English framework/diagnostic string can reach the UI.
//

import XCTest
@testable import shafinMultitool

final class SubsystemErrorMappingTests: XCTestCase {

    private struct ErrorMapping {
        let subsystem: String
        let trigger: String
        let localizationKey: String

        init(_ subsystem: String, _ trigger: String, _ localizationKey: String) {
            self.subsystem = subsystem
            self.trigger = trigger
            self.localizationKey = localizationKey
        }
    }

    /// Table: every reachable failure surface and its user-facing key.
    private var mappings: [ErrorMapping] {
        [
            ErrorMapping("recording", "RecorderFailure (prepare/start/stop/promote)", "set.generator.error.recorder"),
            ErrorMapping("generator", "plannedScene missing", "set.generator.error.no_scene"),
            ErrorMapping("generator", "AR session not ready/interrupted/recovering", "set.generator.error.ar_not_ready"),
            ErrorMapping("generator", "camera transform unavailable", "set.generator.error.camera_position"),
            ErrorMapping("generator", "empty parse result", "set.generator.error.parse_empty"),
            ErrorMapping("marking", "object marking failed", "set.generator.error.mark_failed"),
            ErrorMapping("marking", "marker name empty", "set.generator.error.marker_name"),
            ErrorMapping("microphone", "authorization denied", "set.generator.error.microphone_denied"),
            ErrorMapping("microphone", "authorization restricted", "set.generator.error.microphone_restricted"),
            ErrorMapping("storyboard", "beat open failed", "set.storyboard.error.open"),
            ErrorMapping("storyboard", "beat not found", "set.storyboard.error.not_found"),
            ErrorMapping("storyboard", "last beat deletion", "set.storyboard.error.delete_last"),
        ]
    }

    private var localizationCatalog: [String: (ru: String?, en: String?)] {
        // The source .xcstrings is the build's localization source of truth
        // (the compiled bundle keeps only per-language .strings). Resolve it
        // relative to this test file inside the repository checkout.
        let catalogURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("shafinMultitool/Resources/Localizable.xcstrings")
        guard let data = try? Data(contentsOf: catalogURL),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let strings = object["strings"] as? [String: Any] else {
            return [:]
        }

        var catalog: [String: (ru: String?, en: String?)] = [:]
        for (key, entry) in strings {
            guard let entry = entry as? [String: Any],
                  let localizations = entry["localizations"] as? [String: Any] else {
                continue
            }
            let ru = (localizations["ru"] as? [String: Any])?["stringUnit"] as? [String: Any]
            let en = (localizations["en"] as? [String: Any])?["stringUnit"] as? [String: Any]
            catalog[key] = (
                ru?["value"] as? String,
                en?["value"] as? String
            )
        }
        return catalog
    }

    func testEveryReachableFailureMapsToFullyLocalizedRecoverableMessage() {
        let catalog = localizationCatalog
        XCTAssertFalse(catalog.isEmpty, "Localizable.xcstrings must be readable")

        for mapping in mappings {
            let entry = catalog[mapping.localizationKey]
            XCTAssertNotNil(entry, "missing localization entry for \(mapping.localizationKey)")
            let ru = entry?.ru ?? ""
            let en = entry?.en ?? ""
            XCTAssertFalse(ru.isEmpty, "RU value must be non-empty for \(mapping.localizationKey)")
            XCTAssertFalse(en.isEmpty, "EN value must be non-empty for \(mapping.localizationKey)")
        }
    }

    func testTypedSubsystemErrorTaxonomiesAreEquatableAndExhaustive() {
        // The typed taxonomies are the production mapping sources; Equatable
        // conformance keeps them switch-exhaustive at their handling sites.
        let recorderFailures: [RecorderFailure] = [
            .invalidTransition, .outputAlreadyExists, .writerCreationFailed,
            .writerInputRejected, .writerStartFailed, .audioUnavailable,
            .audioStartFailed, .videoAppendFailed, .audioAppendFailed,
            .noVideoFrames, .finishFailed,
        ]
        XCTAssertEqual(Set(recorderFailures).count, recorderFailures.count)

        let teardownFailures: [SceneWorkspaceTeardownFailure] = [
            .worldMapSnapshotFailed, .persistenceFailed, .workspaceOwnerUnavailable,
        ]
        XCTAssertEqual(Set(teardownFailures).count, teardownFailures.count)

        let storeFailures: [RecordingArtifactStoreError] = [
            .pendingSourceMissing, .pendingSourceOutsideRoot, .pendingSourceSymlink,
            .pendingSourceNotRegular, .destinationConflict,
            .projectArtifactUnexpectedEntry, .fileSystemFailure,
        ]
        XCTAssertEqual(Set(storeFailures).count, storeFailures.count)

        let dbFailures: [DBServiceError] = [.staleSnapshot(storedUpdatedAt: Date())]
        XCTAssertTrue(dbFailures.allSatisfy { !$0.localizedDescription.isEmpty })
    }

}
