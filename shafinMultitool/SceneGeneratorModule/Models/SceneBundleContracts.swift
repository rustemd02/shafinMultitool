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
    case libraryRenameDuplicateName = "library.rename-duplicate-name"
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
    case generatorValidating = "generator.validating"
    case generatorAccepted = "generator.accepted"
    case generatorQueued = "generator.queued"
    case generatorLeader = "generator.leader"
    case generatorProgressReading = "generator.progress-reading"
    case generatorProgressAnchors = "generator.progress-anchors"
    case generatorProgressFrame = "generator.progress-frame"
    case generatorCancelling = "generator.cancelling"
    case generatorPaused = "generator.paused"
    case generatorBackgroundCancel = "generator.background-cancel"
    case generatorFailureParse = "generator.failure-parse"
    case generatorFailureQuota = "generator.failure-quota"
    case generatorFailureMalformed = "generator.failure-malformed"
    case generatorFailurePersistence = "generator.failure-persistence"
    case generatorFailureNetwork = "generator.failure-network"
    case generatorFailureModel = "generator.failure-model"
    case generatorRetry = "generator.retry"
    case generatorBackgroundRecovery = "generator.background-recovery"
    case generatorFailureTimeout = "generator.failure-timeout"
    case generatorFailureCompilation = "generator.failure-compilation"
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
    case arRelocalization = "ar.relocalization"
    case arReset = "ar.reset"
    case arWorldMapRecovery = "ar.world-map-recovery"
    case arTeardown = "ar.teardown"

    // Visual Policy v2.6: Storyboard.
    case storyboardTrayCollapsed = "storyboard.tray-collapsed"
    case storyboardTrayExpanded = "storyboard.tray-expanded"
    case storyboardSelectionReflow = "storyboard.selection-reflow"
    case storyboardPlanning = "storyboard.planning"
    case storyboardValidation = "storyboard.validation"
    case storyboardResult = "storyboard.result"
    case storyboardInspector = "storyboard.inspector"
    case storyboardEditorMedium = "storyboard.editor-medium"
    case storyboardEditorLarge = "storyboard.editor-large"
    case storyboardSaving = "storyboard.saving"
    case storyboardReorder = "storyboard.reorder"
    case storyboardProjectionValidationFailure = "storyboard.projection-validation-failure"
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
    case recordingPreflight = "recording.preflight"
    case recordingPermission = "recording.permission"
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
    case recordingPlayback = "recording.playback"
    case recordingRecovery = "recording.recovery"
    case recordingShare = "recording.share"
    case recordingExporting = "recording.exporting"
    case recordingExported = "recording.exported"
    case recordingExportCancelled = "recording.export-cancelled"
    case recordingExportFailure = "recording.export-failure"
    case recordingPhotosExporting = "recording.photos-exporting"
    case recordingPhotosExported = "recording.photos-exported"
    case recordingPhotosExportCancelled = "recording.photos-export-cancelled"
    case recordingPhotosExportFailure = "recording.photos-export-failure"

    var id: String { rawValue }

    /// The subset of journey states backed directly by the canonical recorder
    /// lifecycle. Presentation, export, and recovery states intentionally
    /// return nil so crossing into them must be an explicitly outer edge.
    var recordingLifecycleState: RecordingLifecycleState? {
        switch self {
        case .recordingIdle: .idle
        case .recordingPreparing: .preparing
        case .recordingReady: .ready
        case .recordingStarting: .starting
        case .recordingInProgress: .recording
        case .recordingStopping: .stopping
        case .recordingFinalizing: .finalizing
        case .recordingPromoting: .promoting
        case .recordingCompleted: .completed
        case .recordingFailure: .failed
        case .recordingCancelled: .cancelled
        case .recordingReleased: .released
        default: nil
        }
    }

    /// Deliberately independent from `CaseIterable`: this is the frozen 1.0
    /// identity set that a custom contract must exactly reproduce.
    static let canonicalStateIDs: [String] = [
        "library.empty", "library.contact-sheet", "library.selected", "library.rename-name",
        "library.rename-duplicate-name", "library.missing-preview", "library.create-name", "library.duplicate-name", "library.delete-confirmation",
        "library.persistence-failure", "generator.input-empty", "generator.input-editing",
        "generator.input-keyboard", "generator.input-marked-detected", "generator.input-invalid",
        "generator.clarification", "generator.validating", "generator.accepted", "generator.queued", "generator.leader",
        "generator.progress-reading", "generator.progress-anchors", "generator.progress-frame",
        "generator.cancelling", "generator.paused", "generator.background-cancel", "generator.failure-parse",
        "generator.failure-quota", "generator.failure-malformed", "generator.failure-persistence", "generator.failure-network",
        "generator.failure-model", "generator.retry", "generator.background-recovery", "generator.failure-timeout",
        "generator.failure-compilation", "generator.success", "ar.preparing",
        "ar.ready", "ar.surface-search", "ar.placement", "ar.playback", "ar.marking",
        "ar.live-hints", "ar.hint-pause", "ar.hint-playback", "ar.recording",
        "ar.recording-review", "ar.interruption", "ar.error", "ar.relocalization", "ar.reset",
        "ar.world-map-recovery", "ar.teardown",
        "storyboard.tray-collapsed", "storyboard.tray-expanded", "storyboard.selection-reflow",
        "storyboard.planning", "storyboard.validation", "storyboard.result", "storyboard.inspector", "storyboard.editor-medium",
        "storyboard.editor-large", "storyboard.saving", "storyboard.reorder", "storyboard.projection-validation-failure", "storyboard.validation-failure",
        "storyboard.delete-confirmation", "sheet.scene-name", "sheet.marker-name",
        "sheet.screenplay-input", "sheet.decision-trace", "recording.idle", "recording.preflight", "recording.permission",
        "recording.preparing", "recording.ready", "recording.starting", "recording.stopping", "recording.finalizing",
        "recording.promoting", "recording.completed", "recording.failed", "recording.cancelled",
        "recording.released", "recording.playback", "recording.recovery", "recording.share", "recording.exporting", "recording.exported",
        "recording.export-cancelled", "recording.export-failure", "recording.photos-exporting", "recording.photos-exported",
        "recording.photos-export-cancelled", "recording.photos-export-failure"
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
    case libraryRenameDuplicate = "SETLibraryModel.FlowState.duplicate + rename operation"
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
    case generationValidating = "planned: SceneGeneratorViewModel validation owner"
    case generationQueued = "planned: SceneGeneratorViewModel queued request owner"
    case generationCancelling = "planned: SceneGeneratorViewModel cancellation owner"
    case generationPaused = "planned: SceneGeneratorViewModel paused request owner"
    case generationQuotaFailure = "planned: SceneGeneratorViewModel quota failure owner"
    case generationMalformedFailure = "planned: SceneGeneratorViewModel malformed-result owner"
    case generationPersistenceFailure = "planned: SceneGeneratorViewModel persistence failure owner"
    case generationBackgroundRecovery = "planned: SceneGeneratorViewModel background recovery owner"
    case generationTimeout = "planned: SceneGeneratorViewModel timeout failure owner"
    case generationCompilationFailure = "planned: SceneGeneratorViewModel compilation failure owner"
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
    case recordingPreflight = "planned: SceneRecordingController preflight owner"
    case recordingPermission = "planned: AVAudioSession/AVCaptureDevice permission owner"
    case recordingPlayback = "LegacySceneGeneratorCameraShell playback owner"
    case recordingRecovery = "planned: SceneRecordingController recovery owner"
    case recordingShare = "LegacySceneGeneratorCameraShell/UIActivityViewController share owner"
    case recordingPhotosExport = "planned: PHPhotoLibrary/Photos export owner (future M7-028)"
    case sceneScript = "SceneScript"
    case plannedScene = "PlannedScene"
    case recordingArtifact = "RecordingArtifact"
    case arSession = "ARSceneContainer"
    case arRelocalization = "planned: ARSceneContainer relocalization recovery owner"
    case arReset = "planned: ARSceneContainer session reset owner"
    case arWorldMapRecovery = "planned: ARSceneContainer world-map/anchor recovery owner"
    case storyboardProjection = "SceneGeneratorViewModel.storyboardBeatItems"
    case decisionTrace = "DecisionTraceView"
    case keyboard = "system keyboard owner"
    case scenePersistence = "UnifiedSceneProject persistence owner"
    case recordingExport = "planned: share result hand-off"
}

enum SceneJourneyOwner: String, Codable, Equatable {
    case library = "SETLibraryModel"
    case libraryPersistence = "SETLibraryModel + scene persistence owner"
    case generator = "SceneGeneratorViewModel"
    case generatorInput = "SceneInputSheet + SceneGeneratorViewModel"
    case generatorExecution = "SceneGeneratorViewModel generation owner"
    case generatorPersistence = "SceneGeneratorViewModel + scene persistence owner"
    case generatorStateMachine = "planned: SceneGeneratorViewModel generation state-machine owner"
    case generatorRecovery = "planned: SceneGeneratorViewModel background/recovery owner"
    case generatorTimeout = "planned: SceneGeneratorViewModel timeout owner"
    case generatorCompilation = "planned: SceneGeneratorViewModel compilation owner"
    case ar = "ARSceneContainer + AR session owner"
    case arRecovery = "planned: ARSceneContainer relocalization/reset/world-map owner"
    case storyboard = "SceneGeneratorViewModel storyboard owner"
    case storyboardEditor = "SceneGeneratorViewModel storyboard editor owner"
    case recording = "SceneRecordingController + RecordingLifecycleOwner"
    case recordingStore = "RecordingArtifactStore"
    case recordingPlayback = "LegacySceneGeneratorCameraShell playback owner"
    case photosExport = "planned: PHPhotoLibrary/Photos export owner (future M7-028)"
    case persistence = "scene persistence owner"
    case keyboard = "system keyboard owner"
    case trace = "DecisionTraceView + SceneGeneratorViewModel"
    /// Current share owner. Photos export is deliberately a separate future
    /// owner below so the two external hand-offs cannot be conflated.
    case export = "LegacySceneGeneratorCameraShell/UIActivityViewController share owner"
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
    case release = "project + retained recording source + external export receipt"
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
    case recordingExport = "recording export/share hand-off"
    case photosExportReceipt = "Photos export receipt"
    case preview = "real preview or metadata"
    case generationJob = "generation request"
    case worldMap = "ARWorldMap/anchor graph"
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
    /// Crosses from/to a lifecycle-backed state without asserting a recorder
    /// lifecycle transition (for example, route teardown or review).
    case outerNavigation = "outer-navigation"
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
    let entryStates: [SceneJourneyState]

