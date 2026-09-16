import AVFoundation
import Combine
import CoreVideo
import Foundation

struct CameraRecordingProjectHandle: Sendable, Equatable {
    let id: UUID
    let name: String
    let updatedAt: Date
    let leaseToken: UUID
}

struct CameraRecordingSavedTake: Sendable, Equatable {
    let project: CameraRecordingProjectHandle
    let reference: SceneRecordingReference
    let artifact: RecordingArtifact
}

enum CameraRecordingPersistenceFailure: Error, Sendable, Equatable {
    case invalidName
    case projectUnavailable
    case projectInUse
    case conflict
    case persistence
    case mediaUnavailable
}

enum CameraRecordingPresentationFailure: Error, Sendable, Equatable {
    case busy
    case released
}

protocol CameraRecordingPersisting: Sendable {
    func createProject(named name: String) async throws -> CameraRecordingProjectHandle
    func save(
        _ artifact: RecordingArtifact,
        project: CameraRecordingProjectHandle,
        explicitlyMergeLatest: Bool
    ) async throws -> CameraRecordingSavedTake
    func releaseProject(_ project: CameraRecordingProjectHandle) async
    func resolve(_ reference: SceneRecordingReference, projectID: UUID) async -> RecordingArtifact?
}

/// A narrow asynchronous adapter over the existing persistence owner. It owns
/// no files/schema of its own and keeps blocking DB/filesystem work off MainActor.
actor CameraRecordingDBAdapter: CameraRecordingPersisting {
    private let database: DBService
    private let artifactStore: RecordingArtifactStore
    private var projectLeases: [UUID: UUID] = [:]

    init(database: DBService = .shared, artifactStore: RecordingArtifactStore) {
        self.database = database
        self.artifactStore = artifactStore
    }

    func createProject(named name: String) throws -> CameraRecordingProjectHandle {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CameraRecordingPersistenceFailure.invalidName
        }
        let project = try database.createUnifiedSceneProject(named: name)
        guard let token = database.acquireProjectLease(id: project.id) else {
            throw CameraRecordingPersistenceFailure.projectInUse
        }
        projectLeases[project.id] = token
        return CameraRecordingProjectHandle(
            id: project.id, name: project.name, updatedAt: project.updatedAt, leaseToken: token
        )
    }

    func save(
        _ artifact: RecordingArtifact,
        project: CameraRecordingProjectHandle,
        explicitlyMergeLatest: Bool
    ) async throws -> CameraRecordingSavedTake {
        guard projectLeases[project.id] == project.leaseToken else {
            throw CameraRecordingPersistenceFailure.projectInUse
        }
        // Journal the original committed project generation before moving.
        // An explicit retry never rewrites an older journal's captured version.
        let reference = try artifactStore.promoteFinalizedArtifact(
            artifact, projectID: project.id, expectedProjectUpdatedAt: project.updatedAt
        )
        guard let candidateURL = artifactStore.resolve(reference, ownedBy: project.id),
              await AVURLAssetPlaybackProbe().isPlayableMovie(at: candidateURL) else {
            // A writer recovery descriptor is not proof of a playable movie.
            // Keep the journal and promoted media for explicit recovery.
            throw CameraRecordingPersistenceFailure.mediaUnavailable
        }
        guard projectLeases[project.id] == project.leaseToken else {
            throw CameraRecordingPersistenceFailure.projectInUse
        }
        guard case let .success(opened) = database.loadUnifiedSceneProjectForOpening(id: project.id) else {
            throw CameraRecordingPersistenceFailure.projectUnavailable
        }
        let matching = opened.project.recordingReferences.filter { $0.recordingID == reference.recordingID }
        if let alreadySaved = matching.first {
            guard matching.count == 1, alreadySaved.relativePath == reference.relativePath else {
                throw CameraRecordingPersistenceFailure.conflict
            }
            try? artifactStore.acknowledgePersistedReference(alreadySaved, projectID: project.id)
            return try savedTake(reference: alreadySaved, project: opened.project, token: project.leaseToken)
        }
        guard explicitlyMergeLatest || opened.project.updatedAt == project.updatedAt else {
            throw CameraRecordingPersistenceFailure.conflict
        }
        var updated = opened.project
        updated.recordingReferences.append(reference)
        updated.updatedAt = Date(timeIntervalSinceReferenceDate: max(
            Date().timeIntervalSinceReferenceDate,
            opened.project.updatedAt.timeIntervalSinceReferenceDate + 0.000_001
        ))
        do {
            try database.saveUnifiedSceneProject(
                updated, worldMap: opened.worldMap, expectedUpdatedAt: opened.project.updatedAt
            )
        } catch is DBServiceError {
            throw CameraRecordingPersistenceFailure.conflict
        }
        return try savedTake(reference: reference, project: updated, token: project.leaseToken)
    }

    func releaseProject(_ project: CameraRecordingProjectHandle) {
        guard projectLeases[project.id] == project.leaseToken else { return }
        projectLeases.removeValue(forKey: project.id)
        database.releaseProjectLease(id: project.id, token: project.leaseToken)
    }

    func resolve(_ reference: SceneRecordingReference, projectID: UUID) -> RecordingArtifact? {
        guard let url = artifactStore.resolve(reference, ownedBy: projectID) else { return nil }
        return RecordingArtifact(
            id: RecordingID(rawValue: reference.recordingID), localURL: url,
            duration: reference.duration, hasAudio: reference.hasAudio
        )
    }

    private func savedTake(
        reference: SceneRecordingReference,
        project: UnifiedSceneProject,
        token: UUID
    ) throws -> CameraRecordingSavedTake {
        guard let artifact = resolve(reference, projectID: project.id) else {
            throw CameraRecordingPersistenceFailure.mediaUnavailable
        }
        return CameraRecordingSavedTake(
            project: CameraRecordingProjectHandle(
                id: project.id, name: project.name, updatedAt: project.updatedAt, leaseToken: token
            ),
            reference: reference,
            artifact: artifact
        )
    }
}

