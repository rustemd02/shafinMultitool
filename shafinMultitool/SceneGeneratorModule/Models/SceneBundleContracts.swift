//
//  SceneBundleContracts.swift
//  shafinMultitool
//
//  Created on 22.04.2026.
//

import Foundation

/// M5-001: typed, non-owning contract for the production Scene journey.
/// Existing Library/Generator/AR/Storyboard/recording owners remain the
/// mutation owners; this catalog only describes their shared hand-off.
enum SceneJourneyState: String, CaseIterable, Codable, Equatable, Identifiable {
    // Visual Policy v2.6: Library.
    case libraryEmpty = "library.empty"
    case libraryLoaded = "library.contact-sheet"
    case librarySelected = "library.selected"
    case libraryRenameName = "library.rename-name"
    case libraryMissingPreview = "library.missing-preview"
    case libraryCreateName = "library.create-name"
    case libraryDuplicateName = "library.duplicate-name"
    case libraryDeleteConfirmation = "library.delete-confirmation"
    case libraryPersistenceFailure = "library.persistence-failure"

    // Visual Policy v2.6: Generator input and execution.
    case generatorInputEmpty = "generator.input-empty"
    case generatorInputEditing = "generator.input-editing"
    case generatorInputKeyboard = "generator.input-keyboard"
    case generatorInputMarkedDetected = "generator.input-marked-detected"
    case generatorInputInvalid = "generator.input-invalid"
    case generatorClarification = "generator.clarification"
    case generatorAccepted = "generator.accepted"
    case generatorLeader = "generator.leader"
    case generatorProgressReading = "generator.progress-reading"
    case generatorProgressAnchors = "generator.progress-anchors"
    case generatorProgressFrame = "generator.progress-frame"
    case generatorBackgroundCancel = "generator.background-cancel"
    case generatorFailureParse = "generator.failure-parse"
    case generatorFailureNetwork = "generator.failure-network"
    case generatorFailureModel = "generator.failure-model"
    case generatorRetry = "generator.retry"
    case generatorSuccess = "generator.success"

    // Visual Policy v2.6: AR and playback. `ar.playback` is retained as the
    // existing workspace hand-off state; the policy row for hint playback is
    // represented separately by `ar.hint-playback`.
    case arPreparing = "ar.preparing"
    case arReady = "ar.ready"
    case arSurfaceSearch = "ar.surface-search"
    case arPlacement = "ar.placement"
    case arPlayback = "ar.playback"
    case arMarking = "ar.marking"
    case arLiveHints = "ar.live-hints"
    case arHintPause = "ar.hint-pause"
    case arHintPlayback = "ar.hint-playback"
    case recordingInProgress = "ar.recording"
    case recordingReview = "ar.recording-review"
    case arInterruption = "ar.interruption"
    case arError = "ar.error"
    case arTeardown = "ar.teardown"

    // Visual Policy v2.6: Storyboard.
    case storyboardTrayCollapsed = "storyboard.tray-collapsed"
    case storyboardTrayExpanded = "storyboard.tray-expanded"
    case storyboardSelectionReflow = "storyboard.selection-reflow"
    case storyboardResult = "storyboard.result"
    case storyboardInspector = "storyboard.inspector"
    case storyboardEditorMedium = "storyboard.editor-medium"
    case storyboardEditorLarge = "storyboard.editor-large"
    case storyboardSaving = "storyboard.saving"
    case storyboardValidationFailure = "storyboard.validation-failure"
    case storyboardDeleteConfirmation = "storyboard.delete-confirmation"

    // Visual Policy v2.6: relevant sheets.
    case sheetSceneName = "sheet.scene-name"
    case sheetMarkerName = "sheet.marker-name"
    case sheetScreenplayInput = "sheet.screenplay-input"
    case sheetDecisionTrace = "sheet.decision-trace"

    // RecordingLifecycleState plus the explicit export hand-off. The visual
    // recording/review rows above remain the presentation states.
    case recordingIdle = "recording.idle"
    case recordingPreparing = "recording.preparing"
    case recordingReady = "recording.ready"
    case recordingStarting = "recording.starting"
    case recordingStopping = "recording.stopping"
    case recordingFinalizing = "recording.finalizing"
    case recordingPromoting = "recording.promoting"
    case recordingCompleted = "recording.completed"
    case recordingFailure = "recording.failed"
    case recordingCancelled = "recording.cancelled"
    case recordingReleased = "recording.released"
    case recordingExporting = "recording.exporting"
    case recordingExported = "recording.exported"

    var id: String { rawValue }

    /// Deliberately independent from `CaseIterable`: this is the frozen 1.0
    /// identity set that a custom contract must exactly reproduce.
    static let canonicalStateIDs: [String] = [
        "library.empty", "library.contact-sheet", "library.selected", "library.rename-name",
        "library.missing-preview", "library.create-name", "library.duplicate-name", "library.delete-confirmation",
        "library.persistence-failure", "generator.input-empty", "generator.input-editing",
        "generator.input-keyboard", "generator.input-marked-detected", "generator.input-invalid",
        "generator.clarification", "generator.accepted", "generator.leader",
        "generator.progress-reading", "generator.progress-anchors", "generator.progress-frame",
        "generator.background-cancel", "generator.failure-parse", "generator.failure-network",
        "generator.failure-model", "generator.retry", "generator.success", "ar.preparing",
        "ar.ready", "ar.surface-search", "ar.placement", "ar.playback", "ar.marking",
        "ar.live-hints", "ar.hint-pause", "ar.hint-playback", "ar.recording",
        "ar.recording-review", "ar.interruption", "ar.error", "ar.teardown",
        "storyboard.tray-collapsed", "storyboard.tray-expanded", "storyboard.selection-reflow",
        "storyboard.result", "storyboard.inspector", "storyboard.editor-medium",
        "storyboard.editor-large", "storyboard.saving", "storyboard.validation-failure",
        "storyboard.delete-confirmation", "sheet.scene-name", "sheet.marker-name",
        "sheet.screenplay-input", "sheet.decision-trace", "recording.idle", "recording.preparing",
        "recording.ready", "recording.starting", "recording.stopping", "recording.finalizing",
        "recording.promoting", "recording.completed", "recording.failed", "recording.cancelled",
        "recording.released", "recording.exporting", "recording.exported"
    ]
}