    init(
        sourceVocabulary: [SceneJourneySourceState],
        states: [SceneJourneyStateContract],
        entryStates: [SceneJourneyState] = [.libraryEmpty, .libraryLoaded]
    ) {
        self.sourceVocabulary = sourceVocabulary
        self.states = states
        self.entryStates = entryStates
    }

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
            makeState(.libraryRenameName, availability: .pending, owner: .libraryPersistence, sources: [.librarySelected, .scenePersistence], entry: "selected scene name is being edited", action: "confirm or cancel rename", recovery: "preserve the old name and project ID", exit: "selected, rename duplicate, or failure", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.preview, .optional)], transitions: [edge(.librarySelected, .advance, "rename commits"), edge(.libraryRenameDuplicateName, .recover, "rename conflicts"), edge(.libraryPersistenceFailure, .recover, "rename persistence failure")]),
            makeState(.libraryRenameDuplicateName, availability: .pending, owner: .libraryPersistence, sources: [.libraryRenameDuplicate], entry: "rename persistence reports an existing name", action: "correct the conflicting rename", recovery: "return to the active rename draft", exit: "rename-name, selected, or failure", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.preview, .optional)], transitions: [edge(.libraryRenameName, .recover, "edit rename"), edge(.librarySelected, .cancel, "cancel rename"), edge(.libraryPersistenceFailure, .recover, "rename persistence failure")]),
            makeState(.libraryMissingPreview, availability: .pending, owner: .library, sources: [.librarySelected, .scenePersistence], entry: "selected row has no resolvable preview", action: "continue with truthful metadata or reload", recovery: "keep row identity and never fabricate a thumbnail", exit: "selected, generator input, or loaded", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.preview, .missing, .required), artifact(.input, .optional), artifact(.script, .optional)], transitions: [edge(.librarySelected, .recover, "metadata fallback acknowledged"), edge(.generatorInputEmpty, .advance, "open without preview"), edge(.libraryLoaded, .back, "reload library")]),
            makeState(.libraryCreateName, owner: .libraryPersistence, sources: [.libraryCreating], entry: "create flow owns a name draft", action: "confirm or cancel scene creation", recovery: "edit name without losing draft", exit: "name sheet, selected, duplicate, failure, or loaded", persistence: .draft, artifacts: [artifact(.project, .draft, .required), artifact(.input, .draft, .required), artifact(.preview, .missing)], transitions: [edge(.sheetSceneName, .advance, "open scene name sheet"), edge(.librarySelected, .advance, "create succeeds and opens project"), edge(.libraryDuplicateName, .recover, "duplicate name result"), edge(.libraryPersistenceFailure, .recover, "create persistence failure"), edge(.libraryLoaded, .cancel, "cancel create")]),
            makeState(.libraryDuplicateName, owner: .libraryPersistence, sources: [.libraryDuplicate], entry: "create persistence reports an existing name", action: "correct the conflicting create name", recovery: "return to the active create draft", exit: "create-name or loaded", persistence: .draft, artifacts: [artifact(.project, .missing, .required), artifact(.input, .draft, .required), artifact(.preview, .missing)], transitions: [edge(.libraryCreateName, .recover, "edit create name"), edge(.libraryLoaded, .cancel, "cancel duplicate flow")]),
            makeState(.libraryDeleteConfirmation, owner: .libraryPersistence, sources: [.libraryDeleting, .librarySelected], entry: "selected project identity is visible", action: "confirm or cancel deletion", recovery: "cancel without deleting identity", exit: "loaded or failure", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.preview, .optional)], transitions: [edge(.libraryLoaded, .delete, "confirmed deletion"), edge(.librarySelected, .cancel, "cancel deletion"), edge(.libraryPersistenceFailure, .recover, "delete persistence failure")]),
            makeState(.libraryPersistenceFailure, owner: .libraryPersistence, sources: [.libraryFailure, .scenePersistence], entry: "create/delete/open/rename persistence failed", action: "retry the named operation", recovery: "preserve selection and draft; never claim success", exit: "loaded, selected, empty, create-name, rename-name, or rename duplicate", persistence: .project, artifacts: [artifact(.project, .pending, .required), artifact(.input, .draft, .optional), artifact(.preview, .missing)], transitions: [edge(.libraryLoaded, .retry, "retry reload"), edge(.librarySelected, .recover, "retry open/delete restores selection"), edge(.libraryEmpty, .recover, "retry confirms empty"), edge(.libraryCreateName, .recover, "retry create restores draft"), edge(.libraryRenameName, .recover, "retry rename restores draft"), edge(.libraryRenameDuplicateName, .recover, "retry rename duplicate restores draft")]),

            // Generator: input, execution, truthful progress, cancellation,
            // and typed failure rows.
            makeState(.generatorInputEmpty, owner: .generatorInput, sources: [.workspaceEditing, .sceneScript], entry: "selected project has empty screenplay input", action: "enter screenplay text", recovery: "return to selected library row", exit: "editing, screenplay sheet, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .missing, .required), artifact(.script, .missing, .required), artifact(.plannedScene, .missing)], transitions: [edge(.generatorInputEditing, .advance, "text becomes nonempty"), edge(.sheetScreenplayInput, .advance, "open screenplay sheet"), edge(.librarySelected, .back, "close generator")]),
            makeState(.generatorInputEditing, owner: .generatorInput, sources: [.workspaceEditing, .sceneScript], entry: "screenplay draft is being edited", action: "submit one draft to the owner", recovery: "keep editable draft", exit: "keyboard, marked/detected, invalid, validating, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required), artifact(.plannedScene, .missing)], transitions: [edge(.generatorInputKeyboard, .advance, "focus input"), edge(.generatorInputMarkedDetected, .advance, "mark/detect context"), edge(.generatorInputInvalid, .recover, "local validation rejects input"), edge(.generatorValidating, .advance, "submit draft for validation"), edge(.librarySelected, .back, "close generator")]),
            makeState(.generatorInputKeyboard, owner: .keyboard, sources: [.workspaceEditing, .keyboard], entry: "screenplay field has system keyboard focus", action: "edit or paste without losing context", recovery: "dismiss keyboard and restore focus", exit: "editing or empty", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required)], transitions: [edge(.generatorInputEditing, .back, "keyboard dismissed"), edge(.generatorInputEmpty, .recover, "draft becomes empty")]),
            makeState(.generatorInputMarkedDetected, owner: .generator, sources: [.workspaceEditing, .workspaceMarking, .arSession], entry: "draft is accompanied by real mark/detection projections", action: "inspect context or submit draft", recovery: "retain draft when AR context is unavailable", exit: "editing, validating, or AR marking", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.arBindings, .optional)], transitions: [edge(.generatorInputEditing, .back, "return to editor"), edge(.generatorValidating, .advance, "submit with context"), edge(.arMarking, .advance, "open marking owner")]),
            makeState(.generatorInputInvalid, owner: .generatorInput, sources: [.workspaceEditing, .sceneScript], entry: "owner exposes input-local validation failure", action: "correct the invalid field", recovery: "keep text and field-level reason", exit: "editing, empty, or parse failure", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .missing, .required)], transitions: [edge(.generatorInputEditing, .recover, "correct text"), edge(.generatorInputEmpty, .recover, "clear text"), edge(.generatorFailureParse, .recover, "parser reports failure")]),
            makeState(.generatorClarification, availability: .pending, owner: .generatorExecution, sources: [.generationReading, .sceneScript], entry: "only a typed parser clarification result may enter", action: "answer the structured question", recovery: "cancel to the same draft", exit: "editing or accepted", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required)], transitions: [edge(.generatorInputEditing, .recover, "answer/cancel question"), edge(.generatorAccepted, .advance, "clarification resolves")]),
            makeState(.generatorValidating, availability: .pending, owner: .generatorStateMachine, sources: [.generationValidating, .sceneScript], entry: "one submitted draft is being classified", action: "validate and classify the request", recovery: "return field reasons to the draft", exit: "clarification, accepted, parse, malformed, quota, persistence, timeout, compilation, or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required)], transitions: [edge(.generatorClarification, .recover, "typed clarification result"), edge(.generatorAccepted, .advance, "validation succeeds"), edge(.generatorFailureParse, .recover, "parser rejects input"), edge(.generatorFailureMalformed, .recover, "result is malformed"), edge(.generatorFailureQuota, .recover, "quota is exhausted"), edge(.generatorFailurePersistence, .recover, "draft persistence fails"), edge(.generatorFailureCompilation, .recover, "compile preflight fails"), edge(.generatorFailureTimeout, .recover, "validation times out"), edge(.generatorInputEditing, .back, "edit before acceptance")]),
            makeState(.generatorAccepted, availability: .pending, owner: .generatorStateMachine, sources: [.generationPlanning, .sceneScript], entry: "owner accepted one validated request", action: "enqueue one idempotent generation", recovery: "cancel before work starts", exit: "queued, retry, input, or cancelling", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorQueued, .advance, "accepted request enqueued"), edge(.generatorRetry, .retry, "bounded enqueue retry"), edge(.generatorCancelling, .cancel, "cancel before work")]),
            makeState(.generatorQueued, availability: .pending, owner: .generatorStateMachine, sources: [.generationQueued], entry: "request has a stable idempotency key and is queued", action: "start, pause, or cancel one request", recovery: "retain the same request identity", exit: "leader, paused, cancelling, timeout, or failure", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorLeader, .advance, "worker starts"), edge(.generatorPaused, .recover, "route leaves foreground"), edge(.generatorCancelling, .cancel, "cancel queued request"), edge(.generatorFailureQuota, .recover, "quota rejects queued request"), edge(.generatorFailurePersistence, .recover, "queue persistence fails"), edge(.generatorFailureTimeout, .recover, "queue times out")]),
            makeState(.generatorLeader, availability: .pending, owner: .generatorStateMachine, sources: [.generationPlanning], entry: "accepted request has a single leader event", action: "show leader once and begin work", recovery: "cancel or pause the same request", exit: "progress, paused, cancelling, background recovery, timeout, or failure", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorProgressReading, .advance, "leader completes"), edge(.generatorPaused, .recover, "route leaves foreground"), edge(.generatorCancelling, .cancel, "cancel request"), edge(.generatorBackgroundCancel, .cancel, "route/background cancellation"), edge(.generatorFailureTimeout, .recover, "leader times out")]),
            makeState(.generatorPaused, availability: .pending, owner: .generatorStateMachine, sources: [.generationPaused], entry: "one request is paused while preserving its identity", action: "resume or cancel the same request", recovery: "reconcile without a duplicate job", exit: "queued, progress, cancelling, or background recovery", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorQueued, .recover, "resume queued request"), edge(.generatorProgressReading, .recover, "resume active stage"), edge(.generatorCancelling, .cancel, "cancel paused request"), edge(.generatorBackgroundCancel, .cancel, "teardown while paused")]),
            makeState(.generatorCancelling, availability: .pending, owner: .generatorStateMachine, sources: [.generationCancelling], entry: "one generation cancellation is in flight", action: "await cancellation and join the owner task", recovery: "retain the prior committed scene and editable draft", exit: "input, selected library, background cancel, or recovery", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorInputEditing, .cancel, "cancellation completes"), edge(.librarySelected, .teardown, "workspace closes"), edge(.generatorBackgroundCancel, .teardown, "owner teardown remains pending")]),
            makeState(.generatorProgressReading, availability: .pending, owner: .generatorStateMachine, sources: [.generationReading], entry: "owner publishes reading stage", action: "consume truthful stage only", recovery: "cancel or classify error", exit: "anchors, failure, or paused/background-cancel", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .pending, .required)], transitions: [edge(.generatorProgressAnchors, .advance, "reading completes"), edge(.generatorFailureParse, .recover, "parse failure"), edge(.generatorFailureNetwork, .recover, "network failure"), edge(.generatorFailureModel, .recover, "model failure"), edge(.generatorFailureQuota, .recover, "quota failure"), edge(.generatorFailurePersistence, .recover, "persistence failure"), edge(.generatorFailureTimeout, .recover, "execution timeout"), edge(.generatorPaused, .recover, "route leaves foreground"), edge(.generatorBackgroundCancel, .cancel, "background/cancel")]),
            makeState(.generatorProgressAnchors, availability: .pending, owner: .generatorStateMachine, sources: [.generationPlacing], entry: "owner publishes anchor stage", action: "consume truthful anchor progress", recovery: "cancel or classify error", exit: "frame, failure, or paused/background-cancel", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .pending, .required)], transitions: [edge(.generatorProgressFrame, .advance, "anchors complete"), edge(.generatorFailureNetwork, .recover, "network failure"), edge(.generatorFailureModel, .recover, "model failure"), edge(.generatorFailureQuota, .recover, "quota failure"), edge(.generatorFailurePersistence, .recover, "persistence failure"), edge(.generatorFailureTimeout, .recover, "execution timeout"), edge(.generatorPaused, .recover, "route leaves foreground"), edge(.generatorBackgroundCancel, .cancel, "background/cancel")]),
            makeState(.generatorProgressFrame, availability: .pending, owner: .generatorStateMachine, sources: [.generationPlanning, .generationPlacing], entry: "owner publishes frame stage", action: "wait for a committed result", recovery: "cancel or classify error", exit: "success, failure, or paused/background-cancel", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .pending, .required)], transitions: [edge(.generatorSuccess, .advance, "plan commits"), edge(.generatorFailureNetwork, .recover, "network failure"), edge(.generatorFailureModel, .recover, "model failure"), edge(.generatorFailureQuota, .recover, "quota failure"), edge(.generatorFailurePersistence, .recover, "persistence failure"), edge(.generatorFailureCompilation, .recover, "plan compilation fails"), edge(.generatorFailureTimeout, .recover, "execution timeout"), edge(.generatorPaused, .recover, "route leaves foreground"), edge(.generatorBackgroundCancel, .cancel, "background/cancel")]),
            makeState(.generatorBackgroundCancel, availability: .pending, owner: .generatorStateMachine, sources: [.generationReading, .sceneScript], entry: "request leaves foreground or is cancelled", action: "reconcile the same request", recovery: "retain prior committed scene and draft", exit: "background recovery, accepted, progress, retry, input, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .optional)], transitions: [edge(.generatorBackgroundRecovery, .recover, "background owner reconciles request"), edge(.generatorAccepted, .recover, "resume same request"), edge(.generatorProgressReading, .recover, "resume reading"), edge(.generatorRetry, .retry, "retry classified request"), edge(.generatorInputEditing, .cancel, "cancel returns to draft"), edge(.librarySelected, .teardown, "workspace teardown")]),
            makeState(.generatorBackgroundRecovery, availability: .pending, owner: .generatorRecovery, sources: [.generationBackgroundRecovery], entry: "backgrounded request has been reconciled by its owner", action: "resume the same request or expose its prior result", recovery: "retain idempotency key and prior committed scene", exit: "accepted, progress, retry, input, or library", persistence: .project, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .optional), artifact(.script, .validated, .optional), artifact(.generationJob, .pending, .required), artifact(.plannedScene, .optional)], transitions: [edge(.generatorAccepted, .recover, "resume accepted request"), edge(.generatorProgressReading, .recover, "resume active request"), edge(.generatorRetry, .retry, "retry reconciled request"), edge(.generatorInputEditing, .back, "return to draft"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorFailureParse, availability: .pending, owner: .generatorStateMachine, sources: [.generationReading, .sceneScript], entry: "parser reports a non-success result", action: "inspect reason and edit input", recovery: "preserve previous readable project", exit: "validating or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .missing, .required), artifact(.generationJob, .missing)], transitions: [edge(.generatorValidating, .retry, "revalidate corrected input before acceptance"), edge(.generatorInputEditing, .recover, "edit input"), edge(.librarySelected, .back, "leave generator")]),
            makeState(.generatorFailureMalformed, availability: .pending, owner: .generatorStateMachine, sources: [.generationMalformedFailure], entry: "owner rejects a malformed generated result", action: "inspect the safe failure and retry", recovery: "keep prior project and original input", exit: "validating, input, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .missing, .required), artifact(.plannedScene, .missing, .required), artifact(.generationJob, .missing, .required)], transitions: [edge(.generatorValidating, .retry, "revalidate malformed request before acceptance"), edge(.generatorInputEditing, .recover, "edit input"), edge(.librarySelected, .back, "leave generator")]),
            makeState(.generatorFailureQuota, availability: .pending, owner: .generatorStateMachine, sources: [.generationQuotaFailure], entry: "owner reports quota exhaustion", action: "wait for quota recovery or leave", recovery: "retain request without fake progress", exit: "retry, input, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .missing, .required)], transitions: [edge(.generatorRetry, .retry, "quota retry is allowed"), edge(.generatorInputEditing, .back, "edit/cancel"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorFailurePersistence, availability: .pending, owner: .generatorPersistence, sources: [.generationPersistenceFailure], entry: "generator result or request persistence failed", action: "retry the named persistence operation", recovery: "preserve draft and prior committed project", exit: "retry, input, or library", persistence: .project, artifacts: [artifact(.project, .pending, .required), artifact(.input, .draft, .required), artifact(.script, .validated, .optional), artifact(.generationJob, .pending, .optional)], transitions: [edge(.generatorRetry, .retry, "persistence retry"), edge(.generatorInputEditing, .recover, "return to draft"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorFailureTimeout, availability: .pending, owner: .generatorTimeout, sources: [.generationTimeout], entry: "a bounded generation deadline expired", action: "inspect timeout and retry or edit", recovery: "cancel the same request and retain its idempotency key", exit: "retry, input, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .validated, .optional), artifact(.generationJob, .missing, .required)], transitions: [edge(.generatorRetry, .retry, "retry after timeout"), edge(.generatorInputEditing, .recover, "edit timed-out request"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorFailureCompilation, availability: .pending, owner: .generatorCompilation, sources: [.generationCompilationFailure], entry: "validated generation data failed plan compilation", action: "inspect compiler diagnostics and edit or retry", recovery: "retain the prior committed project; never claim a plan", exit: "validating, input, or library", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .missing, .required), artifact(.generationJob, .missing, .optional)], transitions: [edge(.generatorValidating, .retry, "revalidate after compilation failure"), edge(.generatorInputEditing, .recover, "edit source input"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorFailureNetwork, availability: .pending, owner: .generatorStateMachine, sources: [.generationReading], entry: "network/execution owner reports failure", action: "retry or leave the draft", recovery: "retain request and prior project; no fake success", exit: "retry or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.generationJob, .missing, .required)], transitions: [edge(.generatorRetry, .retry, "retry classified request"), edge(.generatorInputEditing, .back, "edit/cancel"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorFailureModel, availability: .pending, owner: .generatorStateMachine, sources: [.generationPlanning], entry: "model owner reports failure", action: "retry or leave the draft", recovery: "retain request and prior project; no fake result", exit: "retry or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .missing, .required), artifact(.generationJob, .missing, .required)], transitions: [edge(.generatorRetry, .retry, "retry classified request"), edge(.generatorInputEditing, .back, "edit/cancel"), edge(.librarySelected, .teardown, "leave generator")]),
            makeState(.generatorRetry, availability: .pending, owner: .generatorStateMachine, sources: [.generationReading, .sceneScript], entry: "bounded retry context is available", action: "retry the same draft/request once owned", recovery: "retain failure reason and close", exit: "validating or input", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .validated, .required), artifact(.generationJob, .pending, .required)], transitions: [edge(.generatorValidating, .retry, "revalidate before acceptance"), edge(.generatorInputEditing, .back, "edit instead")]),
            makeState(.generatorSuccess, owner: .generatorExecution, sources: [.workspaceGeneratedReady, .sceneScript, .plannedScene, .storyboardProjection], entry: "committed SceneScript and PlannedScene are validated", action: "open AR or storyboard planning", recovery: "rollback only the attempted commit and retain draft", exit: "AR preparing, storyboard planning, or model failure", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .pending, .required), artifact(.arBindings, .missing, .optional)], transitions: [edge(.arPreparing, .advance, "open AR workspace"), edge(.storyboardPlanning, .advance, "compile storyboard projection"), edge(.generatorFailureModel, .recover, "commit/model failure")]),

            // AR: hardware-dependent readiness stays pending; interruption,
            // error, and teardown are explicit recovery edges.
            makeState(.arPreparing, availability: .pending, owner: .ar, sources: [.workspaceGeneratedReady, .arSession, .plannedScene], entry: "success hand-off owns stable project and plan", action: "prepare supported AR session", recovery: "release session and retry", exit: "ready, search, relocalization, error, interruption, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .pending, .required), artifact(.worldMap, .optional), artifact(.storyboard, .optional)], transitions: [edge(.arReady, .advance, "session publishes valid frame"), edge(.arSurfaceSearch, .advance, "session enters search"), edge(.arRelocalization, .recover, "session needs relocalization"), edge(.arError, .recover, "session error"), edge(.arInterruption, .recover, "session interrupted"), edge(.arTeardown, .teardown, "release workspace")]),
            makeState(.arReady, availability: .pending, owner: .ar, sources: [.workspaceShooting, .arSession], entry: "post-recovery frame and workspace are available", action: "search for a surface", recovery: "relocalize or reset", exit: "surface search, relocalization, reset, preparing, interruption, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .pending, .required), artifact(.worldMap, .optional)], transitions: [edge(.arSurfaceSearch, .advance, "search action"), edge(.arRelocalization, .recover, "tracking is lost"), edge(.arReset, .recover, "reset requested"), edge(.arPreparing, .recover, "session restart"), edge(.arInterruption, .recover, "session interruption"), edge(.arError, .recover, "session error"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arSurfaceSearch, availability: .pending, owner: .ar, sources: [.workspaceShooting, .arSession], entry: "AR session exposes tracking search", action: "confirm a supported surface", recovery: "reposition and retry", exit: "placement, ready, relocalization, reset, interruption, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .pending, .required), artifact(.worldMap, .optional)], transitions: [edge(.arPlacement, .advance, "surface confirmed"), edge(.arReady, .recover, "search cancelled"), edge(.arRelocalization, .recover, "tracking is lost"), edge(.arReset, .recover, "reset requested"), edge(.arInterruption, .recover, "session interruption"), edge(.arError, .recover, "session error"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arPlacement, availability: .pending, owner: .ar, sources: [.workspaceShooting, .arSession], entry: "surface confirmation is real", action: "place stable plan entities", recovery: "undo and retry placement", exit: "live hints, playback, storyboard, recording preflight, interruption, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .validated, .required), artifact(.storyboard, .optional)], transitions: [edge(.arPlayback, .advance, "play selected plan"), edge(.arLiveHints, .advance, "open live hints"), edge(.storyboardResult, .advance, "open storyboard"), edge(.recordingPreflight, .outerNavigation, "prepare recording"), edge(.arInterruption, .recover, "session interruption"), edge(.arError, .recover, "session error"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arPlayback, availability: .pending, owner: .ar, sources: [.workspacePreviewPlayback, .arSession, .plannedScene], entry: "placed plan and selected beat are available", action: "play or stop the selected beat", recovery: "stop playback and return to placement", exit: "live hints, storyboard, recording preflight, interruption, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .validated, .required), artifact(.storyboard, .optional)], transitions: [edge(.storyboardResult, .back, "open storyboard"), edge(.arLiveHints, .advance, "open live hints"), edge(.recordingPreflight, .outerNavigation, "prepare take"), edge(.arPlacement, .recover, "stop playback"), edge(.arInterruption, .recover, "session interruption"), edge(.arError, .recover, "session error"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arMarking, owner: .ar, sources: [.workspaceMarking, .arSession], entry: "user marking owner is active", action: "name or confirm a marked object", recovery: "cancel marker without persistence", exit: "marker sheet, placement, input context, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .draft, .required)], transitions: [edge(.sheetMarkerName, .advance, "name selected marker"), edge(.arPlacement, .advance, "marker confirmed"), edge(.generatorInputMarkedDetected, .back, "return to generator context"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arLiveHints, availability: .pending, owner: .ar, sources: [.workspaceShooting, .arSession], entry: "current frame has an owner-linked hint", action: "inspect one actionable hint", recovery: "hide stale/unavailable hint", exit: "hint pause, hint playback, placement, interruption, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.decisionTrace, .optional)], transitions: [edge(.arHintPause, .advance, "pause hints"), edge(.arHintPlayback, .advance, "play explanation"), edge(.arPlacement, .back, "return to placement"), edge(.arInterruption, .recover, "session interruption"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arHintPause, owner: .ar, sources: [.workspaceShooting], entry: "one immutable hint pause is visible", action: "resume or inspect the paused hint", recovery: "discard stale pause and resume", exit: "live hints, hint playback, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.decisionTrace, .optional)], transitions: [edge(.arLiveHints, .recover, "resume live hints"), edge(.arHintPlayback, .advance, "inspect explanation"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arHintPlayback, owner: .ar, sources: [.workspacePreviewPlayback, .decisionTrace], entry: "one owner-linked explanation is selected", action: "play explanation once", recovery: "stop playback and retain source hint", exit: "live hints, placement, interruption, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.decisionTrace, .validated, .required), artifact(.arBindings, .validated, .required)], transitions: [edge(.arLiveHints, .back, "finish explanation"), edge(.arPlacement, .back, "close explanation"), edge(.arInterruption, .recover, "session interruption"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.recordingInProgress, availability: .pending, owner: .recording, sources: [.workspaceRecording, .recordingInProgress], entry: "recording owner is actively writing media", action: "stop this take", recovery: "stop safely before AR interruption or teardown", exit: "stopping or terminal recording outcome", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingStopping, .recover, "explicit stop, interruption, or teardown requests safe stop"), edge(.recordingFailure, .recover, "writer failure")]),
            makeState(.recordingReview, owner: .recordingStore, sources: [.workspacePreviewPlayback, .recordingCompleted, .recordingArtifact], entry: "only a resolvable promoted artifact enters review", action: "play, share, or request Photos export", recovery: "keep missing media disabled and retry promotion", exit: "playback, share, Photos export, storyboard, library, or teardown", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .optional)], transitions: [edge(.recordingPlayback, .outerNavigation, "play owned recording"), edge(.recordingShare, .outerNavigation, "share requested"), edge(.recordingPhotosExporting, .outerNavigation, "Photos export requested"), edge(.storyboardResult, .back, "return to storyboard"), edge(.librarySelected, .back, "return to library")]),
            makeState(.recordingPlayback, availability: .pending, owner: .recordingPlayback, sources: [.recordingPlayback, .recordingArtifact], entry: "a promoted project-owned recording is selected for playback", action: "play or stop the owned media", recovery: "return to review when media is unavailable", exit: "review, recovery, or teardown", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required)], transitions: [edge(.recordingReview, .outerNavigation, "playback finishes"), edge(.recordingRecovery, .outerNavigation, "playback cannot resolve"), edge(.librarySelected, .outerNavigation, "close playback")]),
            makeState(.recordingRecovery, availability: .pending, owner: .recording, sources: [.recordingRecovery, .recordingFailure], entry: "recording owner exposes a failure or uncertain take without a guaranteed promoted artifact", action: "retry preflight or leave", recovery: "keep project identity and never discard promoted media implicitly", exit: "preflight or library", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .optional)], transitions: [edge(.recordingPreflight, .outerNavigation, "retry capture"), edge(.librarySelected, .outerNavigation, "leave recovery")]),
            makeState(.arInterruption, availability: .pending, owner: .ar, sources: [.arSession, .workspaceShooting, .recordingInProgress], entry: "AR session interruption invalidates live frame generation", action: "wait for post-interruption recovery", recovery: "stop recording/playback/hints and clear readiness", exit: "relocalization, reset, preparing, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .missing, .required), artifact(.worldMap, .optional), artifact(.recording, .pending, .optional)], transitions: [edge(.arRelocalization, .recover, "post-interruption relocalization"), edge(.arReset, .recover, "interruption requires reset"), edge(.arPreparing, .recover, "post-interruption restart"), edge(.arError, .recover, "interruption reports failure"), edge(.arTeardown, .teardown, "leave workspace")]),
            makeState(.arError, availability: .pending, owner: .ar, sources: [.arSession], entry: "AR owner reports an honest error", action: "close or recover the session", recovery: "preserve project and do not claim live readiness", exit: "reset, relocalization, preparing, selected library, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .missing, .required), artifact(.worldMap, .optional), artifact(.recording, .missing, .optional)], transitions: [edge(.arReset, .recover, "reset session"), edge(.arRelocalization, .recover, "retry tracking"), edge(.arPreparing, .recover, "retry session"), edge(.librarySelected, .back, "close workspace"), edge(.arTeardown, .teardown, "release session")]),
            makeState(.arRelocalization, availability: .pending, owner: .arRecovery, sources: [.arRelocalization, .arSession], entry: "tracking loss requires a bounded relocalization attempt", action: "restore the session against current anchors", recovery: "fall back to world-map recovery or reset without claiming readiness", exit: "world-map recovery, ready, reset, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .pending, .required), artifact(.worldMap, .pending, .optional)], transitions: [edge(.arWorldMapRecovery, .recover, "relocalization needs saved world map"), edge(.arReady, .advance, "tracking is restored"), edge(.arReset, .recover, "relocalization failed"), edge(.arError, .recover, "relocalization reports error"), edge(.arTeardown, .teardown, "release session")]),
            makeState(.arReset, availability: .pending, owner: .arRecovery, sources: [.arReset, .arSession], entry: "session reset is requested after stale tracking or error", action: "pause, clear, and restart the AR session", recovery: "retain project links and retry relocalization", exit: "preparing, relocalization, world-map recovery, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .missing, .required), artifact(.worldMap, .optional)], transitions: [edge(.arPreparing, .recover, "session restart begins"), edge(.arRelocalization, .recover, "retry tracking after reset"), edge(.arWorldMapRecovery, .recover, "restore saved map after reset"), edge(.arError, .recover, "reset fails"), edge(.arTeardown, .teardown, "release reset owner")]),
            makeState(.arWorldMapRecovery, availability: .pending, owner: .arRecovery, sources: [.arWorldMapRecovery, .arSession, .scenePersistence], entry: "saved world-map/anchor graph is available for recovery", action: "restore and validate map-linked anchors", recovery: "reset the session or preserve project without fabricated anchors", exit: "ready, relocalization, reset, error, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.plannedScene, .validated, .required), artifact(.arBindings, .pending, .required), artifact(.worldMap, .pending, .required)], transitions: [edge(.arReady, .advance, "map-linked anchors validate"), edge(.arRelocalization, .recover, "map restore needs relocalization"), edge(.arReset, .recover, "map restore requires reset"), edge(.arError, .recover, "map restore fails"), edge(.arTeardown, .teardown, "release recovery owner")]),
            makeState(.arTeardown, owner: .ar, sources: [.arSession, .scenePersistence], entry: "route/workspace teardown is requested", action: "pause session and await owner release", recovery: "retain project before dismiss", exit: "selected library only", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .missing, .required), artifact(.recording, .optional)], transitions: [edge(.librarySelected, .teardown, "teardown completes")]),

            // Storyboard and reachable sheets are projections over real domain
            // items; editor/validation/delete/trace remain typed owner edges.
            makeState(.storyboardPlanning, owner: .storyboard, sources: [.generationPlanning, .plannedScene, .storyboardProjection], entry: "validated plan is being compiled into storyboard beats", action: "construct a typed storyboard projection", recovery: "return to the generator result without claiming beats", exit: "validation or generator success", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .pending, .required)], transitions: [edge(.storyboardValidation, .advance, "projection is assembled"), edge(.generatorSuccess, .back, "return to generator result")]),
            makeState(.storyboardValidation, owner: .storyboard, sources: [.plannedScene, .storyboardProjection, .scenePersistence], entry: "storyboard projection is ready for owner validation", action: "validate beat/action links before display", recovery: "retain plan and expose the invalid link", exit: "result or projection validation failure", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .pending, .required)], transitions: [edge(.storyboardResult, .advance, "all links validate"), edge(.storyboardProjectionValidationFailure, .recover, "projection validation fails"), edge(.storyboardPlanning, .back, "rebuild projection")]),
            makeState(.storyboardProjectionValidationFailure, availability: .pending, owner: .storyboard, sources: [.plannedScene, .storyboardProjection, .scenePersistence], entry: "storyboard projection validation failed before a result exists", action: "inspect the projection diagnostic and rebuild", recovery: "return to planning without opening an editor draft", exit: "planning, validation, or generator success", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .pending, .required)], transitions: [edge(.storyboardPlanning, .recover, "rebuild typed projection"), edge(.storyboardValidation, .retry, "retry projection validation"), edge(.generatorSuccess, .back, "return to validated generator result")]),
            makeState(.storyboardTrayCollapsed, owner: .storyboard, sources: [.workspacePreviewPlayback, .storyboardProjection], entry: "storyboard projection has a selected beat", action: "expand tray or select beat", recovery: "show missing-link warning", exit: "expanded, reflow, result, inspector, or editor", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardTrayExpanded, .advance, "expand tray"), edge(.storyboardSelectionReflow, .advance, "select beat"), edge(.storyboardInspector, .advance, "inspect beat"), edge(.storyboardEditorMedium, .advance, "edit beat")]),
            makeState(.storyboardTrayExpanded, owner: .storyboard, sources: [.workspacePreviewPlayback, .storyboardProjection], entry: "readable beat tray is expanded", action: "select, inspect, reorder, or edit a beat", recovery: "collapse without mutating project", exit: "collapsed, reflow, result, inspector, reorder, or editor", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardTrayCollapsed, .back, "collapse tray"), edge(.storyboardSelectionReflow, .advance, "select beat"), edge(.storyboardInspector, .advance, "inspect beat"), edge(.storyboardReorder, .advance, "reorder beats"), edge(.storyboardEditorMedium, .advance, "edit beat")]),
            makeState(.storyboardReorder, availability: .pending, owner: .storyboardEditor, sources: [.storyboardProjection, .scenePersistence], entry: "selected beats have an explicit reorder draft", action: "move beats and save the new order", recovery: "restore the last validated order", exit: "saving, tray, result, or validation failure", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .draft, .required), artifact(.plannedScene, .validated, .required)], transitions: [edge(.storyboardSaving, .advance, "save reorder"), edge(.storyboardTrayExpanded, .back, "cancel reorder"), edge(.storyboardResult, .back, "close reorder"), edge(.storyboardValidationFailure, .recover, "reorder validation fails")]),
            makeState(.storyboardSelectionReflow, owner: .storyboard, sources: [.workspacePreviewPlayback, .storyboardProjection], entry: "selection owner has a stable beat ID", action: "settle selected beat before editor", recovery: "return to prior selection", exit: "result, inspector, editor, or tray", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardResult, .advance, "selection settles"), edge(.storyboardInspector, .advance, "open inspector"), edge(.storyboardEditorMedium, .advance, "open editor"), edge(.storyboardTrayExpanded, .back, "selection cancelled")]),
            makeState(.storyboardResult, owner: .storyboard, sources: [.workspacePreviewPlayback, .storyboardProjection, .sceneScript, .plannedScene], entry: "real SceneScript/PlannedScene projection is available", action: "select, inspect, reorder, edit, or record", recovery: "show missing-link warning without fake thumbnail", exit: "tray, inspector, reorder, editor, AR placement, or recording", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.script, .validated, .required), artifact(.plannedScene, .validated, .required), artifact(.storyboard, .validated, .required), artifact(.preview, .optional), artifact(.recording, .missing, .optional)], transitions: [edge(.storyboardTrayCollapsed, .back, "collapse tray"), edge(.storyboardTrayExpanded, .advance, "expand tray"), edge(.storyboardSelectionReflow, .advance, "select beat"), edge(.storyboardInspector, .advance, "inspect beat"), edge(.storyboardReorder, .advance, "reorder beats"), edge(.storyboardEditorMedium, .advance, "edit beat"), edge(.arPlacement, .back, "return to AR"), edge(.recordingPreflight, .outerNavigation, "prepare recording")]),
            makeState(.storyboardInspector, owner: .storyboard, sources: [.storyboardProjection, .decisionTrace], entry: "selected beat metadata is linked", action: "inspect evidence or edit beat", recovery: "close inspector to result", exit: "result, trace, or editor", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .validated, .required), artifact(.decisionTrace, .optional)], transitions: [edge(.storyboardResult, .back, "close inspector"), edge(.sheetDecisionTrace, .advance, "open decision trace"), edge(.storyboardEditorMedium, .advance, "edit inspected beat")]),
            makeState(.storyboardEditorMedium, owner: .storyboardEditor, sources: [.workspaceEditing, .storyboardProjection], entry: "real beat draft opens at medium detent", action: "edit, save, or request delete", recovery: "discard unsaved draft only", exit: "large editor, saving, validation failure, delete, or result", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .draft, .required), artifact(.script, .validated, .required)], transitions: [edge(.storyboardEditorLarge, .advance, "expand editor"), edge(.storyboardSaving, .advance, "save draft"), edge(.storyboardValidationFailure, .recover, "validation fails"), edge(.storyboardDeleteConfirmation, .delete, "delete beat"), edge(.storyboardResult, .back, "cancel editor")]),
            makeState(.storyboardEditorLarge, owner: .storyboardEditor, sources: [.workspaceEditing, .storyboardProjection], entry: "real beat draft opens at large detent", action: "edit, save, or request delete", recovery: "return to medium without data loss", exit: "medium editor, saving, validation failure, delete, or result", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .draft, .required), artifact(.script, .validated, .required)], transitions: [edge(.storyboardEditorMedium, .back, "shrink editor"), edge(.storyboardSaving, .advance, "save draft"), edge(.storyboardValidationFailure, .recover, "validation fails"), edge(.storyboardDeleteConfirmation, .delete, "delete beat"), edge(.storyboardResult, .back, "cancel editor")]),
            makeState(.storyboardSaving, owner: .storyboardEditor, sources: [.workspaceEditing, .scenePersistence], entry: "one owner-side save is in flight", action: "await idempotent save", recovery: "keep draft and surface failure", exit: "result, editor, or validation failure", persistence: .draft, artifacts: [artifact(.project, .pending, .required), artifact(.storyboard, .pending, .required)], transitions: [edge(.storyboardResult, .advance, "save commits"), edge(.storyboardEditorMedium, .recover, "save returns editable draft"), edge(.storyboardValidationFailure, .recover, "save validates and rejects")]),
            makeState(.storyboardValidationFailure, owner: .storyboardEditor, sources: [.workspaceEditing], entry: "editor draft validation returned a typed invalid field", action: "correct the field in the editor draft", recovery: "retain draft and field reason", exit: "medium or large editor", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .draft, .required)], transitions: [edge(.storyboardEditorMedium, .recover, "return to medium editor"), edge(.storyboardEditorLarge, .recover, "return to large editor")]),
            makeState(.storyboardDeleteConfirmation, owner: .persistence, sources: [.workspaceEditing, .scenePersistence], entry: "selected beat identity is visible", action: "confirm or cancel deletion", recovery: "cancel without deleting beat", exit: "result or editor", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardResult, .delete, "confirmed delete"), edge(.storyboardEditorMedium, .cancel, "cancel delete")]),
            makeState(.sheetSceneName, owner: .libraryPersistence, sources: [.libraryCreating, .scenePersistence], entry: "library create-name sheet is open", action: "enter and confirm scene name", recovery: "close while retaining draft", exit: "create-name, duplicate, or selected", persistence: .draft, artifacts: [artifact(.project, .draft, .required), artifact(.input, .draft, .required)], transitions: [edge(.libraryCreateName, .back, "close sheet"), edge(.librarySelected, .advance, "create succeeds"), edge(.libraryDuplicateName, .recover, "duplicate name")]),
            makeState(.sheetMarkerName, owner: .ar, sources: [.workspaceMarking, .scenePersistence], entry: "selected mark awaits a name", action: "name or cancel marker", recovery: "discard unconfirmed mark", exit: "marking or placement", persistence: .draft, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .draft, .required)], transitions: [edge(.arMarking, .back, "close marker sheet"), edge(.arPlacement, .advance, "marker confirmed")]),
            makeState(.sheetScreenplayInput, owner: .generatorInput, sources: [.workspaceEditing, .keyboard], entry: "screenplay input sheet is open", action: "edit and submit screenplay", recovery: "close without dropping draft", exit: "input empty, editing, or invalid", persistence: .draft, artifacts: [artifact(.project, .validated, .required), artifact(.input, .draft, .required), artifact(.script, .pending, .required)], transitions: [edge(.generatorInputEditing, .back, "close with text"), edge(.generatorInputEmpty, .recover, "close empty"), edge(.generatorInputInvalid, .recover, "submit invalid")]),
            makeState(.sheetDecisionTrace, owner: .trace, sources: [.decisionTrace, .storyboardProjection], entry: "decision trace is linked to selected beat", action: "inspect evidence and close", recovery: "hide trace if link is missing", exit: "inspector or result", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.decisionTrace, .validated, .required), artifact(.storyboard, .validated, .required)], transitions: [edge(.storyboardInspector, .back, "close trace"), edge(.storyboardResult, .back, "close to result")]),

            // RecordingLifecycleState: explicit stop/finalize/promote/finish,
            // cancellation/release, and system export without fake artifacts.
            makeState(.recordingPreflight, availability: .pending, owner: .recording, sources: [.recordingPreflight, .workspaceShooting], entry: "AR/storyboard hand-off requests a recording preflight", action: "check links, format, and recorder readiness", recovery: "return to the source workspace without a take", exit: "permission, playback, or recovery", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.storyboard, .optional), artifact(.recording, .missing, .required)], transitions: [edge(.recordingPermission, .outerNavigation, "request capture permission"), edge(.recordingPlayback, .outerNavigation, "inspect existing recording"), edge(.recordingRecovery, .outerNavigation, "preflight cannot proceed")]),
            makeState(.recordingPermission, availability: .pending, owner: .recording, sources: [.recordingPermission], entry: "capture permission status is unresolved", action: "request or explain microphone/camera permission", recovery: "return to preflight when permission changes", exit: "idle, preflight, or recovery", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .missing, .required)], transitions: [edge(.recordingIdle, .outerNavigation, "permission is granted"), edge(.recordingPreflight, .back, "permission check cancelled"), edge(.recordingRecovery, .outerNavigation, "permission denied")]),
            makeState(.recordingIdle, owner: .recording, sources: [.recordingIdle], entry: "recording owner has no active take", action: "prepare a take", recovery: "remain idle", exit: "preparing, ready, or teardown", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .missing, .required)], transitions: [edge(.recordingPreparing, .advance, "prepare capture"), edge(.recordingReady, .advance, "owner publishes ready"), edge(.recordingReleased, .teardown, "release idle owner")]),
            makeState(.recordingPreparing, owner: .recording, sources: [.recordingPreparing], entry: "capture format/permissions are preparing", action: "await recorder readiness", recovery: "return to idle on preparation failure", exit: "ready, failure, cancelled, or released", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingReady, .advance, "recorder ready"), edge(.recordingFailure, .recover, "preparation failure"), edge(.recordingCancelled, .cancel, "cancel preparation"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingReady, owner: .recording, sources: [.recordingReady, .workspaceRecording], entry: "capture format and links are ready", action: "start a take", recovery: "return to placement without artifact", exit: "starting, in-progress, cancelled, or failure", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.arBindings, .validated, .required), artifact(.storyboard, .validated, .optional), artifact(.recording, .missing, .required)], transitions: [edge(.recordingStarting, .advance, "start take"), edge(.recordingInProgress, .advance, "atomic recorder start"), edge(.recordingCancelled, .cancel, "cancel before start"), edge(.recordingFailure, .recover, "start failure")]),
            makeState(.recordingStarting, owner: .recording, sources: [.recordingStarting], entry: "identity gate passed; writer/audio preparation is pending", action: "finish preparation or cancel", recovery: "return without publishing REC", exit: "in-progress, failure, cancelled, or released", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingInProgress, .advance, "writer starts"), edge(.recordingFailure, .recover, "writer/audio failure"), edge(.recordingCancelled, .cancel, "cancel start"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingStopping, owner: .recording, sources: [.recordingStopping], entry: "stop requested for active take", action: "finalize writer", recovery: "retain recoverable recorder result", exit: "finalizing, completed, failure, cancelled, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingFinalizing, .advance, "writer stops"), edge(.recordingCompleted, .advance, "atomic stop returns final"), edge(.recordingFailure, .recover, "stop failure"), edge(.recordingCancelled, .cancel, "cancel stop"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingFinalizing, owner: .recording, sources: [.recordingFinalizing], entry: "writer finalization is in flight", action: "await final media descriptor", recovery: "preserve pending/failure journal; never show completed", exit: "promoting, completed, failure, cancelled, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingPromoting, .advance, "finalization succeeds"), edge(.recordingCompleted, .advance, "finalization yields owned artifact"), edge(.recordingFailure, .recover, "finalization fails"), edge(.recordingCancelled, .cancel, "cancel finalization"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingPromoting, owner: .recordingStore, sources: [.recordingPromoting, .recordingArtifact], entry: "finalized descriptor is being promoted to project store", action: "complete or retry one exclusive promotion from pendingRecordingArtifacts", recovery: "retry recordingPromoting with the same pendingRecordingArtifacts; never mark the recording missing or rerun finalization", exit: "completed, cancelled, or retry recordingPromoting", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .pending, .required)], transitions: [edge(.recordingPromoting, .retry, "retry pendingRecordingArtifacts without finalization"), edge(.recordingCompleted, .advance, "promotion succeeds"), edge(.recordingCancelled, .cancel, "cancel promotion")]),
            makeState(.recordingCompleted, owner: .recordingStore, sources: [.recordingCompleted, .recordingArtifact], entry: "project-owned recording artifact resolves", action: "open review, share, or Photos export", recovery: "reopen newest resolvable artifact", exit: "review, share, Photos export, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required)], transitions: [edge(.recordingReview, .outerNavigation, "open review"), edge(.recordingShare, .outerNavigation, "share requested"), edge(.recordingPhotosExporting, .outerNavigation, "Photos export requested"), edge(.recordingReleased, .teardown, "release recording UI/owner; retain promoted project media")]),
            makeState(.recordingFailure, owner: .recording, sources: [.recordingFailure], entry: "capture or finalization failed before a promoted artifact resolves", action: "enter recovery, retry finalization, or discard", recovery: "preserve honest failure and never claim reviewable media", exit: "recovery, finalizing, cancelled, AR interruption, AR teardown, or released", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .missing, .required)], transitions: [edge(.recordingRecovery, .outerNavigation, "open recovery"), edge(.recordingFinalizing, .retry, "retry finalization"), edge(.recordingCancelled, .cancel, "discard active take"), edge(.arInterruption, .outerNavigation, "safe stop completed with interruption outcome"), edge(.arTeardown, .outerNavigation, "safe stop completed with teardown outcome"), edge(.recordingReleased, .teardown, "release owner")]),
            makeState(.recordingCancelled, owner: .recording, sources: [.recordingCancelled], entry: "take was cancelled before promotion", action: "release recorder resources", recovery: "retain project and failure journal", exit: "released only", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .missing, .optional)], transitions: [edge(.recordingReleased, .teardown, "resource release completes")]),
            makeState(.recordingReleased, owner: .recording, sources: [.recordingReleased], entry: "recording owner has released take resources; any promoted artifact remains project-owned", action: "none; route may close", recovery: "start a new owner instance without deleting a promoted artifact", exit: "terminal", persistence: .project, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .optional)], transitions: []),
            makeState(.recordingShare, availability: .pending, owner: .export, sources: [.recordingShare], entry: "a promoted recording is handed to the current share owner", action: "open the LegacySceneGeneratorCameraShell/UIActivityViewController share hand-off", recovery: "return to review without changing project media", exit: "share hand-off or review", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .optional)], transitions: [edge(.recordingExporting, .outerNavigation, "open current share owner"), edge(.recordingReview, .outerNavigation, "cancel share request")]),
            makeState(.recordingExporting, availability: .pending, owner: .export, sources: [.recordingShare, .recordingExport], entry: "current share hand-off is in flight for a promoted artifact", action: "await LegacySceneGeneratorCameraShell/UIActivityViewController share result", recovery: "keep review playable and share retryable", exit: "share result, share-cancelled, share-failure, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .pending, .optional)], transitions: [edge(.recordingExported, .export, "share hand-off succeeds"), edge(.recordingExportCancelled, .cancel, "user cancels share"), edge(.recordingExportFailure, .recover, "share hand-off fails"), edge(.recordingReleased, .outerNavigation, "close share owner without deleting source")]),
            makeState(.recordingExported, availability: .pending, owner: .export, sources: [.recordingShare, .recordingExport], entry: "current share hand-off returned a concrete result", action: "return to review or release the share owner", recovery: "retain the project-owned recording when share result is absent", exit: "review or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .optional)], transitions: [edge(.recordingReview, .back, "return to review"), edge(.recordingReleased, .outerNavigation, "release share owner")]),
            makeState(.recordingExportCancelled, availability: .pending, owner: .export, sources: [.recordingShare, .recordingExport], entry: "current share hand-off was cancelled before producing an external result", action: "return to review or retry share", recovery: "preserve the promoted source recording", exit: "review, share, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .missing, .optional)], transitions: [edge(.recordingReview, .outerNavigation, "return to review"), edge(.recordingShare, .retry, "retry share"), edge(.recordingReleased, .outerNavigation, "close share without deleting source")]),
            makeState(.recordingExportFailure, availability: .pending, owner: .export, sources: [.recordingShare, .recordingExport], entry: "current share hand-off failed after a promoted source was selected", action: "retry share or return to review", recovery: "preserve the promoted source recording and failure reason", exit: "review, share, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.recordingExport, .missing, .optional)], transitions: [edge(.recordingShare, .retry, "retry share"), edge(.recordingReview, .outerNavigation, "return to review"), edge(.recordingReleased, .outerNavigation, "close share without deleting source")]),
            makeState(.recordingPhotosExporting, availability: .pending, owner: .photosExport, sources: [.recordingPhotosExport], entry: "Photos export is requested for a promoted project recording", action: "await the future PHPhotoLibrary export owner", recovery: "keep the source recording project-owned and retryable", exit: "Photos exported, Photos export-cancelled, Photos export-failure, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.photosExportReceipt, .pending, .required)], transitions: [edge(.recordingPhotosExported, .export, "Photos export succeeds"), edge(.recordingPhotosExportCancelled, .cancel, "Photos export is cancelled"), edge(.recordingPhotosExportFailure, .recover, "Photos export fails"), edge(.recordingReleased, .outerNavigation, "close Photos exporter without deleting source")]),
            makeState(.recordingPhotosExported, availability: .pending, owner: .photosExport, sources: [.recordingPhotosExport], entry: "Photos export returned a concrete result", action: "return to review or release the Photos owner", recovery: "retain the promoted source recording when Photos result is absent", exit: "review or released", persistence: .release, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.photosExportReceipt, .promoted, .required)], transitions: [edge(.recordingReview, .outerNavigation, "return to review"), edge(.recordingReleased, .outerNavigation, "release Photos owner")]),
            makeState(.recordingPhotosExportCancelled, availability: .pending, owner: .photosExport, sources: [.recordingPhotosExport], entry: "Photos export was cancelled before producing a library asset", action: "return to review or retry Photos export", recovery: "preserve the promoted source recording", exit: "review, Photos export, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.photosExportReceipt, .missing, .optional)], transitions: [edge(.recordingReview, .outerNavigation, "return to review"), edge(.recordingPhotosExporting, .retry, "retry Photos export"), edge(.recordingReleased, .outerNavigation, "close Photos export without deleting source")]),
            makeState(.recordingPhotosExportFailure, availability: .pending, owner: .photosExport, sources: [.recordingPhotosExport], entry: "Photos export failed after a promoted source was selected", action: "retry Photos export or return to review", recovery: "preserve the promoted source recording and failure reason", exit: "review, Photos export, or released", persistence: .artifact, artifacts: [artifact(.project, .promoted, .required), artifact(.recording, .promoted, .required), artifact(.photosExportReceipt, .missing, .optional)], transitions: [edge(.recordingPhotosExporting, .retry, "retry Photos export"), edge(.recordingReview, .outerNavigation, "return to review"), edge(.recordingReleased, .outerNavigation, "close Photos export without deleting source")])
        ],
        entryStates: [.libraryEmpty, .libraryLoaded]
    )

    func state(_ value: SceneJourneyState) -> SceneJourneyStateContract? {
        states.first { $0.state == value }
    }

    func allows(_ from: SceneJourneyState, _ to: SceneJourneyState) -> Bool {
        state(from)?.transitions.contains { $0.to == to } == true
    }

    /// Promotion retry is an in-place journey action, not a recorder no-op.
    /// It is the only permitted self-edge and requires the pending artifact
    /// relation that the owner preserves while retrying promotion.
    private static func isAllowedPromotionRetry(
        from contract: SceneJourneyStateContract,
        _ transition: SceneJourneyTransition
    ) -> Bool {
        contract.state == .recordingPromoting
            && transition.to == .recordingPromoting
            && transition.kind == .retry
            && transition.trigger.contains("pendingRecordingArtifacts")
            && contract.artifact(.recording)?.status == .pending
            && contract.artifact(.recording)?.requirement == .required
    }

    /// Outer navigation is intentionally a closed allowlist. It is reserved
    /// for a known owner/route hand-off, never as a generic escape hatch for
    /// an unverified transition.
    private static let legitimateOuterNavigationEdges: Set<String> = [
        "ar.placement→recording.preflight",
        "ar.playback→recording.preflight",
        "storyboard.result→recording.preflight",
        "ar.recording-review→recording.playback",
        "ar.recording-review→recording.share",
        "ar.recording-review→recording.photos-exporting",
        "recording.playback→ar.recording-review",
        "recording.playback→recording.recovery",
        "recording.playback→library.selected",
        "recording.recovery→recording.preflight",
        "recording.recovery→recording.playback",
        "recording.recovery→ar.recording-review",
        "recording.recovery→library.selected",
        "recording.preflight→recording.permission",
        "recording.preflight→recording.playback",
        "recording.preflight→recording.recovery",
        "recording.permission→recording.idle",
        "recording.permission→recording.recovery",
        "recording.completed→ar.recording-review",
        "recording.completed→recording.share",
        "recording.completed→recording.photos-exporting",
        "recording.failed→recording.recovery",
        "recording.failed→ar.interruption",
        "recording.failed→ar.teardown",
        "recording.share→recording.exporting",
        "recording.share→ar.recording-review",
        "recording.exporting→recording.released",
        "recording.exported→recording.released",
        "recording.export-cancelled→ar.recording-review",
        "recording.export-cancelled→recording.released",
        "recording.export-failure→ar.recording-review",
        "recording.export-failure→recording.released",
        "recording.photos-exporting→recording.released",
        "recording.photos-exported→ar.recording-review",
        "recording.photos-exported→recording.released",
        "recording.photos-export-cancelled→ar.recording-review",
        "recording.photos-export-cancelled→recording.released",
        "recording.photos-export-failure→ar.recording-review",
        "recording.photos-export-failure→recording.released"
    ]

    func outerNavigationEdgesAreWhitelisted() -> Bool {
        states.allSatisfy { contract in
            contract.transitions.allSatisfy { transition in
                transition.kind != .outerNavigation
                    || Self.legitimateOuterNavigationEdges.contains("\(contract.id)→\(transition.to.id)")
            }
        }
    }

    func reachableStates() -> Set<SceneJourneyState> {
        var reachable = Set(entryStates)
        var frontier = entryStates
        while let current = frontier.popLast() {
            guard let contract = state(current) else { continue }
            for transition in contract.transitions where reachable.insert(transition.to).inserted {
                frontier.append(transition.to)
            }
        }
        return reachable
    }

    /// Every edge touching a recorder-owned lifecycle state must either match
    /// the canonical lifecycle table or explicitly cross the outer journey.
    func recordingLifecycleTransitionsAreConsistent() -> Bool {
        for contract in states {
            let fromLifecycle = contract.state.recordingLifecycleState
            for transition in contract.transitions {
                let toLifecycle = transition.to.recordingLifecycleState
                if fromLifecycle != nil || toLifecycle != nil {
                    if Self.isAllowedPromotionRetry(from: contract, transition) { continue }
                    if transition.kind == .outerNavigation { continue }
                    guard let fromLifecycle, let toLifecycle,
                          RecordingLifecycleState.isLegalTransition(from: fromLifecycle, to: toLifecycle) else {
                        return false
                    }
                }
            }
        }
        return true
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
        guard !entryStates.isEmpty,
              Set(entryStates).count == entryStates.count,
              entryStates.allSatisfy({ knownStates.contains($0.id) }),
              entryStates.allSatisfy { state($0)?.availability != .unreachable },
              outerNavigationEdgesAreWhitelisted(),
              recordingLifecycleTransitionsAreConsistent() else { return false }
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
                ($0.to != state.state || Self.isAllowedPromotionRetry(from: state, $0))
                    && knownStates.contains($0.to.id)
                    && !$0.trigger.isEmpty
            }) else { return false }
        }
        let reachable = reachableStates()
        return state(.recordingReleased)?.transitions.isEmpty == true
            && states.allSatisfy { $0.availability == .unreachable || reachable.contains($0.state) }
    }
}

