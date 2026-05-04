//
//  SceneV8PipelineTests.swift
//  shafinMultitoolTests
//
//  Created on 21.04.2026.
//

import XCTest
@testable import shafinMultitool

final class SceneV8PipelineTests: XCTestCase {
    private static let liveModelOverrideKey = "scene_generator_llm_model_path"
    private static let liveDatasetSmokeFlagKey = "SG_RUN_LIVE_MODEL_DATASET_SMOKE"
    private static let liveModelSmokeFlagKey = "SG_RUN_LIVE_MODEL_SMOKE"
    private static let liveDatasetSmokeSentinelPath = "/tmp/scene_live_dataset_smoke.enabled"
    private static let liveModelSmokeSentinelPath = "/tmp/scene_live_model_smoke.enabled"

    private struct LiveDatasetRecord: Decodable {
        struct GraphConstraints: Decodable {
            struct MarkedObjectConstraint: Decodable {
                let allowedAliases: [String]
                let canonicalName: String
                let id: String

                enum CodingKeys: String, CodingKey {
                    case allowedAliases = "allowed_aliases"
                    case canonicalName = "canonical_name"
                    case id
                }
            }

            let markedObjects: [MarkedObjectConstraint]
            let ordinalBindings: [String: String]
            let sameTypeMarkerConflict: Bool
            let targetObjectID: String?

            enum CodingKeys: String, CodingKey {
                case markedObjects = "marked_objects"
                case ordinalBindings = "ordinal_bindings"
                case sameTypeMarkerConflict = "same_type_marker_conflict"
                case targetObjectID = "target_object_id"
            }
        }

        struct ValidationReport: Decodable {
            let criticVerdict: String?
            let criticDetectedFailures: [String]

            enum CodingKeys: String, CodingKey {
                case criticVerdict = "critic_verdict"
                case criticDetectedFailures = "critic_detected_failures"
            }
        }

        let patternName: String
        let difficultyBucket: String
        let sampleID: String
        let sourceText: String
        let graphConstraints: GraphConstraints
        let validationReport: ValidationReport?

        enum CodingKeys: String, CodingKey {
            case patternName = "pattern_name"
            case difficultyBucket = "difficulty_bucket"
            case sampleID = "sample_id"
            case sourceText = "source_text"
            case graphConstraints = "graph_constraints"
            case validationReport = "validation_report"
        }
    }

    private struct LivePatternExpectation {
        let actorFloor: Int
        let requiresDialogue: Bool
        let requiredActionTypes: [SceneAction.ActionType]
        let markedObjectFloor: Int
        let expectsSameTypeConflict: Bool
    }

    private struct LiveDatasetEvaluation {
        let record: LiveDatasetRecord
        let hardIssues: [String]
        let softIssues: [String]
        let actorCount: Int
        let beatCount: Int
        let actionCount: Int
        let confidence: Float
        let route: SceneRouterOutcome?
        let reasonCodes: [String]
        let matchedMarkedCount: Int

        var passed: Bool {
            hardIssues.isEmpty
        }
    }