/// Typed source vocabulary. Raw values document the existing production
/// symbols; state contracts store this enum rather than unchecked source-name
/// strings.
enum SceneJourneySourceState: String, CaseIterable, Codable, Equatable {
    case libraryEmpty = "SETLibraryModel.FlowState.idle + scenes.isEmpty"
    case libraryLoaded = "SETLibraryModel.FlowState.idle + scenes"
    case librarySelected = "SETLibraryModel.selectedSceneID"
    case libraryCreating = "SETLibraryModel.FlowState.creating"
    case libraryDuplicate = "SETLibraryModel.FlowState.duplicate"
    case libraryDeleting = "SETLibraryModel.FlowState.deleting"
    case libraryFailure = "SETLibraryModel.FlowState.failure"
    case workspaceEditing = "SceneWorkspaceMode.editingScene"
    case workspaceMarking = "SceneWorkspaceMode.marking"
    case workspaceGeneratedReady = "SceneWorkspaceMode.generatedReady"
    case workspaceShooting = "SceneWorkspaceMode.shooting"
    case workspaceRecording = "SceneWorkspaceMode.recording"
    case workspacePreviewPlayback = "SceneWorkspaceMode.previewPlayback"
    case generationReading = "SceneGenerationStage.reading"
    case generationPlanning = "SceneGenerationStage.planning"
    case generationPlacing = "SceneGenerationStage.placing"
    case recordingIdle = "RecordingLifecycleState.idle"
    case recordingPreparing = "RecordingLifecycleState.preparing"
    case recordingReady = "RecordingLifecycleState.ready"
    case recordingStarting = "RecordingLifecycleState.starting"
    case recordingInProgress = "RecordingLifecycleState.recording"
    case recordingStopping = "RecordingLifecycleState.stopping"
    case recordingFinalizing = "RecordingLifecycleState.finalizing"
    case recordingPromoting = "RecordingLifecycleState.promoting"
    case recordingCompleted = "RecordingLifecycleState.completed"
    case recordingFailure = "RecordingLifecycleState.failed"
    case recordingCancelled = "RecordingLifecycleState.cancelled"
    case recordingReleased = "RecordingLifecycleState.released"
    case sceneScript = "SceneScript"
    case plannedScene = "PlannedScene"
    case recordingArtifact = "RecordingArtifact"
    case arSession = "ARSceneContainer"
    case storyboardProjection = "SceneGeneratorViewModel.storyboardBeatItems"
    case decisionTrace = "DecisionTraceView"
    case keyboard = "system keyboard owner"
    case scenePersistence = "UnifiedSceneProject persistence owner"
    case recordingExport = "RecordingArtifactStore export owner"
}

enum SceneJourneyOwner: String, Codable, Equatable {
    case library = "SETLibraryModel"
    case libraryPersistence = "SETLibraryModel + scene persistence owner"
    case generator = "SceneGeneratorViewModel"
    case generatorInput = "SceneInputSheet + SceneGeneratorViewModel"
    case generatorExecution = "SceneGeneratorViewModel generation owner"
    case ar = "ARSceneContainer + AR session owner"
    case storyboard = "SceneGeneratorViewModel storyboard owner"
    case storyboardEditor = "SceneGeneratorViewModel storyboard editor owner"
    case recording = "SceneRecordingController + RecordingLifecycleOwner"
    case recordingStore = "RecordingArtifactStore"
    case persistence = "scene persistence owner"
    case keyboard = "system keyboard owner"
    case trace = "DecisionTraceView + SceneGeneratorViewModel"
    case export = "RecordingArtifactStore export owner"
}

enum SceneJourneyAvailability: String, Codable, Equatable {
    case production
    case fixtureOnly = "fixture-only"
    case pending
    case unreachable
}

enum SceneJourneyPersistence: String, Codable, Equatable {
    case none
    case draft = "scene draft only"
    case project = "UnifiedSceneProject"
    case artifact = "project + owned recording artifact"
    case release = "project + released recording artifact"
}

enum SceneJourneyArtifact: String, Codable, Equatable {
    case project = "project.id"
    case input = "scene input draft"
    case script = "SceneScript"
    case plannedScene = "PlannedScene"
    case arBindings = "AR marker/entity bindings"
    case storyboard = "Storyboard beat/action links"
    case decisionTrace = "DecisionTrace"
    case recording = "recording artifact"
    case recordingExport = "recording export"
    case preview = "real preview or metadata"
    case generationJob = "generation request"
}

enum SceneJourneyArtifactStatus: String, Codable, Equatable {
    case draft
    case validated
    case optional
    case missing
    case pending
    case promoted
}

enum SceneJourneyArtifactRequirement: String, Codable, Equatable {
    case required
    case optional
}

struct SceneJourneyArtifactRelation: Codable, Equatable, Identifiable {
    let artifact: SceneJourneyArtifact
    let status: SceneJourneyArtifactStatus
    let requirement: SceneJourneyArtifactRequirement

    var id: String { artifact.rawValue }
}

enum SceneJourneyTransitionKind: String, Codable, Equatable {
    case advance
    case recover
    case retry
    case cancel
    case teardown
    case export
    case delete
    case back
}

struct SceneJourneyTransition: Codable, Equatable {
    let to: SceneJourneyState
    let kind: SceneJourneyTransitionKind
    let trigger: String
}

struct SceneJourneyStateContract: Codable, Equatable, Identifiable {
    let state: SceneJourneyState
    let availability: SceneJourneyAvailability
    let owner: SceneJourneyOwner
    let sourceStates: [SceneJourneySourceState]
    let entry: String
    let primaryAction: String
    let recovery: String
    let exit: String
    let persistence: SceneJourneyPersistence
    let artifacts: [SceneJourneyArtifactRelation]
    let transitions: [SceneJourneyTransition]

    var id: String { state.id }

    /// Compatibility projection for callers that only need legal destinations.
    var allowedNext: [SceneJourneyState] { transitions.map(\.to) }

    func artifact(_ kind: SceneJourneyArtifact) -> SceneJourneyArtifactRelation? {
        artifacts.first { $0.artifact == kind }
    }
}

struct SceneJourneyContract: Codable, Equatable {
    let sourceVocabulary: [SceneJourneySourceState]
    let states: [SceneJourneyStateContract]

    private static func artifact(
        _ kind: SceneJourneyArtifact,
        _ status: SceneJourneyArtifactStatus,
        _ requirement: SceneJourneyArtifactRequirement = .optional
    ) -> SceneJourneyArtifactRelation {
        SceneJourneyArtifactRelation(artifact: kind, status: status, requirement: requirement)
    }

    private static func edge(
        _ to: SceneJourneyState,
        _ kind: SceneJourneyTransitionKind = .advance,
        _ trigger: String
    ) -> SceneJourneyTransition {
        SceneJourneyTransition(to: to, kind: kind, trigger: trigger)
    }

    private static func makeState(
        _ state: SceneJourneyState,
        availability: SceneJourneyAvailability = .production,
        owner: SceneJourneyOwner,
        sources: [SceneJourneySourceState],
        entry: String,
        action: String,
        recovery: String,
        exit: String,
        persistence: SceneJourneyPersistence,
        artifacts: [SceneJourneyArtifactRelation],
        transitions: [SceneJourneyTransition]
    ) -> SceneJourneyStateContract {
        SceneJourneyStateContract(
            state: state,
            availability: availability,
            owner: owner,
            sourceStates: sources,
            entry: entry,
            primaryAction: action,
            recovery: recovery,
            exit: exit,
            persistence: persistence,
            artifacts: artifacts,
            transitions: transitions
        )
    }