// MARK: - M6-001 AR Workspace product contract

/// Thin immutable projection over `SceneJourneyContract.production`.
/// This declaration owns no `ARSession`, reducer, recorder, or copied graph.
enum ARWorkspaceDeviceClass: String, CaseIterable, Codable, Hashable {
    case iPhone
    case iPad
}

enum ARWorkspaceOrientation: String, CaseIterable, Codable, Hashable {
    case landscapeLeft
    case landscapeRight
    case portrait
    case portraitUpsideDown
}

struct ARWorkspaceOrientationMatrix: Codable, Equatable {
    let supported: [ARWorkspaceDeviceClass: Set<ARWorkspaceOrientation>]

    static let canonical = ARWorkspaceOrientationMatrix(supported: [
        .iPhone: [.landscapeLeft, .landscapeRight],
        .iPad: [.landscapeLeft, .landscapeRight]
    ])

    func supportedOrientations(for device: ARWorkspaceDeviceClass) -> [ARWorkspaceOrientation] {
        (supported[device] ?? []).sorted { $0.rawValue < $1.rawValue }
    }

    func supports(_ orientation: ARWorkspaceOrientation, on device: ARWorkspaceDeviceClass) -> Bool {
        supported[device]?.contains(orientation) == true
    }

    func validate() -> Bool {
        self == Self.canonical
    }
}