enum CameraCoachRecordingPhase: Sendable, Equatable {
    case idle
    case changingMeter
    case preparing
    case recording
    case finalizing
    case saving
    case review
    case failed
    case released
}

enum CameraCoachRecordingIssue: Sendable, Equatable {
    case busy
    case pendingSave
    case permission(PermissionSnapshot)
    case capture(CameraRecordingCaptureError)
    case recorder(RecorderFailure)
    case audioSession(AudioSessionCoordinatorError)
    case persistence(CameraRecordingPersistenceFailure)
    case released
}

private struct GrantedCameraRecordingMicrophoneChecker: RecordingMicrophonePermissionChecking {
    let permissions: any PermissionClient
    func microphoneAvailable() async -> Bool {
        let current = await permissions.snapshot(for: .microphone)
        return current.availability == .available && current.authorization == .authorized
    }
}

private struct OwnedCameraRecordingAudioChecker: RecordingAudioSessionChecking {
    let coordinator: AudioSessionCoordinator
    let lease: AudioSessionLease?
    func audioSessionAvailable() async -> Bool {
        guard let lease else { return false }
        return await coordinator.ownsActiveLease(lease)
    }
}

@MainActor
final class CameraCoachRecordingCoordinator: ObservableObject {
    typealias ControllerFactory = @MainActor (
        PreparedCameraRecordingCapture, any RecordingStartPreflighting
    ) -> SceneRecordingController

    @Published private(set) var phase: CameraCoachRecordingPhase = .idle
    @Published private(set) var issue: CameraCoachRecordingIssue?
    @Published private(set) var meterEnabled = false
    @Published private(set) var latestSavedTake: CameraRecordingSavedTake?
    @Published private(set) var hasPendingSave = false
    @Published private(set) var lastPhotosOutcome: ScenePhotosExportOutcome?
    @Published private(set) var droppedVideoFrames = 0
    @Published private(set) var droppedAudioFrames = 0
    @Published private(set) var isPlaybackActive = false
    @Published private(set) var isPhotosExportInFlight = false
    private(set) var lastStopResult: RecordingStopResult?

    private final class Attempt {
        let id = UUID()
        let audioMode: RecordingAudioMode
        var captureLease: CameraRecordingCaptureLease?
        var controller: SceneRecordingController?
        var cleanupTask: Task<RecordingStopResult?, Never>?
        init(audioMode: RecordingAudioMode) { self.audioMode = audioMode }
    }