    static let production = SceneJourneyContract(
        sourceVocabulary: SceneJourneySourceState.allCases,
        states: [
            // Library: all seven Visual Policy rows, including CRUD and
            // missing-preview truth.
            makeState(.libraryEmpty, owner: .library, sources: [.libraryEmpty, .scenePersistence], entry: "real project count is zero", action: "create scene", recovery: "reload library", exit: "create-name or loaded", persistence: .none, artifacts: [artifact(.project, .missing, .required), artifact(.preview, .missing)], transitions: [edge(.libraryCreateName, .advance, "create action"), edge(.libraryLoaded, .recover, "reload returns rows")]),
            makeState(.libraryLoaded, owner: .library, sources: [.libraryLoaded], entry: "real project rows loaded", action: "select, create, or delete a row", recovery: "reload library", exit: "selected, empty, create-name, or failure", persistence: .none, artifacts: [artifact(.project, .optional), artifact(.preview, .optional)], transitions: [edge(.librarySelected, .advance, "real row selected"), edge(.libraryEmpty, .recover, "reload returns zero rows"), edge(.libraryCreateName, .advance, "create action")]),
            makeState(.librarySelected, owner: .library, sources: [.librarySelected, .scenePersistence], entry: "stable project ID selected", action: "open generator, rename, or request delete", recovery: "reopen project or reload", exit: "generator input, rename, missing preview, delete confirmation, loaded, or failure", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.preview, .optional), artifact(.input, .optional), artifact(.script, .optional), artifact(.plannedScene, .optional), artifact(.arBindings, .optional), artifact(.storyboard, .optional), artifact(.recording, .optional)], transitions: [edge(.generatorInputEmpty, .advance, "open selected project"), edge(.libraryRenameName, .advance, "rename selected row"), edge(.libraryMissingPreview, .recover, "preview cannot resolve"), edge(.libraryDeleteConfirmation, .delete, "delete selected row"), edge(.libraryLoaded, .back, "back to library"), edge(.libraryPersistenceFailure, .recover, "open/delete persistence failure")]),
            makeState(.libraryRenameName, availability: .pending, owner: .libraryPersistence, sources: [.librarySelected, .scenePersistence], entry: "selected scene name is being edited", action: "confirm or cancel rename", recovery: "preserve the old name and project ID", exit: "selected, duplicate, or failure", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.preview, .optional)], transitions: [edge(.librarySelected, .advance, "rename commits"), edge(.libraryDuplicateName, .recover, "rename conflicts"), edge(.libraryPersistenceFailure, .recover, "rename persistence failure")]),
            makeState(.libraryMissingPreview, availability: .pending, owner: .library, sources: [.librarySelected, .scenePersistence], entry: "selected row has no resolvable preview", action: "continue with truthful metadata or reload", recovery: "keep row identity and never fabricate a thumbnail", exit: "selected, generator input, or loaded", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.preview, .missing, .required), artifact(.input, .optional), artifact(.script, .optional)], transitions: [edge(.librarySelected, .recover, "metadata fallback acknowledged"), edge(.generatorInputEmpty, .advance, "open without preview"), edge(.libraryLoaded, .back, "reload library")]),
            makeState(.libraryCreateName, owner: .libraryPersistence, sources: [.libraryCreating], entry: "create flow owns a name draft", action: "confirm or cancel scene creation", recovery: "edit name without losing draft", exit: "selected, duplicate, failure, or loaded", persistence: .draft, artifacts: [artifact(.project, .draft, .required), artifact(.input, .draft, .required), artifact(.preview, .missing)], transitions: [edge(.librarySelected, .advance, "create succeeds and opens project"), edge(.libraryDuplicateName, .recover, "duplicate name result"), edge(.libraryPersistenceFailure, .recover, "create persistence failure"), edge(.libraryLoaded, .cancel, "cancel create")]),
            makeState(.libraryDuplicateName, owner: .libraryPersistence, sources: [.libraryDuplicate], entry: "persistence reports an existing name", action: "correct the conflicting name", recovery: "return to the active create or rename draft", exit: "create-name, rename-name, or loaded", persistence: .draft, artifacts: [artifact(.project, .missing, .required), artifact(.input, .draft, .required), artifact(.preview, .missing)], transitions: [edge(.libraryCreateName, .recover, "edit create name"), edge(.libraryRenameName, .recover, "edit rename"), edge(.libraryLoaded, .cancel, "cancel duplicate flow")]),
            makeState(.libraryDeleteConfirmation, owner: .libraryPersistence, sources: [.libraryDeleting, .librarySelected], entry: "selected project identity is visible", action: "confirm or cancel deletion", recovery: "cancel without deleting identity", exit: "loaded or failure", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.preview, .optional)], transitions: [edge(.libraryLoaded, .delete, "confirmed deletion"), edge(.librarySelected, .cancel, "cancel deletion"), edge(.libraryPersistenceFailure, .recover, "delete persistence failure")]),
            makeState(.libraryPersistenceFailure, owner: .libraryPersistence, sources: [.libraryFailure, .scenePersistence], entry: "create/delete/open/rename persistence failed", action: "retry the named operation", recovery: "preserve selection and draft; never claim success", exit: "loaded, selected, empty, create-name, or rename-name", persistence: .project, artifacts: [artifact(.project, .pending, .required), artifact(.input, .draft, .optional), artifact(.preview, .missing)], transitions: [edge(.libraryLoaded, .retry, "retry reload"), edge(.librarySelected, .recover, "retry open/delete restores selection"), edge(.libraryEmpty, .recover, "retry confirms empty"), edge(.libraryCreateName, .recover, "retry create restores draft"), edge(.libraryRenameName, .recover, "retry rename restores draft")]),

            // Generator: input, execution, truthful progress, cancellation,
            // and typed failure rows.
            makeState(.generatorInputEmpty, owner: .generatorInput, sources: [.workspaceEditing, .sceneScript], entry: "selected project has empty screenplay input", action: "enter screenplay text", recovery: "return to selected library row", exit: "editing, screenplay sheet, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .missing, .required), artifact(.script, .missing, .required), artifact(.plannedScene, .missing)], transitions: [edge(.generatorInputEditing, .advance, "text becomes nonempty"), edge(.sheetScreenplayInput, .advance, "open screenplay sheet"), edge(.librarySelected, .back, "close generator")]),
            makeState(.generatorInputEditing, owner: .generatorInput, sources: [.workspaceEditing, .sceneScript], entry: "screenplay draft is being edited", action: "submit one draft to the owner", recovery: "keep editable draft", exit: "keyboard, marked/detected, invalid, accepted, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required), artifact(.plannedScene, .missing)], transitions: [edge(.generatorInputKeyboard, .advance, "focus input"), edge(.generatorInputMarkedDetected, .advance, "mark/detect context"), edge(.generatorInputInvalid, .recover, "local validation rejects input"), edge(.generatorAccepted, .advance, "owner accepts submit"), edge(.librarySelected, .back, "close generator")]),
            makeState(.generatorInputKeyboard, owner: .keyboard, sources: [.workspaceEditing, .keyboard], entry: "screenplay field has system keyboard focus", action: "edit or paste without losing context", recovery: "dismiss keyboard and restore focus", exit: "editing or empty", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required)], transitions: [edge(.generatorInputEditing, .back, "keyboard dismissed"), edge(.generatorInputEmpty, .recover, "draft becomes empty")]),
            makeState(.generatorInputMarkedDetected, owner: .generator, sources: [.workspaceEditing, .workspaceMarking, .arSession], entry: "draft is accompanied by real mark/detection projections", action: "inspect context or submit draft", recovery: "retain draft when AR context is unavailable", exit: "editing, accepted, or AR marking", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.arBindings, .optional)], transitions: [edge(.generatorInputEditing, .back, "return to editor"), edge(.generatorAccepted, .advance, "submit with context"), edge(.arMarking, .advance, "open marking owner")]),
            makeState(.generatorInputInvalid, owner: .generatorInput, sources: [.workspaceEditing, .sceneScript], entry: "owner exposes input-local validation failure", action: "correct the invalid field", recovery: "keep text and field-level reason", exit: "editing, empty, or parse failure", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .missing, .required)], transitions: [edge(.generatorInputEditing, .recover, "correct text"), edge(.generatorInputEmpty, .recover, "clear text"), edge(.generatorFailureParse, .recover, "parser reports failure")]),
            makeState(.generatorClarification, availability: .unreachable, owner: .generatorExecution, sources: [.generationReading, .sceneScript], entry: "only a typed parser clarification result may enter", action: "answer the structured question", recovery: "cancel to the same draft", exit: "editing or accepted", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required)], transitions: [edge(.generatorInputEditing, .recover, "answer/cancel question"), edge(.generatorAccepted, .advance, "clarification resolves")]),
            makeState(.generatorAccepted, owner: .generatorExecution, sources: [.generationPlanning, .sceneScript], entry: "owner accepted one validated request", action: "start one idempotent generation", recovery: "cancel before work starts", exit: "leader, retry, input, or cancelled", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorLeader, .advance, "accepted request starts"), edge(.generatorRetry, .retry, "bounded enqueue retry"), edge(.generatorInputEditing, .cancel, "cancel before work")]),
            makeState(.generatorLeader, availability: .pending, owner: .generatorExecution, sources: [.generationPlanning], entry: "accepted request has a single leader event", action: "show leader once and begin work", recovery: "cancel the same request", exit: "progress or background-cancel", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorProgressReading, .advance, "leader completes"), edge(.generatorBackgroundCancel, .cancel, "route/background cancellation")]),
            makeState(.generatorProgressReading, owner: .generatorExecution, sources: [.generationReading], entry: "owner publishes reading stage", action: "consume truthful stage only", recovery: "cancel or classify error", exit: "anchors, failure, or background-cancel", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .pending, .required)], transitions: [edge(.generatorProgressAnchors, .advance, "reading completes"), edge(.generatorFailureParse, .recover, "parse failure"), edge(.generatorFailureNetwork, .recover, "network failure"), edge(.generatorFailureModel, .recover, "model failure"), edge(.generatorBackgroundCancel, .cancel, "background/cancel")]),
            makeState(.generatorProgressAnchors, owner: .generatorExecution, sources: [.generationPlacing], entry: "owner publishes anchor stage", action: "consume truthful anchor progress", recovery: "cancel or classify error", exit: "frame, failure, or background-cancel", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .pending, .required)], transitions: [edge(.generatorProgressFrame, .advance, "anchors complete"), edge(.generatorFailureNetwork, .recover, "network failure"), edge(.generatorFailureModel, .recover, "model failure"), edge(.generatorBackgroundCancel, .cancel, "background/cancel")]),
            makeState(.generatorProgressFrame, owner: .generatorExecution, sources: [.generationPlanning, .generationPlacing], entry: "owner publishes frame stage", action: "wait for a committed result", recovery: "cancel or classify error", exit: "success, failure, or background-cancel", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .pending, .required)], transitions: [edge(.generatorSuccess, .advance, "plan commits"), edge(.generatorFailureNetwork, .recover, "network failure"), edge(.generatorFailureModel, .recover, "model failure"), edge(.generatorBackgroundCancel, .cancel, "background/cancel")]),
            makeState(.generatorBackgroundCancel, owner: .generatorExecution, sources: [.generationReading, .sceneScript], entry: "request leaves foreground or is cancelled", action: "reconcile the same request", recovery: "retain prior committed scene and draft", exit: "accepted, progress, retry, input, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .optional)], transitions: [edge(.generatorAccepted, .recover, "resume same request"), edge(.generatorProgressReading, .recover, "resume reading"), edge(.generatorRetry, .retry, "retry classified request"), edge(.generatorInputEditing, .cancel, "cancel returns to draft"), edge(.librarySelected, .teardown, "workspace teardown")]),
            makeState(.generatorFailureParse, owner: .generatorExecution, sources: [.generationReading, .sceneScript], entry: "parser reports a non-success result", action: "inspect reason and edit input", recovery: "preserve previous readable project", exit: "retry or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .missing, .required), artifact(.generationJob, .missing)], transitions: [edge(.generatorRetry, .retry, "retry after corrected input"), edge(.generatorInputEditing, .recover, "edit input"), edge(.librarySelected, .back, "leave generator")]),
            makeState(.generatorFailureNetwork, owner: .generatorExecution, sources: [.generationReading], entry: "network/execution owner reports failure", action: "retry or leave the draft", recovery: "retain request and prior project; no fake success", exit: "retry or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .missing, .required)], transitions: [edge(.generatorRetry, .retry, "retry classified request"), edge(.generatorInputEditing, .back, "edit/cancel"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorFailureModel, owner: .generatorExecution, sources: [.generationPlanning], entry: "model owner reports failure", action: "retry or leave the draft", recovery: "retain request and prior project; no fake result", exit: "retry or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .missing, .required), artifact(.generationJob, .missing, .required)], transitions: [edge(.generatorRetry, .retry, "retry classified request"), edge(.generatorInputEditing, .back, "edit/cancel"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorRetry, owner: .generatorExecution, sources: [.generationReading, .sceneScript], entry: "bounded retry context is available", action: "retry the same draft/request once owned", recovery: "retain failure reason and close", exit: "accepted or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorAccepted, .retry, "retry accepted by owner"), edge(.generatorInputEditing, .back, "edit instead")]),
            makeState(.generatorSuccess, owner: .generatorExecution, sources: [.workspaceGeneratedReady, .sceneScript, .plannedScene, .storyboardProjection], entry: "committed SceneScript and PlannedScene are validated", action: "open AR or storyboard projection", recovery: "rollback only the attempted commit and retain draft", exit: "AR preparing or storyboard result", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .pending, .optional), artifact(.arBindings, .missing, .optional)], transitions: [edge(.arPreparing, .advance, "open AR workspace"), edge(.storyboardResult, .advance, "open storyboard projection"), edge(.generatorFailureModel, .recover, "commit/model failure")]),

            // AR: hardware-dependent readiness stays pending; interruption,
            // error, and teardown are explicit recovery edges.
            makeState(.arPreparing, availability: .pending, owner: .ar, sources: [.workspaceGeneratedReady, .arSession, .plannedScene], entry: "success hand-off owns stable project and plan", action: "prepare supported AR session", recovery: "release session and retry", exit: "ready, search, error, interruption, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .pending, .required), artifact(.storyboard, .optional)], transitions: [edge(.arReady, .advance, "session publishes valid frame"), edge(.arSurfaceSearch, .advance, "session enters search"), edge(.arError, .recover, "session error"), edge(.arInterruption, .recover, "session interrupted"), edge(.arTeardown, .teardown, "release workspace")]),
            makeState(.arReady, availability: .pending, owner: .ar, sources: [.workspaceShooting, .arSession], entry: "post-recovery frame and workspace are available", action: "search for a surface", recovery: "relocalize or reset", exit: "surface search, preparing, interruption, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .pending, .required)], transitions: [edge(.arSurfaceSearch, .advance, "search action"), edge(.arPreparing, .recover, "relocalize/reset"), edge(.arInterruption, .recover, "session interruption"), edge(.arError, .recover, "session error"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arSurfaceSearch, availability: .pending, owner: .ar, sources: [.workspaceShooting, .arSession], entry: "AR session exposes tracking search", action: "confirm a supported surface", recovery: "reposition and retry", exit: "placement, ready, interruption, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .pending, .required)], transitions: [edge(.arPlacement, .advance, "surface confirmed"), edge(.arReady, .recover, "search cancelled"), edge(.arInterruption, .recover, "session interruption"), edge(.arError, .recover, "session error"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arPlacement, availability: .pending, owner: .ar, sources: [.workspaceShooting, .arSession], entry: "surface confirmation is real", action: "place stable plan entities", recovery: "undo and retry placement", exit: "playback, storyboard, recording, interruption, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .validated, .required), artifact(.storyboard, .optional)], transitions: [edge(.arPlayback, .advance, "play selected plan"), edge(.storyboardResult, .advance, "open storyboard"), edge(.recordingReady, .advance, "prepare recording"), edge(.arInterruption, .recover, "session interruption"), edge(.arError, .recover, "session error"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arPlayback, availability: .pending, owner: .ar, sources: [.workspacePreviewPlayback, .arSession, .plannedScene], entry: "placed plan and selected beat are available", action: "play or stop the selected beat", recovery: "stop playback and return to placement", exit: "storyboard, recording, interruption, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .validated, .required), artifact(.storyboard, .optional)], transitions: [edge(.storyboardResult, .back, "open storyboard"), edge(.recordingReady, .advance, "prepare take"), edge(.arPlacement, .recover, "stop playback"), edge(.arInterruption, .recover, "session interruption"), edge(.arError, .recover, "session error"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arMarking, owner: .ar, sources: [.workspaceMarking, .arSession], entry: "user marking owner is active", action: "name or confirm a marked object", recovery: "cancel marker without persistence", exit: "placement, input context, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .draft, .required)], transitions: [edge(.arPlacement, .advance, "marker confirmed"), edge(.generatorInputMarkedDetected, .back, "return to generator context"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arLiveHints, availability: .pending, owner: .ar, sources: [.workspaceShooting, .arSession], entry: "current frame has an owner-linked hint", action: "inspect one actionable hint", recovery: "hide stale/unavailable hint", exit: "hint pause, hint playback, placement, interruption, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.decisionTrace, .optional)], transitions: [edge(.arHintPause, .advance, "pause hints"), edge(.arHintPlayback, .advance, "play explanation"), edge(.arPlacement, .back, "return to placement"), edge(.arInterruption, .recover, "session interruption"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arHintPause, owner: .ar, sources: [.workspaceShooting], entry: "one immutable hint pause is visible", action: "resume or inspect the paused hint", recovery: "discard stale pause and resume", exit: "live hints, hint playback, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.decisionTrace, .optional)], transitions: [edge(.arLiveHints, .recover, "resume live hints"), edge(.arHintPlayback, .advance, "inspect explanation"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arHintPlayback, owner: .ar, sources: [.workspacePreviewPlayback, .decisionTrace], entry: "one owner-linked explanation is selected", action: "play explanation once", recovery: "stop playback and retain source hint", exit: "live hints, placement, interruption, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.decisionTrace, .validated, .required), artifact(.arBindings, .validated, .required)], transitions: [edge(.arLiveHints, .back, "finish explanation"), edge(.arPlacement, .back, "close explanation"), edge(.arInterruption, .recover, "session interruption"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.recordingInProgress, availability: .pending, owner: .recording, sources: [.workspaceRecording, .recordingInProgress], entry: "recording owner is actively writing media", action: "stop this take", recovery: "cancel and leave an honest recoverable result", exit: "stopping, failure, interruption, or teardown", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingStopping, .advance, "stop requested"), edge(.recordingFailure, .recover, "writer failure"), edge(.arInterruption, .recover, "recording interruption"), edge(.arTeardown, .teardown, "route teardown")]),
            makeState(.recordingReview, owner: .recordingStore, sources: [.workspacePreviewPlayback, .recordingCompleted, .recordingArtifact], entry: "only a resolvable promoted artifact enters review", action: "play or invoke system export/share", recovery: "keep missing media disabled and retry promotion", exit: "exporting, storyboard, library, or teardown", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .optional)], transitions: [edge(.recordingExporting, .export, "export/share requested"), edge(.storyboardResult, .back, "return to storyboard"), edge(.librarySelected, .back, "return to library")]),
            makeState(.arInterruption, availability: .pending, owner: .ar, sources: [.arSession, .workspaceShooting, .recordingInProgress], entry: "AR session interruption invalidates live frame generation", action: "wait for post-interruption recovery", recovery: "stop recording/playback/hints and clear readiness", exit: "preparing, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .missing, .required), artifact(.recording, .pending, .optional)], transitions: [edge(.arPreparing, .recover, "post-interruption recovery"), edge(.arError, .recover, "interruption reports failure"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arError, availability: .pending, owner: .ar, sources: [.arSession], entry: "AR owner reports an honest error", action: "close or recover the session", recovery: "preserve project and do not claim live readiness", exit: "preparing, selected library, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .missing, .required), artifact(.recording, .missing, .optional)], transitions: [edge(.arPreparing, .recover, "retry session"), edge(.librarySelected, .back, "close workspace"), edge(.arTeardown, .teardown, "release session")]),
            makeState(.arTeardown, owner: .ar, sources: [.arSession, .scenePersistence], entry: "route/workspace teardown is requested", action: "pause session and await owner release", recovery: "retain project before dismiss", exit: "selected library only", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .missing, .required), artifact(.recording, .optional)], transitions: [edge(.librarySelected, .teardown, "teardown completes")]),

            // Storyboard and reachable sheets are projections over real domain
            // items; editor/validation/delete/trace remain typed owner edges.
            makeState(.storyboardTrayCollapsed, owner: .storyboard, sources: [.workspacePreviewPlayback, .storyboardProjection], entry: "storyboard projection has a selected beat", action: "expand tray or select beat", recovery: "show missing-link warning", exit: "expanded, reflow, result, inspector, or editor", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardTrayExpanded, .advance, "expand tray"), edge(.storyboardSelectionReflow, .advance, "select beat"), edge(.storyboardInspector, .advance, "inspect beat"), edge(.storyboardEditorMedium, .advance, "edit beat")]),
            makeState(.storyboardTrayExpanded, owner: .storyboard, sources: [.workspacePreviewPlayback, .storyboardProjection], entry: "readable beat tray is expanded", action: "select, inspect, or edit a beat", recovery: "collapse without mutating project", exit: "collapsed, reflow, result, inspector, or editor", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardTrayCollapsed, .back, "collapse tray"), edge(.storyboardSelectionReflow, .advance, "select beat"), edge(.storyboardInspector, .advance, "inspect beat"), edge(.storyboardEditorMedium, .advance, "edit beat")]),
            makeState(.storyboardSelectionReflow, owner: .storyboard, sources: [.workspacePreviewPlayback, .storyboardProjection], entry: "selection owner has a stable beat ID", action: "settle selected beat before editor", recovery: "return to prior selection", exit: "result, inspector, editor, or tray", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardResult, .advance, "selection settles"), edge(.storyboardInspector, .advance, "open inspector"), edge(.storyboardEditorMedium, .advance, "open editor"), edge(.storyboardTrayExpanded, .back, "selection cancelled")]),
            makeState(.storyboardResult, owner: .storyboard, sources: [.workspacePreviewPlayback, .storyboardProjection, .sceneScript, .plannedScene], entry: "real SceneScript/PlannedScene projection is available", action: "select, inspect, edit, or record", recovery: "show missing-link warning without fake thumbnail", exit: "tray, inspector, editor, AR placement, or recording", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .validated, .required), artifact(.preview, .optional), artifact(.recording, .missing, .optional)], transitions: [edge(.storyboardTrayCollapsed, .back, "collapse tray"), edge(.storyboardTrayExpanded, .advance, "expand tray"), edge(.storyboardSelectionReflow, .advance, "select beat"), edge(.storyboardInspector, .advance, "inspect beat"), edge(.storyboardEditorMedium, .advance, "edit beat"), edge(.arPlacement, .back, "return to AR"), edge(.recordingReady, .advance, "prepare recording")]),
            makeState(.storyboardInspector, owner: .storyboard, sources: [.storyboardProjection, .decisionTrace], entry: "selected beat metadata is linked", action: "inspect evidence or edit beat", recovery: "close inspector to result", exit: "result, trace, or editor", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .validated, .required), artifact(.decisionTrace, .optional)], transitions: [edge(.storyboardResult, .back, "close inspector"), edge(.sheetDecisionTrace, .advance, "open decision trace"), edge(.storyboardEditorMedium, .advance, "edit inspected beat")]),
            makeState(.storyboardEditorMedium, owner: .storyboardEditor, sources: [.workspaceEditing, .storyboardProjection], entry: "real beat draft opens at medium detent", action: "edit, save, or request delete", recovery: "discard unsaved draft only", exit: "large editor, saving, validation failure, delete, or result", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .draft, .required), artifact(.script, .validated, .required)], transitions: [edge(.storyboardEditorLarge, .advance, "expand editor"), edge(.storyboardSaving, .advance, "save draft"), edge(.storyboardValidationFailure, .recover, "validation fails"), edge(.storyboardDeleteConfirmation, .delete, "delete beat"), edge(.storyboardResult, .back, "cancel editor")]),
            makeState(.storyboardEditorLarge, owner: .storyboardEditor, sources: [.workspaceEditing, .storyboardProjection], entry: "real beat draft opens at large detent", action: "edit, save, or request delete", recovery: "return to medium without data loss", exit: "medium editor, saving, validation failure, delete, or result", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .draft, .required), artifact(.script, .validated, .required)], transitions: [edge(.storyboardEditorMedium, .back, "shrink editor"), edge(.storyboardSaving, .advance, "save draft"), edge(.storyboardValidationFailure, .recover, "validation fails"), edge(.storyboardDeleteConfirmation, .delete, "delete beat"), edge(.storyboardResult, .back, "cancel editor")]),
            makeState(.storyboardSaving, owner: .storyboardEditor, sources: [.workspaceEditing, .scenePersistence], entry: "one owner-side save is in flight", action: "await idempotent save", recovery: "keep draft and surface failure", exit: "result, editor, or validation failure", persistence: .draft, artifacts: [artifact(.project, .pending, .required), artifact(.storyboard, .pending, .required)], transitions: [edge(.storyboardResult, .advance, "save commits"), edge(.storyboardEditorMedium, .recover, "save returns editable draft"), edge(.storyboardValidationFailure, .recover, "save validates and rejects")]),
            makeState(.storyboardValidationFailure, owner: .storyboardEditor, sources: [.workspaceEditing, .storyboardProjection], entry: "typed invalid field is returned", action: "correct the field in editor", recovery: "retain draft and field reason", exit: "medium or large editor", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .draft, .required)], transitions: [edge(.storyboardEditorMedium, .recover, "return to medium editor"), edge(.storyboardEditorLarge, .recover, "return to large editor")]),
            makeState(.storyboardDeleteConfirmation, owner: .persistence, sources: [.workspaceEditing, .scenePersistence], entry: "selected beat identity is visible", action: "confirm or cancel deletion", recovery: "cancel without deleting beat", exit: "result or editor", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardResult, .delete, "confirmed delete"), edge(.storyboardEditorMedium, .cancel, "cancel delete")]),
            makeState(.sheetSceneName, owner: .libraryPersistence, sources: [.libraryCreating, .scenePersistence], entry: "library create-name sheet is open", action: "enter and confirm scene name", recovery: "close while retaining draft", exit: "create-name, duplicate, or selected", persistence: .draft, artifacts: [artifact(.project, .draft, .required), artifact(.input, .draft, .required)], transitions: [edge(.libraryCreateName, .back, "close sheet"), edge(.librarySelected, .advance, "create succeeds"), edge(.libraryDuplicateName, .recover, "duplicate name")]),
            makeState(.sheetMarkerName, owner: .ar, sources: [.workspaceMarking, .scenePersistence], entry: "selected mark awaits a name", action: "name or cancel marker", recovery: "discard unconfirmed mark", exit: "marking or placement", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .draft, .required)], transitions: [edge(.arMarking, .back, "close marker sheet"), edge(.arPlacement, .advance, "marker confirmed")]),
            makeState(.sheetScreenplayInput, owner: .generatorInput, sources: [.workspaceEditing, .keyboard], entry: "screenplay input sheet is open", action: "edit and submit screenplay", recovery: "close without dropping draft", exit: "input empty, editing, or invalid", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required)], transitions: [edge(.generatorInputEditing, .back, "close with text"), edge(.generatorInputEmpty, .recover, "close empty"), edge(.generatorInputInvalid, .recover, "submit invalid")]),
            makeState(.sheetDecisionTrace, owner: .trace, sources: [.decisionTrace, .storyboardProjection], entry: "decision trace is linked to selected beat", action: "inspect evidence and close", recovery: "hide trace if link is missing", exit: "inspector or result", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.decisionTrace, .validated, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardInspector, .back, "close trace"), edge(.storyboardResult, .back, "close to result")]),

            // RecordingLifecycleState: explicit stop/finalize/promote/finish,
            // cancellation/release, and system export without fake artifacts.
            makeState(.recordingIdle, owner: .recording, sources: [.recordingIdle], entry: "recording owner has no active take", action: "prepare a take", recovery: "remain idle", exit: "preparing, ready, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .missing, .required)], transitions: [edge(.recordingPreparing, .advance, "prepare capture"), edge(.recordingReady, .advance, "owner publishes ready"), edge(.recordingReleased, .teardown, "release idle owner")]),
            makeState(.recordingPreparing, owner: .recording, sources: [.recordingPreparing], entry: "capture format/permissions are preparing", action: "await recorder readiness", recovery: "return to idle on preparation failure", exit: "ready, failure, cancelled, or released", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingReady, .advance, "recorder ready"), edge(.recordingFailure, .recover, "preparation failure"), edge(.recordingCancelled, .cancel, "cancel preparation"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingReady, owner: .recording, sources: [.recordingReady, .workspaceRecording], entry: "capture format and links are ready", action: "start a take", recovery: "return to placement without artifact", exit: "starting, in-progress, cancelled, or failure", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.storyboard, .validated, .optional), artifact(.recording, .missing, .required)], transitions: [edge(.recordingStarting, .advance, "start take"), edge(.recordingInProgress, .advance, "atomic recorder start"), edge(.recordingCancelled, .cancel, "cancel before start"), edge(.recordingFailure, .recover, "start failure")]),
            makeState(.recordingStarting, owner: .recording, sources: [.recordingStarting], entry: "identity gate passed; writer/audio preparation is pending", action: "finish preparation or cancel", recovery: "return without publishing REC", exit: "in-progress, failure, cancelled, or released", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingInProgress, .advance, "writer starts"), edge(.recordingFailure, .recover, "writer/audio failure"), edge(.recordingCancelled, .cancel, "cancel start"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingStopping, owner: .recording, sources: [.recordingStopping], entry: "stop requested for active take", action: "finalize writer", recovery: "retain recoverable recorder result", exit: "finalizing, completed, failure, cancelled, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingFinalizing, .advance, "writer stops"), edge(.recordingCompleted, .advance, "atomic stop returns final"), edge(.recordingFailure, .recover, "stop failure"), edge(.recordingCancelled, .cancel, "cancel stop"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingFinalizing, owner: .recording, sources: [.recordingFinalizing], entry: "writer finalization is in flight", action: "await final media descriptor", recovery: "preserve pending/failure journal; never show completed", exit: "promoting, completed, failure, cancelled, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingPromoting, .advance, "finalization succeeds"), edge(.recordingCompleted, .advance, "finalization yields owned artifact"), edge(.recordingFailure, .recover, "finalization fails"), edge(.recordingCancelled, .cancel, "cancel finalization"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingPromoting, owner: .recordingStore, sources: [.recordingPromoting, .recordingArtifact], entry: "finalized descriptor is being promoted to project store", action: "complete one exclusive promotion", recovery: "retry without duplicate or absolute-path claim", exit: "completed, failure, cancelled, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingCompleted, .advance, "promotion succeeds"), edge(.recordingFailure, .recover, "promotion fails"), edge(.recordingCancelled, .cancel, "cancel promotion"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingCompleted, owner: .recordingStore, sources: [.recordingCompleted, .recordingArtifact], entry: "project-owned recording artifact resolves", action: "open review", recovery: "reopen newest resolvable artifact", exit: "review, exporting, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required)], transitions: [edge(.recordingReview, .advance, "open review"), edge(.recordingExporting, .export, "export/share requested"), edge(.recordingReleased, .teardown, "release artifact")]),
            makeState(.recordingFailure, owner: .recording, sources: [.recordingFailure], entry: "capture/finalize/promotion failed", action: "retry or return to ready", recovery: "preserve honest failure and any recoverable artifact", exit: "ready, finalizing, review, cancelled, or released", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .missing, .optional)], transitions: [edge(.recordingReady, .recover, "retry take"), edge(.recordingFinalizing, .retry, "retry finalization"), edge(.recordingReview, .recover, "recover resolvable artifact"), edge(.recordingCancelled, .cancel, "discard active take"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingCancelled, owner: .recording, sources: [.recordingCancelled], entry: "take was cancelled before promotion", action: "release recorder resources", recovery: "retain project and failure journal", exit: "released only", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .missing, .optional)], transitions: [edge(.recordingReleased, .teardown, "resource release completes")]),
            makeState(.recordingReleased, owner: .recording, sources: [.recordingReleased], entry: "recording owner has released take resources; any promoted artifact remains project-owned", action: "none; route may close", recovery: "start a new owner instance without deleting a promoted artifact", exit: "terminal", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .optional)], transitions: []),
            makeState(.recordingExporting, availability: .pending, owner: .export, sources: [.recordingCompleted, .recordingExport], entry: "system export/share is requested for a promoted artifact", action: "await system export result", recovery: "keep review playable and export retryable", exit: "exported, review, failure, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .pending, .required)], transitions: [edge(.recordingExported, .export, "system export succeeds"), edge(.recordingReview, .recover, "export cancelled"), edge(.recordingFailure, .recover, "export fails"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingExported, availability: .pending, owner: .export, sources: [.recordingCompleted, .recordingExport], entry: "system export returned a concrete result", action: "return to review or release", recovery: "retain source artifact when export result is absent", exit: "review or released", persistence: .release, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .promoted, .required)], transitions: [edge(.recordingReview, .back, "return to review"), edge(.recordingReleased, .teardown, "release export owner")])
        ]
    )

    func state(_ value: SceneJourneyState) -> SceneJourneyStateContract? {
        states.first { $0.state == value }
    }

    func allows(_ from: SceneJourneyState, _ to: SceneJourneyState) -> Bool {
        state(from)?.transitions.contains { $0.to == to } == true
    }

    func validate() -> Bool {
        let ids = states.map(\.id)
        let canonicalIDs = Set(SceneJourneyState.canonicalStateIDs)
        guard states.count == canonicalIDs.count,
              Set(ids).count == ids.count,
              Set(ids) == canonicalIDs else { return false }

        let vocabulary = Set(sourceVocabulary)
        guard sourceVocabulary.count == vocabulary.count, !vocabulary.isEmpty else { return false }
        let knownStates = Set(ids)
        for state in states {
            guard !state.sourceStates.isEmpty,
                  state.sourceStates.allSatisfy(vocabulary.contains),
                  !state.entry.isEmpty,
                  !state.primaryAction.isEmpty,
                  !state.recovery.isEmpty,
                  !state.exit.isEmpty,
                  !state.artifacts.isEmpty else { return false }

            let artifactIDs = state.artifacts.map(\.id)
            guard Set(artifactIDs).count == artifactIDs.count else { return false }
            guard state.transitions.allSatisfy({
                $0.to != state.state && knownStates.contains($0.to.id) && !$0.trigger.isEmpty
            }) else { return false }
        }
        return state(.recordingReleased)?.transitions.isEmpty == true
    }
}