    private struct SeededGenerator {
        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
        }

        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }

        mutating func nextInt(upperBound: Int) -> Int {
            guard upperBound > 0 else { return 0 }
            return Int(next() % UInt64(upperBound))
        }
    }

    private final class StubLocalProvider: LocalScenePlanProvider {
        let result: ScenePlanProviderResult?

        init(result: ScenePlanProviderResult?) {
            self.result = result
        }

        func generatePlan(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?
        ) -> ScenePlanProviderResult? {
            result
        }

        func generatePlanAsync(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?
        ) async -> ScenePlanProviderResult? {
            result
        }
    }

    private final class StubRemoteProvider: RemoteScenePlanProvider {
        let result: ScenePlanProviderResult?

        init(result: ScenePlanProviderResult?) {
            self.result = result
        }

        func generateRemotePlan(
            description: String,
            markedObjects: [MarkedObject],
            anchors: SourceAnchorBundle,
            state: SceneChunkState?
        ) async -> ScenePlanProviderResult? {
            result
        }
    }

    private func makeChunkAnchors(
        phaseCues: [String] = [],
        mentionedMarkedObjects: [String] = []
    ) -> SceneChunkAnchor {
        SceneChunkAnchor(
            sourceBundle: SourceAnchorBundle(
                actorCountHint: 2,
                ordinalMentions: ["first", "second"],
                mentionedMarkedObjects: mentionedMarkedObjects,
                objectSurfaceMentions: [],
                phaseCues: phaseCues,
                unsupportedActionFlags: [],
                sameTypeMarkerConflict: false,
                lowConfidenceFlags: []
            ),
            speakerCues: [],
            actorMentions: [],
            objectMentions: [],
            markedObjectMentions: mentionedMarkedObjects,
            pronounMentions: [],
            chronologyCues: [],
            locationCues: [],
            timeCues: [],
            uncertaintyFlags: []
        )
    }

    private func makeExistingStitchState(
        actorRefs: [String] = ["actor_1", "actor_2"],
        objects: [ScenePlanIR.Object] = []
    ) -> SceneStitchState {
        let actors = actorRefs.map { ScenePlanIR.Actor(ref: $0, type: .human) }
        let objectAliasMap = Dictionary(uniqueKeysWithValues: objects.compactMap { object in
            object.name.map { ($0.lowercased(), object.ref) }
        })
        let registry = SceneEntityRegistrySnapshot(
            actors: actors,
            objects: objects,
            actorAliasMap: [:],
            objectAliasMap: objectAliasMap,
            speakerAliasMap: [:],
            unresolvedMentions: [],
            lastResolvedSpeaker: nil,
            locationName: nil,
            actorPoses: [:],
            heldObjects: [:]
        )

        return SceneStitchState(
            sceneID: "scene_1",
            sceneIndex: 0,
            sourceText: "",
            metadata: .empty,
            registry: registry,
            actors: actors,
            objects: objects
        )
    }

    private func datasetWorkspaceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func configString(_ key: String) -> String? {
        let env = ProcessInfo.processInfo.environment
        if let value = env[key], !value.isEmpty {
            return value
        }
        if let value = env["SIMCTL_CHILD_\(key)"], !value.isEmpty {
            return value
        }
        if let value = UserDefaults.standard.string(forKey: key), !value.isEmpty {
            return value
        }
        return nil
    }

    private func configBool(_ key: String) -> Bool {
        if let value = configString(key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "y", "on":
                return true
            default:
                return false
            }
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.bool(forKey: key)
        }
        return false
    }

    private func sentinelEnabled(for path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private func configInt(_ key: String, default defaultValue: Int) -> Int {
        if let value = configString(key), let parsed = Int(value) {
            return parsed
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            let value = UserDefaults.standard.integer(forKey: key)
            if value != 0 {
                return value
            }
        }
        return defaultValue
    }

    private func configUInt64(_ key: String, default defaultValue: UInt64) -> UInt64 {
        if let value = configString(key), let parsed = UInt64(value) {
            return parsed
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            let value = UserDefaults.standard.integer(forKey: key)
            if value > 0 {
                return UInt64(value)
            }
        }
        return defaultValue
    }

    private func configDouble(_ key: String, default defaultValue: Double) -> Double {
        if let value = configString(key), let parsed = Double(value) {
            return parsed
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            return UserDefaults.standard.double(forKey: key)
        }
        return defaultValue
    }

    private func resolveLiveModelPath() -> String? {
        if let explicit = configString("SG_LIVE_MODEL_PATH"),
           !explicit.isEmpty,
           FileManager.default.fileExists(atPath: explicit) {
            return explicit
        }

        let root = datasetWorkspaceRoot()
        let candidates = [
            root.appendingPathComponent("shafinMultitool/Resources/Models/dataset_v9_event_sft_q4_k_m.gguf").path,
            root.appendingPathComponent("shafinMultitool/SceneGeneratorModule/Models/dataset_v8_plan_orpo_iter1_q4_k_m.gguf").path,
            root.appendingPathComponent("shafinMultitool/Resources/Models/qwen2.5-1.5b-instruct.Q4_K_M.gguf").path,
        ]

        return candidates.first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private func loadAcceptedSourceRecords(relativePath: String) throws -> [LiveDatasetRecord] {
        let url = datasetWorkspaceRoot().appendingPathComponent(relativePath)
        let contents = try String(contentsOf: url, encoding: .utf8)
        let decoder = JSONDecoder()
        return try contents
            .split(whereSeparator: \.isNewline)
            .map { line in
                try decoder.decode(LiveDatasetRecord.self, from: Data(line.utf8))
            }
    }

    private func livePatternExpectation(for patternName: String, record: LiveDatasetRecord) -> LivePatternExpectation? {
        switch patternName {
        case "dialogue_only":
            return LivePatternExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 2),
                requiresDialogue: true,
                requiredActionTypes: [],
                markedObjectFloor: 0,
                expectsSameTypeConflict: false
            )
        case "dialogue_then_put_down_object":
            return LivePatternExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 2),
                requiresDialogue: true,
                requiredActionTypes: [.putDown],
                markedObjectFloor: 0,
                expectsSameTypeConflict: false
            )
        case "dialogue_then_pick_up_object_then_give_to_third_actor":
            return LivePatternExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 3),
                requiresDialogue: true,
                requiredActionTypes: [.pickUp, .give],
                markedObjectFloor: 0,
                expectsSameTypeConflict: false
            )
        case "ordinal_first_second_third":
            return LivePatternExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 3),
                requiresDialogue: false,
                requiredActionTypes: [],
                markedObjectFloor: 0,
                expectsSameTypeConflict: false
            )
        case "toward_each_other_then_pass_by_marked_object":
            return LivePatternExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 2),
                requiresDialogue: false,
                requiredActionTypes: [.passBy],
                markedObjectFloor: min(1, record.graphConstraints.markedObjects.count),
                expectsSameTypeConflict: false
            )
        case "same_type_two_marked_objects":
            return LivePatternExpectation(
                actorFloor: max(record.graphConstraints.ordinalBindings.count, 2),
                requiresDialogue: false,
                requiredActionTypes: [],
                markedObjectFloor: record.graphConstraints.markedObjects.count,
                expectsSameTypeConflict: record.graphConstraints.sameTypeMarkerConflict
            )
        default:
            return nil
        }
    }

    private func makeMarkedObjects(from record: LiveDatasetRecord) -> [MarkedObject] {
        record.graphConstraints.markedObjects.enumerated().map { index, marker in
            MarkedObject(
                name: marker.canonicalName,
                position: Position3D(x: Float(index), y: 0, z: Float(-index))
            )
        }
    }

    private func sampledLiveDatasetRecords(
        seed: UInt64,
        caseLimit: Int,
        patternFilter: Set<String>?
    ) throws -> [LiveDatasetRecord] {
        let core = try loadAcceptedSourceRecords(relativePath: "docs/SGv7pipeline/runs/sgv7_full_20260417/core/accepted_source.jsonl")
        let hard = try loadAcceptedSourceRecords(relativePath: "docs/SGv7pipeline/runs/sgv7_full_20260417/hard/accepted_source.jsonl")
        let selectedPatterns = [
            "dialogue_only",
            "dialogue_then_put_down_object",
            "dialogue_then_pick_up_object_then_give_to_third_actor",
            "ordinal_first_second_third",
            "toward_each_other_then_pass_by_marked_object",
            "same_type_two_marked_objects",
        ]
        let preferredOrder: [String: Int] = [
            "dialogue_then_pick_up_object_then_give_to_third_actor": 0,
            "dialogue_then_put_down_object": 1,
            "same_type_two_marked_objects": 2,
            "toward_each_other_then_pass_by_marked_object": 3,
            "ordinal_first_second_third": 4,
            "dialogue_only": 5,
        ]

        var grouped: [String: [LiveDatasetRecord]] = [:]
        for record in core + hard {
            guard selectedPatterns.contains(record.patternName) else { continue }
            if let patternFilter, !patternFilter.contains(record.patternName) { continue }
            grouped[record.patternName, default: []].append(record)
        }

        var generator = SeededGenerator(seed: seed)
        let orderedPatterns = selectedPatterns.sorted {
            preferredOrder[$0, default: .max] < preferredOrder[$1, default: .max]
        }

        var sampled: [LiveDatasetRecord] = []
        var seenSampleIDs = Set<String>()
        let quotaPerPattern = max(1, caseLimit / max(1, orderedPatterns.count))

        for pattern in orderedPatterns {
            guard var pool = grouped[pattern], !pool.isEmpty else { continue }
            var pickedForPattern = 0

            while !pool.isEmpty && pickedForPattern < quotaPerPattern && sampled.count < caseLimit {
                let index = generator.nextInt(upperBound: pool.count)
                let candidate = pool.remove(at: index)
                guard seenSampleIDs.insert(candidate.sampleID).inserted else { continue }
                sampled.append(candidate)
                pickedForPattern += 1
            }
        }

        if sampled.count < caseLimit {
            var remaining = grouped.values.flatMap { $0 }.filter { !seenSampleIDs.contains($0.sampleID) }
            while !remaining.isEmpty && sampled.count < caseLimit {
                let index = generator.nextInt(upperBound: remaining.count)
                let candidate = remaining.remove(at: index)
                guard seenSampleIDs.insert(candidate.sampleID).inserted else { continue }
                sampled.append(candidate)
            }
        }

        return sampled
    }

    private func loadingStateDescription(_ state: LLMParserService.LoadingState) -> String {
        switch state {
        case .notLoaded:
            return "not_loaded"
        case .loading:
            return "loading"
        case .loaded:
            return "loaded"
        case .failed(let reason):
            return "failed(\(reason))"
        }
    }

    private func evaluateLiveDatasetCase(
        record: LiveDatasetRecord,
        result: SceneBundleParsingResult,
        trace: SceneRuntimeTrace?
    ) -> LiveDatasetEvaluation {
        let expectation = livePatternExpectation(for: record.patternName, record: record)
        let activeScene = result.activeSceneScript
        let actions = activeScene?.actions ?? []
        let matchedMarkedCount = Set(result.diagnostics.matchedMarkedObjects).count
        var hardIssues: [String] = []
        var softIssues: [String] = []

        if activeScene == nil {
            hardIssues.append("missing_active_scene")
        }

        if let activeScene {
            if activeScene.beats.isEmpty {
                hardIssues.append("empty_beats")
            }
            if result.chunkDiagnostics.contains(where: \.usedFallbackPlanner) {
                hardIssues.append("fallback_planner_used")
            }
            if let expectation {
                if activeScene.actors.count < expectation.actorFloor {
                    hardIssues.append("actor_floor_\(activeScene.actors.count)_of_\(expectation.actorFloor)")
                }
                if expectation.requiresDialogue {
                    let hasDialogue = actions.contains { action in
                        action.type == .talk || !(action.dialogue ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    if !hasDialogue {
                        hardIssues.append("missing_dialogue")
                    }
                }
                for requiredAction in expectation.requiredActionTypes where !actions.contains(where: { $0.type == requiredAction }) {
                    hardIssues.append("missing_action_\(requiredAction.rawValue)")
                }
                if matchedMarkedCount < expectation.markedObjectFloor {
                    hardIssues.append("matched_marked_objects_\(matchedMarkedCount)_of_\(expectation.markedObjectFloor)")
                }
                if expectation.expectsSameTypeConflict {
                    let detectedConflict = result.chunkDiagnostics.contains { $0.anchors.sourceBundle.sameTypeMarkerConflict }
                    if !detectedConflict {
                        softIssues.append("same_type_conflict_not_detected")
                    }
                }
            }
        }

        if result.diagnostics.confidence < 0.6 {
            softIssues.append("low_confidence_\(String(format: "%.2f", result.diagnostics.confidence))")
        }
        if let verdict = record.validationReport?.criticVerdict, verdict != "pass" {
            softIssues.append("dataset_critic_\(verdict)")
        }
        for failure in record.validationReport?.criticDetectedFailures ?? [] {
            softIssues.append("dataset_flag_\(failure)")
        }

        return LiveDatasetEvaluation(
            record: record,
            hardIssues: hardIssues,
            softIssues: softIssues,
            actorCount: activeScene?.actors.count ?? 0,
            beatCount: activeScene?.beats.count ?? 0,
            actionCount: actions.count,
            confidence: result.diagnostics.confidence,
            route: trace?.route,
            reasonCodes: trace?.reasons ?? [],
            matchedMarkedCount: matchedMarkedCount
        )
    }

    private func liveDatasetSummary(
        evaluations: [LiveDatasetEvaluation],
        seed: UInt64
    ) -> String {
        let total = evaluations.count
        let passed = evaluations.filter(\.passed).count
        let passRate = total > 0 ? Double(passed) / Double(total) : 0

        var lines: [String] = []
        lines.append("LIVE DATASET SMOKE SUMMARY seed=\(seed) passed=\(passed)/\(total) passRate=\(String(format: "%.2f", passRate))")

        let byPattern = Dictionary(grouping: evaluations, by: { $0.record.patternName })
        for pattern in byPattern.keys.sorted() {
            let items = byPattern[pattern] ?? []
            let patternPassed = items.filter(\.passed).count
            let patternRate = Double(patternPassed) / Double(max(items.count, 1))
            let dominantIssues = Dictionary(grouping: items.flatMap(\.hardIssues), by: { $0 })
                .mapValues(\.count)
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.key < rhs.key
                    }
                    return lhs.value > rhs.value
                }
                .prefix(3)
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: ", ")
            lines.append("PATTERN \(pattern) passed=\(patternPassed)/\(items.count) rate=\(String(format: "%.2f", patternRate)) issues=[\(dominantIssues)]")
        }

        for evaluation in evaluations {
            let status = evaluation.passed ? "PASS" : "FAIL"
            let issues = (evaluation.hardIssues + evaluation.softIssues).joined(separator: ",")
            lines.append(
                "\(status) [\(evaluation.record.patternName)] \(evaluation.record.sampleID) actors=\(evaluation.actorCount) beats=\(evaluation.beatCount) actions=\(evaluation.actionCount) matchedMarkers=\(evaluation.matchedMarkedCount) confidence=\(String(format: "%.2f", evaluation.confidence)) route=\(evaluation.route?.rawValue ?? "nil") issues=[\(issues)] reasons=[\(evaluation.reasonCodes.joined(separator: ","))] text=\(evaluation.record.sourceText)"
            )
        }

        return lines.joined(separator: "\n")
    }

    func testCompilerPreservesMarkedObjectIdentityAndSymbolicActors() throws {
        let compiler = ScenePlanCompiler()
        let plan = ScenePlanIR(
            actors: [
                .init(ref: "first", type: .human),
                .init(ref: "second", type: .human),
            ],
            objects: [
                .init(ref: "object_marked_deadbeef", type: .table, relativePosition: .center, markedObjectID: "object_marked_deadbeef"),
                .init(ref: "object_slot_1", type: .chair, relativePosition: .left),
            ],
            beats: [
                .init(
                    ref: "beat_1",
                    phase: "approach_object",
                    actions: [
                        .init(actorRef: "first", type: .approach, targetRef: "object_marked_deadbeef", resultingPose: .walking),
                        .init(actorRef: "second", type: .stand, targetRef: "object_slot_1", resultingPose: .standing),
                    ]
                )
            ],
            spatialRelations: [],
            referenceBindings: .init(
                actorBindings: ["first": "actor_1", "second": "actor_2"],
                markedObjectIDs: ["object_marked_deadbeef"],
                aliasToObjectRef: ["стол": "object_marked_deadbeef"]
            )
        )

        let script = try compiler.compile(plan: plan, originalDescription: "demo")
        XCTAssertEqual(script.actors.map(\.id), ["actor_1", "actor_2"])
        XCTAssertEqual(script.objects.map(\.id), ["object_marked_deadbeef", "object_1"])
        XCTAssertEqual(script.beats.first?.actions.first?.target, "object_marked_deadbeef")
    }

    func testCanonicalizerExpandsCollectiveTowardEachOtherBeatForBothActors() throws {
        let canonicalizer = ChunkCanonicalizer()
        let draft = SceneChunkDraft(
            sceneID: "scene_1",
            chunkID: "scene_1_chunk_1",
            chunkIndex: 0,
            sourceText: "2 актёра идут навстречу друг другу",
            sourceRange: .init(start: 0, end: 36),
            anchors: makeChunkAnchors(phaseCues: ["navstrechu"]),
            registrySnapshot: .empty,
            plan: ScenePlanIR(
                actors: [
                    .init(ref: "first", type: .human),
                    .init(ref: "second", type: .human),
                ],
                objects: [],
                beats: [
                    .init(
                        ref: "beat_1",
                        phase: "navstrechu",
                        actions: [
                            .init(
                                actorRef: "first",
                                type: .walk,
                                resultingPose: .walking,
                                sourceText: "идёт навстречу другому актёру"
                            ),
                        ]
                    ),
                ],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1", "second": "actor_2"])
            ),
            usedFallbackPlanner: false,
            usedLegacyPlanBridge: false,
            confidence: 0.9,
            unresolvedMentions: [],
            reasonCodes: ["v1.local_chunk_plan"]
        )

        let chunk = canonicalizer.canonicalize(
            draft: draft,
            stitchState: makeExistingStitchState()
        )

        let beat = try XCTUnwrap(chunk.beatPatch.first)
        XCTAssertEqual(beat.actions.count, 2)

        let actor1 = try XCTUnwrap(beat.actions.first(where: { $0.actorRef == "actor_1" }))
        XCTAssertEqual(actor1.direction, .towardEachOther)
        XCTAssertEqual(actor1.targetRef, "actor_2")

        let actor2 = try XCTUnwrap(beat.actions.first(where: { $0.actorRef == "actor_2" }))
        XCTAssertEqual(actor2.direction, .towardEachOther)
        XCTAssertEqual(actor2.targetRef, "actor_1")

        XCTAssertTrue(chunk.reasonCodes.contains("v1.collective_toward_each_other_expanded"))
    }

    func testCanonicalizerPreservesObjectTargetInsideCollectiveChunk() throws {
        let canonicalizer = ChunkCanonicalizer()
        let objectRef = "object_marked_computer"
        let object = ScenePlanIR.Object(
            ref: objectRef,
            type: .generic,
            relativePosition: .center,
            name: "компьютер",
            markedObjectID: objectRef
        )
        let draft = SceneChunkDraft(
            sceneID: "scene_1",
            chunkID: "scene_1_chunk_1",
            chunkIndex: 0,
            sourceText: "2 актёра идут навстречу друг другу, потом идут к компьютеру",
            sourceRange: .init(start: 0, end: 61),
            anchors: makeChunkAnchors(phaseCues: ["navstrechu"], mentionedMarkedObjects: [objectRef]),
            registrySnapshot: .empty,
            plan: ScenePlanIR(
                actors: [
                    .init(ref: "first", type: .human),
                    .init(ref: "second", type: .human),
                ],
                objects: [object],
                beats: [
                    .init(
                        ref: "beat_1",
                        phase: "sequence",
                        actions: [
                            .init(
                                actorRef: "second",
                                type: .walk,
                                resultingPose: .walking,
                                sourceText: "идёт к компьютеру"
                            ),
                            .init(
                                actorRef: "first",
                                type: .walk,
                                resultingPose: .walking,
                                sourceText: "идёт навстречу другому"
                            ),
                        ]
                    ),
                ],
                spatialRelations: [],
                referenceBindings: .init(
                    actorBindings: ["first": "actor_1", "second": "actor_2"],
                    markedObjectIDs: [objectRef],
                    aliasToObjectRef: ["компьютер": objectRef]
                )
            ),
            usedFallbackPlanner: false,
            usedLegacyPlanBridge: false,
            confidence: 0.9,
            unresolvedMentions: [],
            reasonCodes: ["v1.local_chunk_plan"]
        )

        let chunk = canonicalizer.canonicalize(
            draft: draft,
            stitchState: makeExistingStitchState(objects: [object])
        )

        let beat = try XCTUnwrap(chunk.beatPatch.first)
        XCTAssertEqual(beat.actions.count, 2)

        let actor1 = try XCTUnwrap(beat.actions.first(where: { $0.actorRef == "actor_1" }))
        XCTAssertEqual(actor1.type, .approach)
        XCTAssertEqual(actor1.targetRef, objectRef)
        XCTAssertEqual(actor1.direction, .toTarget)

        let actor2 = try XCTUnwrap(beat.actions.first(where: { $0.actorRef == "actor_2" }))
        XCTAssertEqual(actor2.targetRef, objectRef)
        XCTAssertEqual(actor2.direction, .toTarget)

        XCTAssertTrue(chunk.reasonCodes.contains("v1.object_target_preserved"))
        XCTAssertTrue(chunk.reasonCodes.contains("v1.collective_object_motion_hotfix_v2"))
    }

    func testCompilerDowngradesTargetlessRequiredActionAndEmitsNote() throws {
        let compiler = ScenePlanCompiler()
        let plan = ScenePlanIR(
            actors: [.init(ref: "first", type: .human)],
            objects: [],
            beats: [
                .init(
                    ref: "beat_1",
                    actions: [
                        .init(actorRef: "first", type: .approach),
                    ]
                ),
            ],
            spatialRelations: [],
            referenceBindings: .init(actorBindings: ["first": "actor_1"])
        )

        let compiled = try compiler.compileWithNotes(plan: plan, originalDescription: "demo")
        XCTAssertEqual(compiled.script.beats.first?.actions.first?.type, .stand)
        XCTAssertNil(compiled.script.beats.first?.actions.first?.target)
        XCTAssertTrue(compiled.notes.contains("v8.targetless_action_downgraded"))
    }

    func testCompilerSkipsInvalidSpatialRelationAndEmitsNote() throws {
        let compiler = ScenePlanCompiler()
        let plan = ScenePlanIR(
            actors: [.init(ref: "first", type: .human)],
            objects: [.init(ref: "object_slot_1", type: .table, relativePosition: .center)],
            beats: [
                .init(
                    ref: "beat_1",
                    actions: [.init(actorRef: "first", type: .stand)]
                ),
            ],
            spatialRelations: [
                .init(ref: "rel_1", subjectRef: "object_slot_1", relation: .inside, objectRef: "holding_object_1"),
            ],
            referenceBindings: .init(actorBindings: ["first": "actor_1"])
        )

        let compiled = try compiler.compileWithNotes(plan: plan, originalDescription: "demo")
        XCTAssertEqual(compiled.script.spatialRelations.count, 0)
        XCTAssertTrue(compiled.notes.contains("v8.invalid_spatial_relation_skipped"))
    }

    func testQualityGateRejectsUnresolvedMarkedObject() {
        let gate = SceneQualityGate()
        let anchors = SourceAnchorBundle(
            actorCountHint: 2,
            ordinalMentions: ["first", "second"],
            mentionedMarkedObjects: ["object_marked_deadbeef"],
            objectSurfaceMentions: ["стол"],
            phaseCues: ["approach_object"],
            unsupportedActionFlags: [],
            sameTypeMarkerConflict: false,
            lowConfidenceFlags: []
        )
        let providerResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human), .init(ref: "second", type: .human)],
                objects: [.init(ref: "object_slot_1", type: .table, relativePosition: .center)],
                beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .approach, targetRef: "object_slot_1")])],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1", "second": "actor_2"], markedObjectIDs: [], aliasToObjectRef: [:])
            ),
            usedLegacySceneScriptBridge: false
        )

        let trace = gate.decide(anchors: anchors, providerResult: providerResult, compiledScript: nil, remoteEnabled: false)
        XCTAssertEqual(trace.route, .fallbackRuleOnly)
        XCTAssertTrue(trace.reasons.contains("unresolved_marked_object"))
    }

    func testAnchorExtractorFlagsSameTypeMarkerConflict() {
        let extractor = SceneAnchorExtractor()
        let markers = [
            MarkedObject(name: "левый стул", position: .init(x: 0, y: 0, z: 0)),
            MarkedObject(name: "правый стул", position: .init(x: 1, y: 0, z: 0)),
        ]

        let anchors = extractor.extract(
            description: "Первый подходит к левому стулу, второй стоит у правого стула",
            markedObjects: markers
        )

        XCTAssertTrue(anchors.sameTypeMarkerConflict)
        XCTAssertTrue(anchors.ordinalMentions.contains("first"))
        XCTAssertTrue(anchors.ordinalMentions.contains("second"))
    }

    func testQualityGatePrefersClarificationForAmbiguity() {
        let gate = SceneQualityGate()
        let anchors = SourceAnchorBundle(
            actorCountHint: 1,
            ordinalMentions: ["first", "second"],
            mentionedMarkedObjects: [],
            objectSurfaceMentions: ["стул"],
            phaseCues: [],
            unsupportedActionFlags: [],
            sameTypeMarkerConflict: true,
            lowConfidenceFlags: ["ordinal_actor_count_mismatch"]
        )
        let providerResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [.init(ref: "object_slot_1", type: .chair, relativePosition: .left)],
                beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .stand, targetRef: "object_slot_1")])],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1"])
            ),
            usedLegacySceneScriptBridge: false
        )

        let trace = gate.decide(anchors: anchors, providerResult: providerResult, compiledScript: nil, remoteEnabled: false)
        XCTAssertEqual(trace.route, .needsClarification)
        XCTAssertNotNil(trace.clarificationMessage)
    }

    func testQualityGateKeepsAcceptLocalWhenOnlyCompileNotesPresent() {
        let gate = SceneQualityGate()
        let anchors = SourceAnchorBundle(
            actorCountHint: 1,
            ordinalMentions: ["first"],
            mentionedMarkedObjects: [],
            objectSurfaceMentions: [],
            phaseCues: [],
            unsupportedActionFlags: [],
            sameTypeMarkerConflict: false,
            lowConfidenceFlags: []
        )
        let providerResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [],
                beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .stand)])],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1"])
            ),
            usedLegacySceneScriptBridge: false
        )
        let script = SceneScript(
            actors: [.init(id: "actor_1", type: .human)],
            objects: [],
            beats: [.init(id: "beat_1", actions: [.init(id: "action_1", actorId: "actor_1", type: .stand)])],
            spatialRelations: [],
            originalDescription: "demo"
        )
        let trace = gate.decide(
            anchors: anchors,
            providerResult: providerResult,
            compiledScript: script,
            compileNotes: ["v8.targetless_action_downgraded"],
            remoteEnabled: false
        )

        XCTAssertEqual(trace.route, .acceptLocal)
        XCTAssertTrue(trace.reasons.contains("v8.targetless_action_downgraded"))
    }

    func testCoordinatorPropagatesClarificationTraceIntoDiagnostics() {
        let compiler = ScenePlanCompiler()
        let coordinator = SceneParseCoordinator(
            anchorExtractor: SceneAnchorExtractor(),
            metadataExtractor: SceneMetadataExtractor(),
            localProvider: StubLocalProvider(
                result: ScenePlanProviderResult(
                    plan: ScenePlanIR(
                        actors: [.init(ref: "first", type: .human)],
                        objects: [.init(ref: "object_slot_1", type: .chair, relativePosition: .left)],
                        beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .stand, targetRef: "object_slot_1")])],
                        spatialRelations: [],
                        referenceBindings: .init(actorBindings: ["first": "actor_1"])
                    ),
                    usedLegacySceneScriptBridge: false
                )
            ),
            compiler: compiler,
            qualityGate: SceneQualityGate(),
            diagnosticsCalculator: DiagnosticsCalculator()
        )

        let result = coordinator.parse(
            description: "Второй стоит у правого стула",
            markedObjects: [
                MarkedObject(name: "левый стул", position: .init(x: 0, y: 0, z: 0)),
                MarkedObject(name: "правый стул", position: .init(x: 1, y: 0, z: 0)),
            ]
        ) {
            ParsingResult(
                script: SceneScript(
                    actors: [.init(id: "actor_1", type: .human)],
                    objects: [.init(id: "object_1", type: .chair, relativePosition: .left)],
                    beats: [.init(id: "beat_1", actions: [.init(id: "action_1", actorId: "actor_1", type: .stand)])],
                    spatialRelations: [],
                    originalDescription: "fallback"
                ),
                diagnostics: .empty
            )
        }

        XCTAssertEqual(result.trace.route, .needsClarification)
        XCTAssertTrue(result.result.diagnostics.notes.contains(where: { $0.contains("router=needs_clarification") }))
    }

    func testMetadataExtractorParsesHeadingLocationAndTimeOfDay() {
        let extractor = SceneMetadataExtractor()
        let metadata = extractor.extract(description: "INT. KITCHEN - EVENING\nПервый подходит к столу")

        XCTAssertEqual(metadata.interiorExterior, "interior")
        XCTAssertEqual(metadata.locationName, "KITCHEN")
        XCTAssertEqual(metadata.timeOfDay, "evening")
        XCTAssertEqual(metadata.sceneHeading, "INT. KITCHEN - EVENING")
    }

    func testCoordinatorUsesRemotePlanWhenOffloadEnabled() async {
        let localResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [],
                beats: [],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1"])
            ),
            usedLegacySceneScriptBridge: false
        )
        let remoteResult = ScenePlanProviderResult(
            plan: ScenePlanIR(
                actors: [.init(ref: "first", type: .human)],
                objects: [.init(ref: "object_slot_1", type: .table, relativePosition: .center)],
                beats: [.init(ref: "beat_1", actions: [.init(actorRef: "first", type: .approach, targetRef: "object_slot_1")])],
                spatialRelations: [],
                referenceBindings: .init(actorBindings: ["first": "actor_1"])
            ),
            usedLegacySceneScriptBridge: false
        )
        let coordinator = SceneParseCoordinator(
            anchorExtractor: SceneAnchorExtractor(),
            metadataExtractor: SceneMetadataExtractor(),
            localProvider: StubLocalProvider(result: localResult),
            remoteProvider: StubRemoteProvider(result: remoteResult),
            compiler: ScenePlanCompiler(),
            qualityGate: SceneQualityGate(),
            diagnosticsCalculator: DiagnosticsCalculator(),
            remoteOffloadEnabled: true
        )

        let output = await coordinator.parseAsync(
            description: "Человек подходит к столу",
            markedObjects: []
        ) {
            ParsingResult(
                script: SceneScript(actors: [], objects: [], beats: [], spatialRelations: [], originalDescription: "fallback"),
                diagnostics: .empty
            )
        }

        XCTAssertEqual(output.trace.route, .offloadRemote)
        XCTAssertTrue(output.trace.reasons.contains("remote_plan_used"))
        XCTAssertEqual(output.result.script.beats.count, 1)
        XCTAssertEqual(output.result.script.objects.count, 1)
    }

    func testLiveLocalModelSmokeCases() async throws {
        guard configBool(Self.liveModelSmokeFlagKey) || sentinelEnabled(for: Self.liveModelSmokeSentinelPath) else {
            throw XCTSkip("Enable SG_RUN_LIVE_MODEL_SMOKE=1 or create /tmp/scene_live_model_smoke.enabled to run the local-model smoke suite.")
        }

        let parser = SceneParserService.shared
        parser.resetRuntimeContext()

        let cases: [(description: String, markedObjects: [MarkedObject], expectedActorFloor: Int)] = [
            (
                "Человек подходит к столу, останавливается рядом и смотрит на него.",
                [],
                1
            ),
            (
                "Первый подходит к шкафу, второй держится рядом, а третий остаётся у киоска.",
                [],
                3
            ),
            (
                "Первый подходит к компьютеру, второй останавливается рядом.",
                [MarkedObject(name: "компьютер", position: .zero)],
                2
            ),
            (
                "Первый актёр говорит: «Положи коробку сюда, потом разберём», после чего второй кладёт коробку на стойку.",
                [],
                2
            ),
            (
                "Таня говорит: «Передай конверт третьему». Рома отвечает: «Сейчас передам». Затем второй берёт письмо и передаёт его Яне, после чего письмо получает третий.",
                [],
                3
            ),
        ]

        for testCase in cases {
            let result = await parser.parseBundle(testCase.description, markedObjects: testCase.markedObjects)
            let activeScene = try XCTUnwrap(result.activeSceneScript, "Missing active scene for: \(testCase.description)")
            XCTAssertFalse(activeScene.beats.isEmpty, "Expected non-empty beats for: \(testCase.description)")
            XCTAssertGreaterThanOrEqual(
                activeScene.actors.count,
                testCase.expectedActorFloor,
                "Unexpected actor count for: \(testCase.description)"
            )
            XCTAssertFalse(
                result.chunkDiagnostics.contains(where: \.usedFallbackPlanner),
                "Fallback planner used for: \(testCase.description)"
            )
        }
    }

    func testLiveLocalModelDatasetSampledCases() async throws {
        guard configBool(Self.liveDatasetSmokeFlagKey) || sentinelEnabled(for: Self.liveDatasetSmokeSentinelPath) else {
            throw XCTSkip("Enable SG_RUN_LIVE_MODEL_DATASET_SMOKE=1 or create /tmp/scene_live_dataset_smoke.enabled to run the dataset-driven local-model smoke suite.")
        }

        let seed = configUInt64("SG_LIVE_DATASET_SEED", default: 20260426)
        let caseLimit = max(1, configInt("SG_LIVE_DATASET_CASE_LIMIT", default: 12))
        let minPassRate = configDouble("SG_LIVE_DATASET_MIN_PASS_RATE", default: 0.60)
        let parser = SceneParserService.shared
        let llmParser = LLMParserService.shared
        guard let modelPath = resolveLiveModelPath() else {
            XCTFail("Live dataset smoke could not resolve GGUF model path.")
            return
        }
        let patternFilter = Set(
            (configString("SG_LIVE_DATASET_PATTERN_FILTER") ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        let previousModelOverride = UserDefaults.standard.string(forKey: Self.liveModelOverrideKey)
        UserDefaults.standard.set(modelPath, forKey: Self.liveModelOverrideKey)
        defer {
            if let previousModelOverride {
                UserDefaults.standard.set(previousModelOverride, forKey: Self.liveModelOverrideKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.liveModelOverrideKey)
            }
        }

        await llmParser.loadModelIfNeeded()
        let llmStateDescription = loadingStateDescription(llmParser.loadingState)
        let sampledRecords = try sampledLiveDatasetRecords(
            seed: seed,
            caseLimit: caseLimit,
            patternFilter: patternFilter.isEmpty ? nil : patternFilter
        )

        XCTAssertFalse(sampledRecords.isEmpty, "Expected non-empty sampled dataset cases.")
        XCTAssertTrue(
            llmParser.isAvailable,
            "Live dataset smoke requires the local LLM to be available. loadingState=\(llmStateDescription), modelPath=\(modelPath)"
        )

        var evaluations: [LiveDatasetEvaluation] = []

        for record in sampledRecords {
            parser.resetRuntimeContext()
            let markedObjects = makeMarkedObjects(from: record)
            let result = await parser.parseBundle(record.sourceText, markedObjects: markedObjects)
            let evaluation = evaluateLiveDatasetCase(
                record: record,
                result: result,
                trace: parser.lastRuntimeTrace
            )
            evaluations.append(evaluation)
        }

        let summary = """
        MODEL path=\(modelPath)
        MODEL loadingState=\(llmStateDescription)
        \(liveDatasetSummary(evaluations: evaluations, seed: seed))
        """
        await MainActor.run {
            XCTContext.runActivity(named: "Live dataset smoke summary") { activity in
                let attachment = XCTAttachment(string: summary)
                attachment.name = "live-dataset-smoke-summary.txt"
                attachment.lifetime = .keepAlways
                activity.add(attachment)
            }
        }
        if let outputPath = configString("SG_LIVE_DATASET_SUMMARY_PATH"), !outputPath.isEmpty {
            try summary.write(to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
        }
        print(summary)

        let passCount = evaluations.filter(\.passed).count
        let passRate = Double(passCount) / Double(max(evaluations.count, 1))
        XCTAssertGreaterThanOrEqual(
            passRate,
            minPassRate,
            "Live dataset smoke pass rate dropped below threshold.\n\(summary)"
        )
    }
}