    private let capture: any CameraRecordingCaptureSource
    private let permissions: any PermissionClient
    private let audio: AudioSessionCoordinator
    private let persistence: any CameraRecordingPersisting
    private let artifactStore: RecordingArtifactStore
    private let photos: ScenePhotosExportService
    private let makeController: ControllerFactory
    private let preflightOverride: (any RecordingStartPreflighting)?
    private let projectName: @MainActor () -> String
    private let audioOwnerID: UUID
    private var audioLease: AudioSessionLease?
    private var recordingAudioDemand = false
    private var currentAttempt: Attempt?
    private var project: CameraRecordingProjectHandle?
    private var pendingArtifact: RecordingArtifact?
    private var generation: UInt64 = 0
    private var released = false
    private var startTask: Task<Void, Never>?
    private var startTaskAttemptID: UUID?
    private var stopTask: Task<RecordingStopResult?, Never>?
    private var releaseTask: Task<RecordingStopResult?, Never>?
    private var meterTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var healthTask: Task<Void, Never>?
    private var exportTask: Task<ScenePhotosExportOutcome, Never>?
    private var audioEventTask: Task<Void, Never>?
    private var audioObservation: CameraRecordingAudioObservation?
    private var meterTaskTarget: Bool?
    private var playbackLease: AudioSessionLease?
    private var playbackOwnerID: UUID?
    private var playbackAcquireTask: Task<AudioSessionLease, Error>?
    private var playbackReleaseTask: Task<Void, Never>?
    private var suspendTask: Task<Void, Never>?

    init(
        capture: any CameraRecordingCaptureSource,
        artifactStore: RecordingArtifactStore,
        persistence: any CameraRecordingPersisting,
        permissions: any PermissionClient = PermissionCoordinator(client: SystemPermissionClient()),
        audio: AudioSessionCoordinator = .shared,
        photos: ScenePhotosExportService = ScenePhotosExportService(),
        notificationCenter: NotificationCenter = .default,
        preflight: (any RecordingStartPreflighting)? = nil,
        projectName: @escaping @MainActor () -> String = {
            "Camera recording \(ISO8601DateFormatter().string(from: Date())) \(UUID().uuidString.prefix(4))"
        },
        makeController: ControllerFactory? = nil
    ) {
        self.capture = capture
        self.artifactStore = artifactStore
        self.persistence = persistence
        self.permissions = permissions
        self.audio = audio
        self.audioOwnerID = capture.sourceOwnerID
        self.photos = photos
        self.preflightOverride = preflight
        self.projectName = projectName
        self.makeController = makeController ?? { prepared, preflight in
            SceneRecordingController(
                artifactStore: artifactStore,
                sourceOwnerID: prepared.lease.ownerID,
                source: .cameraCoach,
                preflight: preflight
            ) { [prepared] configuration in
                if configuration.audioMode == .required && prepared.audioDriverFactory == nil {
                    throw RecorderFailure.audioUnavailable
                }
                return SerializedMediaRecorder(
                    writerFactory: AVAssetWriterRecordingWriterFactory(),
                    audioDriverFactory: configuration.audioMode == .required ? prepared.audioDriverFactory : nil
                )
            }
        }
        self.audioObservation = CameraRecordingAudioObservation(center: notificationCenter) { [weak self] in
            Task { @MainActor [weak self] in await self?.handleAudioInterruption() }
        }
    }