enum SceneBundleParseMode: String, Codable, Equatable {
    case full
    case append
}

enum NormalizedScriptUnitKind: String, Codable, Equatable {
    case sceneHeading = "scene_heading"
    case speakerCue = "speaker_cue"
    case parenthetical = "parenthetical"
    case dialogue = "dialogue"
    case screenText = "screen_text"
    case stageNote = "stage_note"
    case actionLine = "action_line"
    case proseLine = "prose_line"
    case blank
}

struct ScriptOffsetRange: Codable, Equatable {
    var start: Int
    var end: Int
}

struct NormalizedScriptUnit: Codable, Equatable, Identifiable {
    var id: String
    var kind: NormalizedScriptUnitKind
    var text: String
    var lineIndex: Int
    var charRange: ScriptOffsetRange
}

struct ScriptSceneCandidate: Codable, Equatable, Identifiable {
    var id: String
    var sceneIndex: Int
    var heading: String?
    var unitRange: Range<Int>
    var sourceRange: ScriptOffsetRange
    var sourceText: String
    var metadata: SceneTopLevelMetadata
    var isImplicit: Bool
    var isMontage: Bool = false
}

struct SceneVisualOverlay: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case screenText = "screen_text"
        case stageNote = "stage_note"
    }

    var id: String
    var kind: Kind
    var text: String
    var sceneID: String
    var sourceRange: ScriptOffsetRange
    var displayOrder: Int
    var beatID: String?
}