enum ARWorkspaceRuntimeConformance: String, Codable, Equatable {
    case conformingM6002 = "runtime conforms to M6-002 sole-ARSession ownership"
}

enum ARWorkspaceOwnerRole: String, CaseIterable, Codable, Hashable {
    case workspaceLifecycle = "workspace-lifecycle"
    case arSessionLifecycle = "ar-session-lifecycle"
    case presentation
    case placementAnchors = "placement-anchors"
    case marking
    case hints
    case playback
    case recording
    case persistence
    case teardown
}

enum ARWorkspaceOwnerReference: String, Codable, Equatable {
    case workspaceLifecycle = "SceneGeneratorViewModel + SceneWorkspaceTeardownCoordinator"
    case arSessionLifecycle = "ARSceneContainer.Coordinator (runtime sole ARSession owner)"
    case presentation = "CommercialShell routes + AR presentation"
    case placementAnchors = "SceneGeneratorViewModel placement/anchors owner"
    case marking = "SceneGeneratorViewModel marking owner"
    case hints = "SceneGeneratorViewModel live-hints owner"
    case playback = "SceneGeneratorViewModel + LegacySceneGeneratorCameraShell playback owners"
    case recording = "SceneRecordingController + RecordingLifecycleOwner"
    case persistence = "UnifiedSceneProject + existing world-map persistence owners"
    case teardown = "SceneWorkspaceTeardownCoordinator"
}