    func start(audioMode: RecordingAudioMode) async {
        if let startTask { await startTask.value; return }
        guard !released else { issue = .released; return }
        guard !hasPendingSave else { issue = .pendingSave; return }
        guard stopTask == nil, saveTask == nil, meterTask == nil,
              exportTask == nil, audioEventTask == nil, !isPlaybackActive,
              playbackAcquireTask == nil, playbackReleaseTask == nil, suspendTask == nil, currentAttempt == nil else {
            issue = .busy
            return
        }
        generation &+= 1
        let expectedGeneration = generation
        let attempt = Attempt(audioMode: audioMode)
        currentAttempt = attempt
        phase = .preparing
        issue = nil
        lastStopResult = nil
        droppedVideoFrames = 0
        droppedAudioFrames = 0
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performStart(attempt, generation: expectedGeneration)
        }
        startTask = task
        startTaskAttemptID = attempt.id
        await task.value
        if startTaskAttemptID == attempt.id {
            startTask = nil
            startTaskAttemptID = nil
        }
    }

    private func performStart(_ attempt: Attempt, generation expectedGeneration: UInt64) async {
        do {
            let lease = try await capture.reserveRecordingCapture()
            attempt.captureLease = lease
            try checkCurrent(attempt, generation: expectedGeneration)
            guard lease.ownerID == capture.sourceOwnerID else { throw CameraRecordingCaptureError.sourceChanged }
            try await requirePermission(.camera)
            try checkCurrent(attempt, generation: expectedGeneration)
            if attempt.audioMode == .required {
                try await requirePermission(.microphone)
                try checkCurrent(attempt, generation: expectedGeneration)
                recordingAudioDemand = true
                try await ensureAudioLease()
                try checkCurrent(attempt, generation: expectedGeneration)
            }
            let prepared = try await capture.prepareRecordingCapture(lease: lease, audioMode: attempt.audioMode)
            try checkCurrent(attempt, generation: expectedGeneration)
            guard prepared.lease == lease, prepared.fps > 0, prepared.timestamp.isFinite else {
                throw CameraRecordingCaptureError.sourceChanged
            }
            let preflight = makePreflight()
            if let failure = await preflight.validate(RecordingStartPreflightContext(
                width: CVPixelBufferGetWidth(prepared.pixelBuffer),
                height: CVPixelBufferGetHeight(prepared.pixelBuffer),
                fps: prepared.fps, codec: .h264,
                pixelFormatFourCC: CVPixelBufferGetPixelFormatType(prepared.pixelBuffer),
                audioMode: attempt.audioMode
            )) {
                throw failure
            }
            try checkCurrent(attempt, generation: expectedGeneration)
            // No empty project is created for denied permission, unavailable
            // capture, or failed mandatory preflight.
            if project == nil {
                let created = try await persistence.createProject(named: projectName())
                project = created
                try checkCurrent(attempt, generation: expectedGeneration)
            }
            let controller = makeController(prepared, preflight)
            attempt.controller = controller
            try await capture.attachRecordingController(controller, lease: lease)
            try checkCurrent(attempt, generation: expectedGeneration)
            try await controller.start(
                firstPixelBuffer: prepared.pixelBuffer,
                requestedFPS: prepared.fps,
                audioMode: attempt.audioMode,
                timestamp: prepared.timestamp,
                videoCodec: .h264,
                trackTransform: prepared.trackTransform
            )
            try checkCurrent(attempt, generation: expectedGeneration)
            phase = .recording
            issue = nil
            startHealthPolling(attempt, controller: controller, generation: expectedGeneration)
        } catch {
            // A concurrent stop owns cleanup and waits for this start task.
            // A late permission response cannot create a replacement attempt.
            guard stopTask == nil else { return }
            let result = await closeAndReleaseAttempt(attempt, reason: .user)
            if currentAttempt === attempt {
                currentAttempt = nil
                if result != nil {
                    // Cancellation may race the successful writer start.
                    // Preserve any finalized artifact returned by cleanup.
                    await consumeStopResult(result)
                } else if !(error is CancellationError) {
                    issue = mapIssue(error)
                    phase = .failed
                } else {
                    phase = .idle
                }
            }
        }
    }

    func stop(reason: RecordingStopReason = .user) async -> RecordingStopResult? {
        if let stopTask { return await stopTask.value }
        generation &+= 1
        startTask?.cancel()
        healthTask?.cancel()
        healthTask = nil
        let inFlightStart = startTask
        let task = Task { @MainActor [weak self] in
            guard let self else { return nil as RecordingStopResult? }
            if let inFlightStart { await inFlightStart.value }
            self.startTask = nil
            self.startTaskAttemptID = nil
            guard let attempt = self.currentAttempt else { return self.lastStopResult }
            self.phase = .finalizing
            let result = await self.closeAndReleaseAttempt(attempt, reason: reason)
            self.currentAttempt = nil
            await self.consumeStopResult(result)
            return result
        }
        stopTask = task
        let result = await task.value
        stopTask = nil
        return result
    }

    @discardableResult
    private func closeAndReleaseAttempt(_ attempt: Attempt, reason: RecordingStopReason) async -> RecordingStopResult? {
        if let cleanupTask = attempt.cleanupTask { return await cleanupTask.value }
        let task = Task { @MainActor [self] in
            if let lease = attempt.captureLease {
                await capture.closeRecordingFrameAdmission(lease)
            }
            let result = await attempt.controller?.stop(reason: reason)
            _ = await attempt.controller?.releaseAndWait()
            if let lease = attempt.captureLease {
                await capture.releaseRecordingCapture(lease)
            }
            attempt.captureLease = nil
            attempt.controller = nil
            recordingAudioDemand = false
            await releaseAudioIfUnneeded()
            return result
        }
        attempt.cleanupTask = task
        return await task.value
    }

    private func consumeStopResult(_ result: RecordingStopResult?) async {
        lastStopResult = result
        switch result {
        case let .finalized(artifact):
            pendingArtifact = artifact
            hasPendingSave = true
            await persistPending(explicitRetry: false)
        case let .failed(failure, recoverableArtifact):
            pendingArtifact = recoverableArtifact
            hasPendingSave = recoverableArtifact != nil
            issue = .recorder(failure)
            phase = .failed
        case nil:
            phase = latestSavedTake == nil ? .idle : .review
        }
    }

    func retryPersistence() async {
        guard !released else { issue = .released; return }
        guard startTask == nil, stopTask == nil, currentAttempt == nil,
              meterTask == nil, exportTask == nil, audioEventTask == nil,
              !isPlaybackActive, playbackAcquireTask == nil, playbackReleaseTask == nil,
              suspendTask == nil else { issue = .busy; return }
        if let saveTask { await saveTask.value; return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.persistPending(explicitRetry: true)
        }
        saveTask = task
        await task.value
        saveTask = nil
    }

    private func persistPending(explicitRetry: Bool) async {
        guard let artifact = pendingArtifact, let project else { return }
        phase = .saving
        do {
            let saved = try await persistence.save(artifact, project: project, explicitlyMergeLatest: explicitRetry)
            self.project = saved.project
            pendingArtifact = nil
            hasPendingSave = false
            latestSavedTake = saved
            issue = nil
            phase = .review
        } catch {
            // Keep the same descriptor even if promotion moved its source URL.
            // The store retries that recording identity idempotently.
            issue = mapIssue(error)
            phase = .failed
        }
    }

    func setMeterEnabled(_ enabled: Bool) async {
        guard !released else { issue = .released; return }
        guard currentAttempt == nil, startTask == nil, stopTask == nil, saveTask == nil,
              exportTask == nil, audioEventTask == nil, !isPlaybackActive,
              playbackAcquireTask == nil, playbackReleaseTask == nil, suspendTask == nil else {
            issue = .busy
            return
        }
        if let meterTask {
            guard meterTaskTarget == enabled else { issue = .busy; return }
            await meterTask.value
            return
        }
        guard enabled != meterEnabled else { return }
        generation &+= 1
        let expectedGeneration = generation
        phase = .changingMeter
        issue = nil
        meterTaskTarget = enabled
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if enabled {
                    try await self.requirePermission(.microphone)
                    try self.checkGeneration(expectedGeneration)
                    try await self.ensureAudioLease()
                    try self.checkGeneration(expectedGeneration)
                    try await self.capture.setRecordingAudioMeterEnabled(true)
                    try self.checkGeneration(expectedGeneration)
                    self.meterEnabled = true
                } else {
                    try await self.capture.setRecordingAudioMeterEnabled(false)
                    self.meterEnabled = false
                    await self.releaseAudioIfUnneeded()
                }
                if self.generation == expectedGeneration {
                    self.phase = self.latestSavedTake == nil ? .idle : .review
                }
            } catch {
                if enabled {
                    try? await self.capture.setRecordingAudioMeterEnabled(false)
                    self.meterEnabled = false
                    await self.releaseAudioIfUnneeded()
                }
                if self.generation == expectedGeneration, !(error is CancellationError) {
                    self.issue = self.mapIssue(error)
                    self.phase = .failed
                }
            }
        }
        meterTask = task
        await task.value
        meterTask = nil
    }

    func handleBackground() async {
        await suspendAndWait(reason: .background)
    }

    /// Retires all camera-related audio work before the capture graph stops,
    /// while retaining the project, saved review, and explicit retry boundary.
    func suspendAndWait(reason: RecordingStopReason = .interruption) async {
        if let suspendTask { await suspendTask.value; return }
        guard !released else { return }
        generation &+= 1
        meterTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.stop(reason: reason)
            await self.retirePlayback()
            if let meterTask = self.meterTask { await meterTask.value }
            self.meterTask = nil
            await self.disableMeterForExit()
        }
        suspendTask = task
        await task.value
        suspendTask = nil
    }

    /// Audio events retire playback and explicit microphone demand. An
    /// unrelated audio route notification does not terminate a silent take.
    func handleAudioInterruption() async {
        if let audioEventTask { await audioEventTask.value; return }
        guard !released,
              recordingAudioDemand || meterEnabled || meterTask != nil || isPlaybackActive
                || currentAttempt?.audioMode == .required else { return }
        generation &+= 1
        meterTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.stop(reason: .interruption)
            await self.retirePlayback()
            if let meterTask = self.meterTask { await meterTask.value }
            self.meterTask = nil
            await self.disableMeterForExit()
            if self.issue == nil { self.issue = .audioSession(.interrupted) }
        }
        audioEventTask = task
        await task.value
        audioEventTask = nil
    }

    func releaseAndWait(reason: RecordingStopReason = .routeExit) async -> RecordingStopResult? {
        if let releaseTask { return await releaseTask.value }
        released = true
        audioObservation = nil
        generation &+= 1
        meterTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return nil as RecordingStopResult? }
            let result = await self.stop(reason: reason)
            if let saveTask = self.saveTask { await saveTask.value }
            if let exportTask = self.exportTask { _ = await exportTask.value }
            if let audioEventTask = self.audioEventTask { await audioEventTask.value }
            if let suspendTask = self.suspendTask { await suspendTask.value }
            await self.retirePlayback()
            if let meterTask = self.meterTask { await meterTask.value }
            self.meterTask = nil
            await self.disableMeterForExit()
            if let project = self.project { await self.persistence.releaseProject(project) }
            self.phase = .released
            return result
        }
        releaseTask = task
        return await task.value
    }

    private func disableMeterForExit() async {
        do {
            try await capture.setRecordingAudioMeterEnabled(false)
        } catch {
            issue = mapIssue(error)
        }
        meterEnabled = false
        recordingAudioDemand = false
        await releaseAudioIfUnneeded()
        if phase == .changingMeter || phase == .preparing {
            phase = latestSavedTake == nil ? .idle : .review
        }
    }

    func resolvedSavedArtifact() async -> RecordingArtifact? {
        guard let saved = latestSavedTake else { return nil }
        return await persistence.resolve(saved.reference, projectID: saved.project.id)
    }

    /// The review presenter borrows the same audio owner used by capture.
    /// Opening playback fences silent recording as well as microphone takes.
    /// The UI explicitly disables its meter before requesting playback.
    func acquirePlaybackLease(ownerID: UUID) async throws -> AudioSessionLease {
        guard !released else { issue = .released; throw CameraRecordingPresentationFailure.released }
        if let playbackAcquireTask {
            guard playbackOwnerID == ownerID else { issue = .busy; throw CameraRecordingPresentationFailure.busy }
            return try await playbackAcquireTask.value
        }
        if let playbackLease, playbackOwnerID == ownerID, playbackReleaseTask == nil {
            guard await audio.ownsActiveLease(playbackLease) else {
                issue = .audioSession(.interrupted)
                throw AudioSessionCoordinatorError.interrupted
            }
            return playbackLease
        }
        guard currentAttempt == nil, startTask == nil, stopTask == nil, saveTask == nil,
              meterTask == nil, !meterEnabled, !recordingAudioDemand,
              exportTask == nil, audioEventTask == nil, !isPlaybackActive,
              playbackReleaseTask == nil, suspendTask == nil else {
            issue = .busy
            throw CameraRecordingPresentationFailure.busy
        }
        let expectedGeneration = generation
        playbackOwnerID = ownerID
        isPlaybackActive = true
        issue = nil
        let task = Task { @MainActor [weak self] in
            guard let self else { throw CameraRecordingPresentationFailure.released }
            var acquired: AudioSessionLease?
            do {
                let lease = try await self.audio.acquire(ownerID: ownerID, purpose: .playback)
                acquired = lease
                self.playbackLease = lease
                try self.checkGeneration(expectedGeneration)
                try await self.audio.activate(lease, configuration: .playback)
                try self.checkGeneration(expectedGeneration)
                return lease
            } catch {
                if let acquired { try? await self.audio.deactivate(acquired) }
                self.playbackLease = nil
                self.playbackOwnerID = nil
                self.isPlaybackActive = false
                if !(error is CancellationError) { self.issue = self.mapIssue(error) }
                throw error
            }
        }
        playbackAcquireTask = task
        defer { playbackAcquireTask = nil }
        return try await task.value
    }

    func releasePlaybackLease(ownerID: UUID) async {
        guard playbackOwnerID == ownerID else { return }
        if let playbackReleaseTask { await playbackReleaseTask.value; return }
        playbackAcquireTask?.cancel()
        let acquiring = playbackAcquireTask
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if let acquiring { _ = try? await acquiring.value }
            if let lease = self.playbackLease, lease.ownerID == ownerID {
                self.playbackLease = nil
                try? await self.audio.deactivate(lease)
            }
            self.playbackOwnerID = nil
            self.isPlaybackActive = false
        }
        playbackReleaseTask = task
        await task.value
        playbackReleaseTask = nil
    }

    private func retirePlayback() async {
        if let ownerID = playbackOwnerID { await releasePlaybackLease(ownerID: ownerID) }
        if let playbackReleaseTask { await playbackReleaseTask.value }
    }

    func exportToPhotos() async -> ScenePhotosExportOutcome {
        if let exportTask { return await exportTask.value }
        guard !released else { issue = .released; return .failed }
        guard currentAttempt == nil, startTask == nil, stopTask == nil, saveTask == nil,
              meterTask == nil, audioEventTask == nil, !isPlaybackActive,
              playbackAcquireTask == nil, playbackReleaseTask == nil, suspendTask == nil else {
            issue = .busy
            return .failed
        }
        let task = Task { @MainActor [weak self] in
            guard let self else { return ScenePhotosExportOutcome.failed }
            guard let artifact = await self.resolvedSavedArtifact(),
                  await AVURLAssetPlaybackProbe().isPlayableMovie(at: artifact.localURL) else {
                self.issue = .persistence(.mediaUnavailable)
                return .failed
            }
            let outcome = await self.photos.exportMovie(at: artifact.localURL)
            self.lastPhotosOutcome = outcome
            return outcome
        }
        exportTask = task
        isPhotosExportInFlight = true
        let outcome = await task.value
        exportTask = nil
        isPhotosExportInFlight = false
        return outcome
    }

    private func requirePermission(_ permission: AppPermission) async throws {
        let permissions = self.permissions
        var snapshot = try await CameraPermissionWaiter.value {
            await permissions.snapshot(for: permission)
        }
        try Task.checkCancellation()
        if snapshot.authorization == .notDetermined, snapshot.availability == .available {
            snapshot = try await CameraPermissionWaiter.value { await permissions.request(permission) }
        }
        try Task.checkCancellation()
        guard snapshot.availability == .available, snapshot.authorization == .authorized else {
            throw PermissionFailure(snapshot: snapshot)
        }
    }

    private struct PermissionFailure: Error { let snapshot: PermissionSnapshot }

    private func ensureAudioLease() async throws {
        if let audioLease {
            guard await audio.ownsActiveLease(audioLease) else {
                throw AudioSessionCoordinatorError.interrupted
            }
            return
        }
        let lease = try await audio.acquire(ownerID: audioOwnerID, purpose: .recording)
        audioLease = lease
        do {
            try await audio.activate(lease, configuration: .recording)
        } catch {
            try? await audio.deactivate(lease)
            audioLease = nil
            throw error
        }
    }

    private func releaseAudioIfUnneeded() async {
        guard !meterEnabled, !recordingAudioDemand, let lease = audioLease else { return }
        audioLease = nil
        try? await audio.deactivate(lease)
    }

    private func makePreflight() -> any RecordingStartPreflighting {
        if let preflightOverride { return preflightOverride }
        let store = artifactStore
        return StandardRecordingStartPreflight(
            microphonePermission: GrantedCameraRecordingMicrophoneChecker(permissions: permissions),
            audioSession: OwnedCameraRecordingAudioChecker(coordinator: audio, lease: audioLease),
            diskBudget: { context in
                try store.diskBudgetEstimate(
                    width: context.width, height: context.height, fps: context.fps,
                    codec: context.codec, audioMode: context.audioMode,
                    durationLimitSeconds: context.durationLimitSeconds
                )
            }
        )
    }

    private func checkGeneration(_ expected: UInt64) throws {
        try Task.checkCancellation()
        guard !released, generation == expected else { throw CancellationError() }
    }

    private func checkCurrent(_ attempt: Attempt, generation expected: UInt64) throws {
        try checkGeneration(expected)
        guard currentAttempt === attempt else { throw CancellationError() }
    }

    private func startHealthPolling(
        _ attempt: Attempt,
        controller: SceneRecordingController,
        generation expected: UInt64
    ) {
        healthTask?.cancel()
        healthTask = Task { @MainActor [weak self, weak controller] in
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return }
                guard let self, let controller,
                      self.generation == expected,
                      self.currentAttempt === attempt,
                      attempt.controller === controller,
                      self.phase == .recording else { return }
                let snapshot = await controller.recorderStateSnapshot()
                guard self.generation == expected, self.currentAttempt === attempt,
                      attempt.controller === controller, self.phase == .recording else { return }
                self.droppedVideoFrames = snapshot?.droppedVideoCount ?? self.droppedVideoFrames
                self.droppedAudioFrames = snapshot?.droppedAudioCount ?? self.droppedAudioFrames
                if snapshot?.state != .recording {
                    _ = await self.stop(reason: .interruption)
                    return
                }
            }
        }
    }

    private func mapIssue(_ error: Error) -> CameraCoachRecordingIssue {
        if let error = error as? PermissionFailure { return .permission(error.snapshot) }
        if let error = error as? CameraRecordingCaptureError { return .capture(error) }
        if let error = error as? RecorderFailure { return .recorder(error) }
        if let error = error as? AudioSessionCoordinatorError { return .audioSession(error) }
        if let error = error as? CameraRecordingPersistenceFailure { return .persistence(error) }
        return .persistence(.persistence)
    }
}

