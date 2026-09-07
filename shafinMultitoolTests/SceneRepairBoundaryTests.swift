//
//  SceneRepairBoundaryTests.swift
//  shafinMultitoolTests
//
//  M5-027: safe-vs-forbidden repair fixtures. The registry must cover
//  every repair note the production pipeline/compiler can emit
//  (grep-audited); forbidden repairs route to clarification, never to
//  silent application.
//

import XCTest
@testable import shafinMultitool

final class SceneRepairBoundaryTests: XCTestCase {
    func testRegistryHasNoForbiddenRepairsToday() {
        XCTAssertTrue(
            SceneRepairBoundary.forbiddenCodes.isEmpty,
            "forbidden repairs must route to clarification, not ship silently"
        )
    }

    func testRegistryCoversAllProductionNoteCodes() {
        let productionCodes = SceneRepairBoundaryTests.productionNoteCodes()
        let unregistered = productionCodes.subtracting(SceneRepairBoundary.registeredCodes)
        XCTAssertTrue(
            unregistered.isEmpty,
            "unregistered repair notes in production: \(unregistered.sorted())"
        )
    }

    func testSafeRepairsPreserveMeaning() {
        // Spot-check the two compiler downgrades: actor/beat structure
        // survives, only the unresolvable part changes with a note.
        let compiler = ScenePlanCompiler()
        let plan = ScenePlanIR(
            actors: [.init(ref: "first", type: .human)],
            objects: [],
            beats: [.init(ref: "beat_1", actions: [
                .init(actorRef: "first", type: .give, targetRef: "object_ghost")
            ])],
            spatialRelations: [],
            referenceBindings: .init(actorBindings: ["first": "actor_1"])
        )
        guard let compiled = try? compiler.compileWithNotes(plan: plan, originalDescription: "demo") else {
            return XCTFail("expected compilation with downgrade note")
        }
        XCTAssertEqual(compiled.script.beats.count, 1)
        XCTAssertEqual(compiled.script.actors.map(\.id), ["actor_1"])
        XCTAssertTrue(compiled.notes.contains("v8.targetless_action_downgraded"))
    }

    func testValidatorRejectsWhatRepairMustNotFix() {
        // A dangling target is a validation failure (M5-026), not a
        // silent repair: the repair boundary never invents the target.
        let script = SceneScript(
            actors: [SceneActor(id: "actor_1", type: .human)],
            objects: [],
            beats: [SceneBeat(id: "beat_1", actions: [SceneAction(
                id: "action_1",
                actorId: "actor_1",
                type: .give,
                target: "object_ghost"
            )])],
            spatialRelations: [],
            originalDescription: "demo"
        )
        XCTAssertTrue(
            SceneResponseValidator.validate(script: script).contains(.danglingActionTarget)
        )
    }

    // MARK: - Audit helper

    /// Grep-equivalent over the production repair-note vocabulary: every
    /// v8/v9 note literal appended to reason/compile notes in the Scene
    /// pipeline/compiler sources must be registered in the boundary.
    /// Implemented as source scan so a new repair without a registry
    /// entry fails this test. Non-note literals (e.g. filename checks
    /// like "v9.3") are excluded by requiring a note-append context.
    static func productionNoteCodes() -> Set<String> {
        let thisFile = URL(fileURLWithPath: #filePath)
        let moduleDir = thisFile
            .deletingLastPathComponent() // shafinMultitoolTests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("shafinMultitool/SceneGeneratorModule")
        var codes = Set<String>()
        let literalPattern = try! NSRegularExpression(pattern: #""(v[89]\.[a-z_0-9]+)(?::[a-z_0-9]+)?""#)
        let constPattern = try! NSRegularExpression(pattern: #"(?:Code|Codes)\b"#)
        let enumerator = FileManager.default.enumerator(at: moduleDir, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            guard file.pathExtension == "swift" else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for line in text.components(separatedBy: "\n") {
                let lower = line.lowercased()
                let isNoteContext = lower.contains("reasoncode")
                    || lower.contains("compile") && lower.contains("note")
                    || lower.contains("appendnote")
                    || lower.contains("appendreason")
                    || lower.contains("reason")
                    || constPattern.firstMatch(
                        in: line,
                        range: NSRange(line.startIndex..., in: line)
                    ) != nil
                guard isNoteContext else { continue }
                let range = NSRange(line.startIndex..., in: line)
                for match in literalPattern.matches(in: line, range: range) {
                    if let codeRange = Range(match.range(at: 1), in: line) {
                        codes.insert(String(line[codeRange]))
                    }
                }
            }
        }
        // v8 compiler notes travel through named constants
        // (targetlessActionDowngradedCode /
        // invalidSpatialRelationSkippedCode); both are registered.
        codes.insert("v8.targetless_action_downgraded")
        codes.insert("v8.invalid_spatial_relation_skipped")
        return codes
    }
}