struct ARWorkspaceOwnershipBoundary: Codable, Equatable {
    let role: ARWorkspaceOwnerRole
    let owner: ARWorkspaceOwnerReference
}

struct ARWorkspaceOwnershipContract: Codable, Equatable {
    let boundaries: [ARWorkspaceOwnershipBoundary]
    let arSessionRuntimeConformance: ARWorkspaceRuntimeConformance

    static let canonical = ARWorkspaceOwnershipContract(
        boundaries: [
            ARWorkspaceOwnershipBoundary(role: .workspaceLifecycle, owner: .workspaceLifecycle),
            ARWorkspaceOwnershipBoundary(role: .arSessionLifecycle, owner: .arSessionLifecycle),
            ARWorkspaceOwnershipBoundary(role: .presentation, owner: .presentation),
            ARWorkspaceOwnershipBoundary(role: .placementAnchors, owner: .placementAnchors),
            ARWorkspaceOwnershipBoundary(role: .marking, owner: .marking),
            ARWorkspaceOwnershipBoundary(role: .hints, owner: .hints),
            ARWorkspaceOwnershipBoundary(role: .playback, owner: .playback),
            ARWorkspaceOwnershipBoundary(role: .recording, owner: .recording),
            ARWorkspaceOwnershipBoundary(role: .persistence, owner: .persistence),
            ARWorkspaceOwnershipBoundary(role: .teardown, owner: .teardown)
        ],
        arSessionRuntimeConformance: .conformingM6002
    )