/// Scoped observer lifetime follows this coordinator. Category-change events
/// produced by our own activation policy are deliberately ignored.
private final class CameraRecordingAudioObservation: @unchecked Sendable {
    private let center: NotificationCenter
    private var tokens: [NSObjectProtocol] = []

    init(center: NotificationCenter, onInterruption: @escaping @Sendable () -> Void) {
        self.center = center
        tokens.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: nil
        ) { note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            onInterruption()
        })
        tokens.append(center.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil
        ) { _ in onInterruption() })
        tokens.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil
        ) { note in
            guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
            switch reason {
            case .oldDeviceUnavailable, .noSuitableRouteForCategory, .routeConfigurationChange:
                onInterruption()
            default:
                break
            }
        })
    }

    deinit { tokens.forEach { center.removeObserver($0) } }
}

/// Cancelling an owner must not wait for an OS prompt to be answered. The
/// shared PermissionClient request may finish later, but its stale result can
/// only complete this one-shot value; it cannot resume the cancelled owner.
private final class CameraPermissionWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<PermissionSnapshot, Error>?
    private var continuation: CheckedContinuation<PermissionSnapshot, Error>?

    static func value(
        _ operation: @escaping @Sendable () async -> PermissionSnapshot
    ) async throws -> PermissionSnapshot {
        let waiter = CameraPermissionWaiter()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiter.install(continuation)
                Task { waiter.finish(.success(await operation())) }
            }
        } onCancel: {
            waiter.finish(.failure(CancellationError()))
        }
    }

    private func install(_ continuation: CheckedContinuation<PermissionSnapshot, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func finish(_ result: Result<PermissionSnapshot, Error>) {
        lock.lock()
        guard self.result == nil else { lock.unlock(); return }
        self.result = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
