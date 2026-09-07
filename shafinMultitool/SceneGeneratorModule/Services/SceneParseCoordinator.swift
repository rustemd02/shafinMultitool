//
//  SceneParseCoordinator.swift
//  shafinMultitool
//
//  Created on 21.04.2026.
//

import Foundation

/// The bounded answer vocabulary owned by one generator clarification
/// request.  Free text is still checked against observed candidate aliases;
/// it is not a second parser input channel.
enum SceneClarificationAnswer: Equatable {
    case choice(String)
    case option(String)
    case freeText(String)

    var rawValue: String {
        switch self {
        case .choice(let value), .option(let value), .freeText(let value):
            return value
        }
    }

    var isFreeText: Bool {
        if case .freeText = self { return true }
        return false
    }
}

enum SceneClarificationRejection: String, Codable, Equatable {
    case noActiveRequest
    case staleRequest
    case repeatedAnswer
    case invalidAnswer
    case unresolvedAnswer
    case retryLimitReached
    case requestFailed
    case workspaceUnavailable
}

enum SceneClarificationSubmissionResult: Equatable {
    case accepted
    case rejected(SceneClarificationRejection)

    var isAccepted: Bool {
        self == .accepted
    }

    var didAccept: Bool {
        isAccepted
    }
}

struct SceneClarificationOption: Codable, Equatable, Identifiable {
    let id: String
    let label: String

    var accessibilityLabel: String { label }
}

/// Immutable, request-owned clarification surface.  The payload contains
/// only candidate IDs observed in the submitted parser/binding snapshot and
/// carries the same request UUID/epoch as the state machine.
struct SceneClarificationPayload: Codable, Equatable, Identifiable {
    let id: String
    let requestID: UUID
    let epoch: UInt
    let prompt: String
    let targetReference: String?
    let options: [SceneClarificationOption]
    let allowsFreeText: Bool
    let maximumFreeTextCharacters: Int
    let observedDiagnostics: [String]
    let attempt: Int

    static let defaultMaximumFreeTextCharacters = 160

    static func make(
        requestID: UUID,
        epoch: UInt,
        prompt: String,
        trace: SceneRuntimeTrace? = nil,
        bindingResult: SceneObjectBindingResult? = nil,
        markedObjects: [MarkedObject] = [],
        detectedObjects: [DetectedObject] = [],
        attempt: Int = 0
    ) -> Self? {
        let unresolved = bindingResult?.resolutions
            .filter { $0.state != .bound }
            .sorted { $0.reference < $1.reference }
            .first

        let candidates: [SceneObjectBinding]
        if let bindingResult {
            let candidateIDs = Set(unresolved?.candidateIDs ?? [])
            candidates = bindingResult.request.candidates
                .filter { candidateIDs.contains($0.canonicalID) }
        } else {
            let markedCandidates = markedObjects.map { marker in
                SceneObjectBinding(
                    canonicalID: marker.canonicalMarkedObjectID,
                    source: .marked,
                    confidence: 1,
                    name: marker.name.isEmpty ? marker.type.rawValue : marker.name,
                    aliases: [marker.name, marker.type.rawValue],
                    objectType: marker.type,
                    worldPosition: marker.worldPosition,
                    markerID: marker.id
                )
            }
            candidates = markedCandidates + detectedObjects.compactMap(ObjectDetectionBridge.makeBindingCandidate)
        }

        let sortedCandidates = candidates.sorted {
            if $0.canonicalID != $1.canonicalID {
                return $0.canonicalID < $1.canonicalID
            }
            return $0.name < $1.name
        }
        guard !sortedCandidates.isEmpty else {
            // A clarification without a bounded observed answer cannot be
            // safely presented or resumed.  The caller keeps the typed state
            // and reports the failure rather than inventing a choice.
            return nil
        }

        let options = sortedCandidates.map { candidate in
            let suffix = String(candidate.canonicalID.suffix(8))
            let base = candidate.name.isEmpty ? candidate.objectType.rawValue : candidate.name
            return SceneClarificationOption(
                id: candidate.canonicalID,
                label: "\(base) · \(suffix)"
            )
        }
        let reasons = (trace?.reasons ?? [])
            + (bindingResult?.diagnostics ?? [])
            + (bindingResult?.resolutions.compactMap(\.diagnostic) ?? [])
        var diagnostics: [String] = []
        for reason in reasons where !reason.isEmpty && !diagnostics.contains(reason) {
            diagnostics.append(reason)
        }
        let targetReference = unresolved?.reference
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return nil }
        let payloadID = [
            requestID.uuidString.lowercased(),
            String(epoch),
            targetReference ?? "parser",
            String(attempt)
        ].joined(separator: ":")
        return Self(
            id: payloadID,
            requestID: requestID,
            epoch: epoch,
            prompt: prompt,
            targetReference: targetReference,
            options: options,
            allowsFreeText: !options.isEmpty,
            maximumFreeTextCharacters: defaultMaximumFreeTextCharacters,
            observedDiagnostics: diagnostics,
            attempt: max(0, attempt)
        )
    }

    func withAttempt(_ nextAttempt: Int) -> Self {
        Self(
            id: [requestID.uuidString.lowercased(), String(epoch), targetReference ?? "parser", String(nextAttempt)].joined(separator: ":"),
            requestID: requestID,
            epoch: epoch,
            prompt: prompt,
            targetReference: targetReference,
            options: options,
            allowsFreeText: allowsFreeText,
            maximumFreeTextCharacters: maximumFreeTextCharacters,
            observedDiagnostics: observedDiagnostics,
            attempt: max(0, nextAttempt)
        )
    }
}