    var arSessionOwners: [ARWorkspaceOwnershipBoundary] {
        boundaries.filter { $0.role == .arSessionLifecycle }
    }

    func boundary(for role: ARWorkspaceOwnerRole) -> ARWorkspaceOwnershipBoundary? {
        boundaries.first { $0.role == role }
    }

    func validate() -> Bool {
        self == Self.canonical
    }
}

enum ARWorkspaceIdentityKind: String, CaseIterable, Codable, Hashable {
    case workspace = "workspace.id"
    case sessionGeneration = "session.generation"
    case project = "project.id"
    case plannedScene = "planned-scene.id"
    case entity = "entity.id"
    case anchor = "anchor.id"
    case marker = "marker.id"
    case recording = "recording.id"
}

enum ARWorkspaceIdentityFenceRule: String, CaseIterable, Codable, Hashable {
    case stableAcrossFrames = "stable-across-frames"
    case boundToSessionGeneration = "bound-to-session-generation"
    case rejectStaleGeneration = "reject-stale-generation"
    case invalidatedByInterruption = "invalidated-by-interruption"
    case invalidatedByReset = "invalidated-by-reset"
    case revalidatedAfterRelocalization = "revalidated-after-relocalization"
    case revalidatedAfterMapRestore = "revalidated-after-map-restore"
    case invalidatedByTeardown = "invalidated-by-teardown"
}