struct SceneChunkAnchor: Codable, Equatable {
    var sourceBundle: SourceAnchorBundle
    var speakerCues: [String]
    var actorMentions: [String]
    var objectMentions: [String]
    var markedObjectMentions: [String]
    var pronounMentions: [String]
    var chronologyCues: [String]
    var locationCues: [String]
    var timeCues: [String]
    var uncertaintyFlags: [String]

    static let empty = SceneChunkAnchor(
        sourceBundle: .empty,
        speakerCues: [],
        actorMentions: [],
        objectMentions: [],
        markedObjectMentions: [],
        pronounMentions: [],
        chronologyCues: [],
        locationCues: [],
        timeCues: [],
        uncertaintyFlags: []
    )
}

struct SceneEntityRegistrySnapshot: Codable, Equatable {
    var actors: [ScenePlanIR.Actor]
    var objects: [ScenePlanIR.Object]
    var actorAliasMap: [String: String]
    var objectAliasMap: [String: String]
    var speakerAliasMap: [String: String]
    var unresolvedMentions: [String]
    var lastResolvedSpeaker: String?
    var locationName: String?
    var actorPoses: [String: ActorPose]
    var heldObjects: [String: String]
    var previousChunkSummary: String? = nil
    var openBeatContext: String? = nil
    var lastActorPositions: [String: String] = [:]

