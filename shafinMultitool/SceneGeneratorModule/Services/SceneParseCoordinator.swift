//
//  SceneParseCoordinator.swift
//  shafinMultitool
//
//  Created on 21.04.2026.
//

import Foundation

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