struct ARWorkspaceIdentityFence: Codable, Equatable, Hashable {
    let identity: ARWorkspaceIdentityKind
    let rules: Set<ARWorkspaceIdentityFenceRule>
}

struct ARWorkspaceIdentityContract: Codable, Equatable {
    let fences: [ARWorkspaceIdentityFence]

    static let canonical = ARWorkspaceIdentityContract(fences: [
        ARWorkspaceIdentityFence(
            identity: .workspace,
            rules: [.stableAcrossFrames, .invalidatedByTeardown]
        ),
        ARWorkspaceIdentityFence(
            identity: .sessionGeneration,
            rules: [
                .stableAcrossFrames,
                .rejectStaleGeneration,
                .invalidatedByInterruption,
                .invalidatedByReset,
                .revalidatedAfterRelocalization,
                .revalidatedAfterMapRestore,
                .invalidatedByTeardown
            ]
        ),
        ARWorkspaceIdentityFence(
            identity: .project,
            rules: [.stableAcrossFrames]
        ),
        ARWorkspaceIdentityFence(
            identity: .plannedScene,
            rules: [.stableAcrossFrames, .boundToSessionGeneration, .invalidatedByReset, .revalidatedAfterMapRestore]
        ),
        ARWorkspaceIdentityFence(
            identity: .entity,
            rules: [.stableAcrossFrames, .boundToSessionGeneration, .invalidatedByReset, .revalidatedAfterMapRestore]
        ),
        ARWorkspaceIdentityFence(
            identity: .anchor,
            rules: [
                .stableAcrossFrames,
                .boundToSessionGeneration,
                .invalidatedByInterruption,
                .invalidatedByReset,
                .revalidatedAfterRelocalization,
                .revalidatedAfterMapRestore
            ]
        ),
        ARWorkspaceIdentityFence(
            identity: .marker,
            rules: [.stableAcrossFrames, .boundToSessionGeneration, .invalidatedByReset, .revalidatedAfterMapRestore]
        ),
        ARWorkspaceIdentityFence(
            identity: .recording,
            rules: [.stableAcrossFrames, .boundToSessionGeneration, .invalidatedByInterruption, .invalidatedByTeardown]
        )
    ])