    static let empty = SceneEntityRegistrySnapshot(
        actors: [],
        objects: [],
        actorAliasMap: [:],
        objectAliasMap: [:],
        speakerAliasMap: [:],
        unresolvedMentions: [],
        lastResolvedSpeaker: nil,
        locationName: nil,
        actorPoses: [:],
        heldObjects: [:],
        previousChunkSummary: nil,
        openBeatContext: nil,
        lastActorPositions: [:]
    )
}

struct SceneDeferredRef: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        case actor
        case object
    }

    var id: String
    var localRef: String
    var kind: Kind
    var alias: String?
    var sourceText: String?
}

struct SceneChunkDraft: Codable, Equatable, Identifiable {
    var id: String { chunkID }
    var sceneID: String
    var chunkID: String
    var chunkIndex: Int
    var sourceText: String
    var sourceRange: ScriptOffsetRange
    var anchors: SceneChunkAnchor
    var registrySnapshot: SceneEntityRegistrySnapshot
    var plan: ScenePlanIR
    var usedFallbackPlanner: Bool
    var usedLegacyPlanBridge: Bool
    var confidence: Float
    var unresolvedMentions: [String]
    var reasonCodes: [String]
}

struct SceneChunkStateDelta: Codable, Equatable {
    var locationUpdate: String?
    var actorPoseUpdates: [String: ActorPose]
    var heldObjectUpdates: [String: String]
    var releasedObjects: [String]
    var previousChunkSummary: String? = nil
    var openBeatContext: String? = nil
    var lastActorPositions: [String: String] = [:]