final class SceneParseCoordinator {
    private let anchorExtractor: SceneAnchorExtractor
    private let metadataExtractor: SceneMetadataExtractor
    private let localProvider: LocalScenePlanProvider
    private let remoteProvider: RemoteScenePlanProvider?
    private let compiler: ScenePlanCompiler
    private let qualityGate: SceneQualityGate
    private let diagnosticsCalculator: DiagnosticsCalculator
    private let remoteOffloadEnabled: Bool

    init(
        anchorExtractor: SceneAnchorExtractor,
        metadataExtractor: SceneMetadataExtractor,
        localProvider: LocalScenePlanProvider,
        remoteProvider: RemoteScenePlanProvider? = nil,
        compiler: ScenePlanCompiler,
        qualityGate: SceneQualityGate,
        diagnosticsCalculator: DiagnosticsCalculator,
        remoteOffloadEnabled: Bool = false
    ) {
        self.anchorExtractor = anchorExtractor
        self.metadataExtractor = metadataExtractor
        self.localProvider = localProvider
        self.remoteProvider = remoteProvider
        self.compiler = compiler
        self.qualityGate = qualityGate
        self.diagnosticsCalculator = diagnosticsCalculator
        self.remoteOffloadEnabled = remoteOffloadEnabled
    }

    func parse(
        description: String,
        markedObjects: [MarkedObject],
        state: SceneChunkState? = nil,
        ruleBasedFallback: () -> ParsingResult
    ) -> (result: ParsingResult, trace: SceneRuntimeTrace) {
        let metadata = metadataExtractor.extract(description: description, fallbackLocationName: state?.locationName)
        let anchors = anchorExtractor.extract(description: description, markedObjects: markedObjects)
        let providerResult = localProvider.generatePlan(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            state: state
        )
        return finalize(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            metadata: metadata,
            state: state,
            providerResult: providerResult,
            ruleBasedFallback: ruleBasedFallback
        )
    }