    func validate() -> Bool {
        self == Self.canonical
    }
}

enum ARWorkspaceTeardownStep: String, CaseIterable, Codable, Hashable {
    case stopRecording = "stop-recording"
    case stopPlayback = "stop-playback"
    case persist = "persist"
    case releaseRecording = "release-recording"
    case pauseAndDetach = "pause-and-detach"
}

struct ARWorkspaceTeardownContract: Codable, Equatable {
    let order: [ARWorkspaceTeardownStep]
    let terminalState: SceneJourneyState
    let terminalDestination: SceneJourneyState
    let awaitsTerminalBeforeNavigation: Bool

    static let canonical = ARWorkspaceTeardownContract(
        order: [.stopRecording, .stopPlayback, .persist, .releaseRecording, .pauseAndDetach],
        terminalState: .arTeardown,
        terminalDestination: .librarySelected,
        awaitsTerminalBeforeNavigation: true
    )

    func validate() -> Bool {
        self == Self.canonical
    }
}

struct ARWorkspaceContract: Codable, Equatable {
    static let canonicalStates: [SceneJourneyState] = [
        .arPreparing,
        .arReady,
        .arSurfaceSearch,
        .arPlacement,
        .arPlayback,
        .arMarking,
        .arLiveHints,
        .arHintPause,
        .arHintPlayback,
        .recordingInProgress,
        .recordingReview,
        .arInterruption,
        .arError,
        .arRelocalization,
        .arReset,
        .arWorldMapRecovery,
        .arTeardown
    ]

    static let canonicalRecoveryStates: [SceneJourneyState] = [
        .arInterruption,
        .arError,
        .arRelocalization,
        .arReset,
        .arWorldMapRecovery
    ]

    let states: [SceneJourneyState]
    let orientationMatrix: ARWorkspaceOrientationMatrix
    let ownership: ARWorkspaceOwnershipContract
    let identity: ARWorkspaceIdentityContract
    let teardown: ARWorkspaceTeardownContract

    init(
        states: [SceneJourneyState] = Self.canonicalStates,
        orientationMatrix: ARWorkspaceOrientationMatrix = .canonical,
        ownership: ARWorkspaceOwnershipContract = .canonical,
        identity: ARWorkspaceIdentityContract = .canonical,
        teardown: ARWorkspaceTeardownContract = .canonical
    ) {
        self.states = states
        self.orientationMatrix = orientationMatrix
        self.ownership = ownership
        self.identity = identity
        self.teardown = teardown
    }

    static let production = ARWorkspaceContract()

    /// AR rows are always resolved from the existing production journey.
    func state(_ value: SceneJourneyState) -> SceneJourneyStateContract? {
        guard states.contains(value) else { return nil }
        return SceneJourneyContract.production.state(value)
    }

    /// Only AR states may be origins. Legal non-AR destinations remain those
    /// already declared by the production journey (for example teardown to
    /// `library.selected`).
    func allows(_ from: SceneJourneyState, _ to: SceneJourneyState) -> Bool {
        guard Self.canonicalStates.contains(from),
              SceneJourneyContract.production.state(from) != nil else {
            return false
        }
        return SceneJourneyContract.production.allows(from, to)
    }

    func validate() -> Bool {
        guard states == Self.canonicalStates,
              orientationMatrix.validate(),
              ownership.validate(),
              identity.validate(),
              teardown.validate() else {
            return false
        }

        let journey = SceneJourneyContract.production
        guard let activeRecording = journey.state(.recordingInProgress) else {
            return false
        }

        let safeStop = activeRecording.transitions.contains {
            $0.to == .recordingStopping
                && $0.kind == .recover
                && $0.trigger.localizedCaseInsensitiveContains("safe stop")
        }
        let directInterruptionOrTeardown = activeRecording.transitions.contains {
            $0.to == .arInterruption || $0.to == .arTeardown
        }
        return safeStop && !directInterruptionOrTeardown
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

struct ScriptOffsetRange: Codable, Equatable, Sendable {
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
    var generationProvenance: SceneChunkGenerationProvenance? = nil
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
    var generationProvenance: SceneChunkGenerationProvenance? = nil
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
    var remoteFailure: SceneRemoteGenerationFailure? = nil
}