    static let empty = SceneChunkStateDelta(
        locationUpdate: nil,
        actorPoseUpdates: [:],
        heldObjectUpdates: [:],
        releasedObjects: [],
        previousChunkSummary: nil,
        openBeatContext: nil,
        lastActorPositions: [:]
    )
}

struct SceneChunk: Codable, Equatable, Identifiable {
    struct RegistryPatch: Codable, Equatable {
        var actors: [ScenePlanIR.Actor]
        var objects: [ScenePlanIR.Object]
        var actorAliasMap: [String: String]
        var objectAliasMap: [String: String]
        var speakerAliasMap: [String: String]

        static let empty = RegistryPatch(
            actors: [],
            objects: [],
            actorAliasMap: [:],
            objectAliasMap: [:],
            speakerAliasMap: [:]
        )
    }

    var id: String { chunkID }
    var sceneID: String
    var chunkID: String
    var chunkIndex: Int
    var sourceText: String
    var sourceRange: ScriptOffsetRange
    var anchors: SceneChunkAnchor
    var registryPatch: RegistryPatch
    var beatPatch: [ScenePlanIR.Beat]
    var spatialRelationPatch: [ScenePlanIR.SpatialRelation]
    var stateDelta: SceneChunkStateDelta
    var deferredRefs: [SceneDeferredRef]
    var reasonCodes: [String]
    var usedFallbackPlanner: Bool
    var usedLegacyPlanBridge: Bool
}