    func parseAsync(
        description: String,
        markedObjects: [MarkedObject],
        state: SceneChunkState? = nil,
        ruleBasedFallback: () -> ParsingResult
    ) async -> (result: ParsingResult, trace: SceneRuntimeTrace) {
        let metadata = metadataExtractor.extract(description: description, fallbackLocationName: state?.locationName)
        let anchors = anchorExtractor.extract(description: description, markedObjects: markedObjects)
        let providerResult = await localProvider.generatePlanAsync(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            state: state
        )
        return await finalizeAsync(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            metadata: metadata,
            state: state,
            providerResult: providerResult,
            ruleBasedFallback: ruleBasedFallback
        )
    }

    private func finalize(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        metadata: SceneTopLevelMetadata,
        state _: SceneChunkState? = nil,
        providerResult: ScenePlanProviderResult?,
        ruleBasedFallback: () -> ParsingResult
    ) -> (result: ParsingResult, trace: SceneRuntimeTrace) {
        let compiledScript: SceneScript?
        let compileNotes: [String]
        if let providerResult {
            if let compiled = try? compiler.compileWithNotes(
                plan: providerResult.plan,
                originalDescription: description,
                topLevelMetadata: (
                    sceneHeading: metadata.sceneHeading,
                    locationName: metadata.locationName,
                    interiorExterior: metadata.interiorExterior,
                    timeOfDay: metadata.timeOfDay
                )
            ) {
                compiledScript = compiled.script
                compileNotes = compiled.notes
            } else {
                compiledScript = nil
                compileNotes = []
            }
        } else {
            compiledScript = nil
            compileNotes = []
        }

        let trace = qualityGate.decide(
            anchors: anchors,
            providerResult: providerResult,
            compiledScript: compiledScript,
            compileNotes: compileNotes,
            remoteEnabled: remoteOffloadEnabled
        )

        switch trace.route {
        case .acceptLocal:
            guard let compiledScript else {
                let fallback = ruleBasedFallback()
                return (fallback, trace)
            }
            // M5-026: the compiled script is validated before it reaches
            // project state. Invalid outputs fall back to the rule-based
            // result with typed reasons — never silently repaired
            // (M5-027 owns the repair boundary), never partially committed.
            let responseIssues = SceneResponseValidator.validate(
                script: compiledScript,
                markedObjectIDs: Set(markedObjects.map(\.canonicalMarkedObjectID)),
                mentionedMarkedObjects: Set(anchors.mentionedMarkedObjects)
            )
            guard responseIssues.isEmpty else {
                var rejectedTrace = trace
                rejectedTrace.route = .fallbackRuleOnly
                for issue in responseIssues where !rejectedTrace.reasons.contains("response_invalid:\(issue.rawValue)") {
                    rejectedTrace.reasons.append("response_invalid:\(issue.rawValue)")
                }
                return (augmentFallback(ruleBasedFallback(), with: rejectedTrace), rejectedTrace)
            }
            let result = makeParsingResult(
                script: compiledScript,
                description: description,
                markedObjects: markedObjects,
                trace: trace
            )
            return (result, trace)

        case .offloadRemote:
            return (augmentFallback(ruleBasedFallback(), with: trace), trace)

        case .needsClarification, .fallbackRuleOnly:
            return (augmentFallback(ruleBasedFallback(), with: trace), trace)
        }
    }