struct SceneStitchState: Codable, Equatable, Identifiable {
    var id: String { sceneID }
    var sceneID: String
    var sceneIndex: Int
    var sourceText: String
    var metadata: SceneTopLevelMetadata
    var registry: SceneEntityRegistrySnapshot
    var actors: [ScenePlanIR.Actor]
    var objects: [ScenePlanIR.Object]
    var beats: [ScenePlanIR.Beat]
    var spatialRelations: [ScenePlanIR.SpatialRelation]
    var chunkLedger: [String]
    var deferredRefs: [SceneDeferredRef]
    var continuityDiagnostics: [String]

    init(
        sceneID: String,
        sceneIndex: Int,
        sourceText: String,
        metadata: SceneTopLevelMetadata,
        registry: SceneEntityRegistrySnapshot = .empty,
        actors: [ScenePlanIR.Actor] = [],
        objects: [ScenePlanIR.Object] = [],
        beats: [ScenePlanIR.Beat] = [],
        spatialRelations: [ScenePlanIR.SpatialRelation] = [],
        chunkLedger: [String] = [],
        deferredRefs: [SceneDeferredRef] = [],
        continuityDiagnostics: [String] = []
    ) {
        self.sceneID = sceneID
        self.sceneIndex = sceneIndex
        self.sourceText = sourceText
        self.metadata = metadata
        self.registry = registry
        self.actors = actors
        self.objects = objects
        self.beats = beats
        self.spatialRelations = spatialRelations
        self.chunkLedger = chunkLedger
        self.deferredRefs = deferredRefs
        self.continuityDiagnostics = continuityDiagnostics
    }
}

struct SceneBundlePlan: Codable, Equatable {
    struct SceneEntry: Codable, Equatable, Identifiable {
        var id: String { sceneID }
        var sceneID: String
        var sceneIndex: Int
        var sourceText: String
        var metadata: SceneTopLevelMetadata
        var chunks: [SceneChunk]
        var diagnostics: [String]
        var plan: ScenePlanIR
    }

    var bundleID: String
    var scenes: [SceneEntry]
    var activeSceneIndex: Int
    var visualOverlays: [SceneVisualOverlay] = []
    var diagnostics: [String]
}

struct SceneBundleScript: Codable, Equatable {
    var bundleID: String
    var scenes: [SceneScript]
    var activeSceneIndex: Int
    var visualOverlays: [SceneVisualOverlay] = []
    var diagnostics: [String]

    var activeSceneScript: SceneScript? {
        guard scenes.indices.contains(activeSceneIndex) else { return scenes.last }
        return scenes[activeSceneIndex]
    }

    var activeSceneID: String? {
        activeSceneScript?.sceneHeading ?? activeSceneScript?.locationName
    }
}

struct SceneChunkDiagnostics: Codable, Equatable, Identifiable {
    var id: String { chunkID }
    var sceneID: String
    var chunkID: String
    var chunkIndex: Int
    var reasonCodes: [String]
    var unresolvedRefs: [String]
    var anchors: SceneChunkAnchor
    var usedFallbackPlanner: Bool
    var usedLegacyPlanBridge: Bool
}

struct ScriptDocumentState: Codable, Equatable {
    var documentID: String
    var mode: SceneBundleParseMode
    var sourceText: String
    var normalizedUnits: [NormalizedScriptUnit]
    var sceneCandidates: [ScriptSceneCandidate]
    var stitchStates: [SceneStitchState]
    var bundlePlan: SceneBundlePlan
    var bundleScript: SceneBundleScript
    var activeSceneIndex: Int
    var visualOverlays: [SceneVisualOverlay] = []
}

struct SceneBundleParsingResult: Equatable {
    var bundleScript: SceneBundleScript
    var activeSceneScript: SceneScript?
    var activeSceneId: String?
    var sceneChunks: [SceneChunk]
    var visualOverlays: [SceneVisualOverlay] = []
    var documentState: ScriptDocumentState
    var diagnostics: ParsingDiagnostics
    var chunkDiagnostics: [SceneChunkDiagnostics]
    var executionTrace: SceneExecutionTrace?
}