    private func finalizeAsync(
        description: String,
        markedObjects: [MarkedObject],
        anchors: SourceAnchorBundle,
        metadata: SceneTopLevelMetadata,
        state: SceneChunkState? = nil,
        providerResult: ScenePlanProviderResult?,
        ruleBasedFallback: () -> ParsingResult
    ) async -> (result: ParsingResult, trace: SceneRuntimeTrace) {
        let output = finalize(
            description: description,
            markedObjects: markedObjects,
            anchors: anchors,
            metadata: metadata,
            state: state,
            providerResult: providerResult,
            ruleBasedFallback: ruleBasedFallback
        )
        guard output.trace.route == .offloadRemote,
              remoteOffloadEnabled,
              let remoteProvider,
              let remoteResult = await remoteProvider.generateRemotePlan(
                description: description,
                markedObjects: markedObjects,
                anchors: anchors,
                state: state
              ),
              let remoteCompiled = try? compiler.compileWithNotes(
                plan: remoteResult.plan,
                originalDescription: description,
                topLevelMetadata: (
                    sceneHeading: metadata.sceneHeading,
                    locationName: metadata.locationName,
                    interiorExterior: metadata.interiorExterior,
                    timeOfDay: metadata.timeOfDay
                )
              )
        else {
            return output
        }

        var remoteTrace = output.trace
        for note in remoteCompiled.notes where !remoteTrace.reasons.contains(note) {
            remoteTrace.reasons.append(note)
        }
        if !remoteTrace.reasons.contains("remote_plan_used") {
            remoteTrace.reasons.append("remote_plan_used")
        }
        // M5-026: remote outputs pass the same validation gate before
        // they reach project state.
        let remoteIssues = SceneResponseValidator.validate(
            script: remoteCompiled.script,
            markedObjectIDs: Set(markedObjects.map(\.canonicalMarkedObjectID)),
            mentionedMarkedObjects: Set(anchors.mentionedMarkedObjects)
        )
        guard remoteIssues.isEmpty else {
            remoteTrace.route = .fallbackRuleOnly
            for issue in remoteIssues where !remoteTrace.reasons.contains("response_invalid:\(issue.rawValue)") {
                remoteTrace.reasons.append("response_invalid:\(issue.rawValue)")
            }
            return (augmentFallback(ruleBasedFallback(), with: remoteTrace), remoteTrace)
        }
        let result = makeParsingResult(
            script: remoteCompiled.script,
            description: description,
            markedObjects: markedObjects,
            trace: remoteTrace
        )
        return (result, remoteTrace)
    }

    private func makeParsingResult(
        script: SceneScript,
        description: String,
        markedObjects: [MarkedObject],
        trace: SceneRuntimeTrace
    ) -> ParsingResult {
        let matchedMarkedObjectIDs = matchedMarkedObjectIDs(from: script.objects, markedObjects: markedObjects)
        var diagnostics = diagnosticsCalculator.calculateDiagnostics(
            script: script,
            originalText: description,
            markedObjects: markedObjects,
            matchedMarkedObjects: matchedMarkedObjectIDs
        )
        diagnostics = mergeTrace(diagnostics, trace: trace)
        return ParsingResult(script: script, diagnostics: diagnostics)
    }

    private func augmentFallback(_ result: ParsingResult, with trace: SceneRuntimeTrace) -> ParsingResult {
        ParsingResult(script: result.script, diagnostics: mergeTrace(result.diagnostics, trace: trace))
    }

    private func mergeTrace(_ diagnostics: ParsingDiagnostics, trace: SceneRuntimeTrace) -> ParsingDiagnostics {
        var notes = diagnostics.notes
        let routeNote = "router=\(trace.route.rawValue)"
        if !notes.contains(routeNote) {
            notes.append(routeNote)
        }
        if let clarificationMessage = trace.clarificationMessage, !notes.contains(clarificationMessage) {
            notes.append(clarificationMessage)
        }
        for reason in trace.reasons {
            let note = "trace:\(reason)"
            if !notes.contains(note) {
                notes.append(note)
            }
        }
        return ParsingDiagnostics(
            confidence: diagnostics.confidence,
            coverage: diagnostics.coverage,
            missingActors: diagnostics.missingActors,
            missingObjects: diagnostics.missingObjects,
            unresolvedPronouns: diagnostics.unresolvedPronouns,
            unresolvedMarkedObjects: diagnostics.unresolvedMarkedObjects,
            notes: notes,
            matchedMarkedObjects: diagnostics.matchedMarkedObjects
        )
    }

    private func matchedMarkedObjectIDs(from objects: [SceneObject], markedObjects: [MarkedObject]) -> [UUID] {
        objects.compactMap { object in
            guard let shortID = object.markedObjectShortID else { return nil }
            return markedObjects.first(where: { $0.markedShortID == shortID })?.id
        }
    }
}
