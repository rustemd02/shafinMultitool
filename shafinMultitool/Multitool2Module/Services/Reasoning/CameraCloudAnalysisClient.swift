import CoreMedia
import Foundation

enum CameraCloudClientError: Error, Equatable, Sendable {
    case invalidConfiguration
    case invalidRequest
    case approvalRequired
    case authentication
    case unavailable
    case invalidResponse
    case transport
}

struct CameraCloudAnalyzedEvidence: Sendable {
    let request: VLMVisualEvidenceRequest
    /// Untrusted proposal. Only the existing local validator/planner may admit it.
    let response: VLMVisualEvidenceResponse
}

struct CameraCloudPreparedAnalysis: Sendable {
    let transfer: CameraCloudTransferRequest
    let context: CameraCloudPauseContext
    let visualRequest: VLMVisualEvidenceRequest
    let body: Data
    let wireRequest: CameraCloudEvidenceWire.Request

    fileprivate init(transfer: CameraCloudTransferRequest, context: CameraCloudPauseContext,
                     visualRequest: VLMVisualEvidenceRequest, body: Data,
                     wireRequest: CameraCloudEvidenceWire.Request) {
        self.transfer = transfer
        self.context = context
        self.visualRequest = visualRequest
        self.body = body
        self.wireRequest = wireRequest
    }
}

protocol CameraCloudAnalyzing: Sendable {
    var policy: CameraCloudTransferPolicy { get }
    func prepare(still: CameraCloudPreparedStill, context: CameraCloudPauseContext,
                 locale: String) throws -> CameraCloudPreparedAnalysis
    func analyze(_ prepared: CameraCloudPreparedAnalysis,
                 approval: CameraCloudTransferApproval) async throws -> CameraCloudAnalyzedEvidence
}

/// Uses the same Scene installation token actor, HTTPS root and bounded transport.
/// Preparing a body is inert; each analyze call requires its exact ephemeral approval.
final class CameraCloudAnalysisClient: CameraCloudAnalyzing, Sendable {
    static let requestDeadlineSeconds: TimeInterval = 20
    static let cancellationDeadlineSeconds: TimeInterval = 3
    let policy: CameraCloudTransferPolicy
    private let session: URLSession
    private let tokenProvider: SceneServiceTokenProviding

    init(policy: CameraCloudTransferPolicy, session: URLSession,
         tokenProvider: SceneServiceTokenProviding) {
        self.policy = policy
        self.session = session
        self.tokenProvider = tokenProvider
    }

    func prepare(still: CameraCloudPreparedStill, context: CameraCloudPauseContext,
                 locale: String) throws -> CameraCloudPreparedAnalysis {
        let local = context.localRequest
        let provenance = still.provenance
        let pts = provenance.samplePresentationTimestamp
        let timestamp = CMTime(value: pts.value, timescale: pts.timescale,
                               flags: CMTimeFlags(rawValue: pts.flags), epoch: pts.epoch)
        guard local.mode == .pause, local.validate().isEmpty,
              CameraCloudEvidenceWire.validID(local.frameId),
              CameraCloudEvidenceWire.validID(provenance.snapshotID),
              context.snapshotID == provenance.snapshotID,
              local.frameId == provenance.sourceFrameID,
              context.pauseRevision >= 0, provenance.captureGeneration > 0, timestamp.isNumeric,
              still.redaction == .none,
              !still.jpegData.isEmpty, still.byteCount <= CameraCloudFramePreprocessor.maximumJPEGByteCount,
              still.pixelWidth > 0, still.pixelHeight > 0,
              max(still.pixelWidth, still.pixelHeight) <= CameraCloudFramePreprocessor.maximumLongEdge,
              still.sha256 == CameraCloudTransferPolicy.sha256(still.jpegData),
              let fingerprint = policy.fingerprint,
              ["lowKey", "silhouette", "symmetry", "tilt", "motionBlur", "negativeSpace"]
                .containsAll(context.intentAnswers.keys) else {
            throw CameraCloudClientError.invalidRequest
        }
        let requestID = UUID()
        let requestIDString = requestID.uuidString.lowercased()
        let requestLocale = locale.lowercased().hasPrefix("ru") ? "ru" : "en"
        let known = try local.localContext.groundedEntities.map(Self.wireEntity)
        guard CameraCloudEvidenceWire.unique(known.map(\.entity_ref), maximum: 32),
              CameraCloudEvidenceWire.unique(local.localContext.critique.issues.map(\.id), maximum: 64),
              CameraCloudEvidenceWire.unique(local.localContext.critique.strengths.map(\.id), maximum: 64) else {
            throw CameraCloudClientError.invalidRequest
        }
        let catalog = local.allowedCatalog
        guard catalog.allowedEvidenceDimensions.count <= 64,
              catalog.allowedVisualProblemTypes.count <= 64,
              catalog.allowedVisualStrengthTypes.count <= 64 else { throw CameraCloudClientError.invalidRequest }
        let visualRequest = VLMVisualEvidenceRequest(
            schemaVersion: local.schemaVersion, requestId: requestIDString,
            frameId: local.frameId, mode: .pause, locale: requestLocale,
            privacyTier: .authorizedSelectedStill, trigger: .explicitUserRequest,
            visualInput: VLMVisualInput(
                attachmentKind: .userSelectedStill, mediaRef: "sha256:" + still.sha256,
                longEdgePx: max(still.pixelWidth, still.pixelHeight), exifStripped: true,
                redactionApplied: false, redactionNotes: []
            ),
            localContext: local.localContext, allowedCatalog: local.allowedCatalog,
            constraints: local.constraints,
            correlation: VLMVisualEvidenceCorrelation(
                localCritiqueSummaryId: local.correlation.localCritiqueSummaryId,
                localPlanSummaryId: local.correlation.localPlanSummaryId,
                semanticCatalogVersion: local.correlation.semanticCatalogVersion,
                offloadingSchemaVersion: CameraCloudEvidenceWire.version,
                providerConfigVersion: policy.policyVersion,
                sessionEphemeralId: "capture-session:" + String(provenance.sessionGeneration)
            )
        )
        guard visualRequest.validate().isEmpty else { throw CameraCloudClientError.invalidRequest }
        let wire = CameraCloudEvidenceWire.Request(
            request_id: requestIDString, locale: requestLocale,
            correlation: CameraCloudEvidenceWire.Correlation(
                frame_id: local.frameId, snapshot_id: provenance.snapshotID,
                capture_session_id: "capture-session:" + String(provenance.sessionGeneration),
                capture_generation: provenance.captureGeneration,
                frame_pts: CameraCloudEvidenceWire.Timestamp(
                    value: pts.value, timescale: pts.timescale, flags: pts.flags, epoch: pts.epoch
                ), scene_epoch: context.pauseRevision, intent_revision: context.intentRevision
            ),
            consent: CameraCloudEvidenceWire.Consent(
                nonce: UUID().uuidString.lowercased(), policy_fingerprint: fingerprint
            ),
            media: CameraCloudEvidenceWire.Media(
                data: still.jpegData.base64EncodedString(), sha256: still.sha256,
                width: still.pixelWidth, height: still.pixelHeight
            ),
            local_context: CameraCloudEvidenceWire.LocalContext(
                known_entities: known, issue_ids: local.localContext.critique.issues.map(\.id),
                strength_ids: local.localContext.critique.strengths.map(\.id),
                allowed_dimensions: catalog.allowedEvidenceDimensions,
                allowed_problem_types: catalog.allowedVisualProblemTypes,
                allowed_strength_types: catalog.allowedVisualStrengthTypes,
                allowed_relation_types: VLMEntityRelationType.allCases, intent_answers: context.intentAnswers
            )
        )
        let body: Data
        do { body = try wire.encoded() } catch { throw CameraCloudClientError.invalidRequest }
        guard body.count <= CameraCloudEvidenceWire.maximumRequestBytes else {
            throw CameraCloudClientError.invalidRequest
        }
        let transfer = CameraCloudTransferRequest(
            requestID: requestID, requestHash: CameraCloudTransferPolicy.sha256(body),
            snapshotID: provenance.snapshotID, mediaSHA256: still.sha256, jpegData: still.jpegData,
            pixelWidth: still.pixelWidth, pixelHeight: still.pixelHeight, byteCount: still.byteCount,
            policy: policy, policyFingerprint: fingerprint
        )
        return CameraCloudPreparedAnalysis(transfer: transfer, context: context,
                                           visualRequest: visualRequest, body: body, wireRequest: wire)
    }

    func analyze(_ prepared: CameraCloudPreparedAnalysis,
                 approval: CameraCloudTransferApproval) async throws -> CameraCloudAnalyzedEvidence {
        // These checks precede token lookup, App Attest enrollment and all HTTP activity.
        guard approval == prepared.transfer.approval else { throw CameraCloudClientError.approvalRequired }
        guard prepared.transfer.policy == policy,
              prepared.transfer.policyFingerprint == policy.fingerprint,
              prepared.transfer.requestHash == CameraCloudTransferPolicy.sha256(prepared.body),
              prepared.transfer.mediaSHA256 == CameraCloudTransferPolicy.sha256(prepared.transfer.jpegData),
              prepared.body.count <= CameraCloudEvidenceWire.maximumRequestBytes,
              try prepared.wireRequest.encoded() == prepared.body else {
            throw CameraCloudClientError.invalidRequest
        }
        try Task.checkCancellation()
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + Self.requestDeadlineSeconds
        let cancellation = CancellationState()
        let cancellationURL = policy.serviceEndpoint.appendingPathComponent("camera")
            .appendingPathComponent("evidence")
            .appendingPathComponent(prepared.wireRequest.request_id)
        return try await withTaskCancellationHandler {
            do {
                var token = try await serviceToken(deadline: deadline, rejected: nil)
                for attempt in 0..<2 {
                    try Task.checkCancellation()
                    let remaining = deadline - ProcessInfo.processInfo.systemUptime
                    guard remaining > 0 else { throw CameraCloudClientError.transport }
                    var request = URLRequest(url: policy.serviceEndpoint.appendingPathComponent("camera")
                        .appendingPathComponent("evidence"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
                    request.setValue(prepared.wireRequest.request_id, forHTTPHeaderField: "Idempotency-Key")
                    request.setValue(prepared.transfer.requestHash, forHTTPHeaderField: "X-Camera-Request-SHA256")
                    request.httpBody = prepared.body
                    // Once content may have been sent, cancellation may request server cleanup
                    // with this existing bearer. It can never initiate new enrollment.
                    cancellation.recordContentAttempt(token: token)
                    try Task.checkCancellation()
                    let (data, response) = try await BoundedServiceHTTPTransport.send(
                        request, session: session,
                        maximumResponseBytes: CameraCloudEvidenceWire.maximumResponseBytes,
                        timeoutSeconds: remaining
                    )
                    try Task.checkCancellation()
                    if response.statusCode == 401, attempt == 0 {
                        let rejected = token
                        token = try await serviceToken(deadline: deadline, rejected: rejected)
                        guard token != rejected else { throw CameraCloudClientError.authentication }
                        continue
                    }
                    guard response.statusCode == 200 else {
                        if response.statusCode == 401 || response.statusCode == 403 {
                            throw CameraCloudClientError.authentication
                        }
                        if response.statusCode == 408 || response.statusCode == 504 {
                            throw CameraCloudClientError.transport
                        }
                        throw CameraCloudClientError.unavailable
                    }
                    let decoded = try CameraCloudEvidenceWire.decode(
                        data, request: prepared.wireRequest, bodyHash: prepared.transfer.requestHash
                    )
                    let result = CameraCloudEvidenceWire.adapt(
                        decoded, request: prepared.visualRequest, policy: policy,
                        latencyMs: Int(max(0, ProcessInfo.processInfo.systemUptime - started) * 1_000)
                    )
                    try Task.checkCancellation()
                    cancellation.finish()
                    return CameraCloudAnalyzedEvidence(request: prepared.visualRequest, response: result)
                }
                throw CameraCloudClientError.authentication
            } catch is CancellationError {
                requestRemoteCancellation(using: cancellation, url: cancellationURL)
                throw CancellationError()
            } catch let error as CameraCloudClientError {
                requestRemoteCancellation(using: cancellation, url: cancellationURL)
                throw error
            } catch {
                requestRemoteCancellation(using: cancellation, url: cancellationURL)
                throw CameraCloudClientError.transport
            }
        } onCancel: {
            requestRemoteCancellation(using: cancellation, url: cancellationURL)
        }
    }

    private func requestRemoteCancellation(using state: CancellationState, url: URL) {
        guard let existingToken = state.cancel() else { return }
        let session = self.session
        Task.detached(priority: .utility) {
            var request = URLRequest(url: url)
            request.httpMethod = "DELETE"
            request.setValue("Bearer " + existingToken, forHTTPHeaderField: "Authorization")
            // Best effort and separately bounded; local stale-result fencing is authoritative.
            _ = try? await BoundedServiceHTTPTransport.send(
                request, session: session, maximumResponseBytes: 16 * 1_024,
                timeoutSeconds: Self.cancellationDeadlineSeconds
            )
        }
    }

    private func serviceToken(deadline: TimeInterval, rejected: String?) async throws -> String {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { throw CameraCloudClientError.transport }
        let wait = TokenWait()
        let token = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard wait.install(continuation) else { return }
                let provider = tokenProvider
                let acquisition = Task {
                    guard !Task.isCancelled, wait.isActive else { return }
                    let value: String?
                    if let rejected {
                        value = await provider.replacementServiceToken(afterRejecting: rejected)
                    } else {
                        value = await provider.currentServiceToken()
                    }
                    wait.finish(.success(value))
                }
                let timer = Task {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                        wait.finish(.failure(CameraCloudClientError.transport))
                    } catch { }
                }
                wait.own(acquisition: acquisition, timer: timer)
            }
        } onCancel: {
            wait.finish(.failure(CancellationError()))
        }
        try Task.checkCancellation()
        guard let token, SceneGenerationClient.isValidServiceToken(token) else {
            throw CameraCloudClientError.authentication
        }
        return token
    }

    private static func wireEntity(_ entity: VLMGroundedEntity) throws -> CameraCloudEvidenceWire.Entity {
        guard CameraCloudEvidenceWire.validID(entity.entityRef),
              entity.detectorLabel.map(CameraCloudEvidenceWire.validDetectorLabel) ?? true,
              entity.detectorConfidence.map(CameraCloudEvidenceWire.unit) ?? true else {
            throw CameraCloudClientError.invalidRequest
        }
        let region: NormalizedRect?
        if let local = entity.region {
            guard [local.x, local.y, local.width, local.height].allSatisfy(CameraCloudEvidenceWire.unit),
                  local.width > 0, local.height > 0,
                  local.x + local.width <= 1, local.y + local.height <= 1 else {
                throw CameraCloudClientError.invalidRequest
            }
            // Aggregation/S1 keeps Vision's bottom-left coordinates. The prepared JPEG
            // is already oriented and contains the complete image, without preview crop.
            region = NormalizedRect(x: local.x, y: 1 - (local.y + local.height),
                                    width: local.width, height: local.height)
        } else {
            guard entity.kind == .frame || entity.kind == .backgroundArea else {
                throw CameraCloudClientError.invalidRequest
            }
            region = nil
        }
        return CameraCloudEvidenceWire.Entity(
            entity_ref: entity.entityRef, kind: entity.kind, region: region,
            detector_label: entity.detectorLabel, confidence: entity.detectorConfidence
        )
    }

    private final class CancellationState: @unchecked Sendable {
        private let lock = NSLock()
        private var token: String?
        private var cancelled = false
        private var completed = false

        func recordContentAttempt(token: String) {
            lock.lock()
            if !cancelled && !completed { self.token = token }
            lock.unlock()
        }

        func finish() {
            lock.lock()
            completed = true
            token = nil
            lock.unlock()
        }

        func cancel() -> String? {
            lock.lock()
            defer { lock.unlock() }
            guard !cancelled && !completed else { return nil }
            cancelled = true
            let existing = token
            token = nil
            return existing
        }
    }

    /// Ends the caller's wait even when an OS App Attest callback cannot be cancelled.
    /// The late callback only resolves this closed wait; it never owns an image upload.
    private final class TokenWait: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: Result<String?, Error>?
        private var continuation: CheckedContinuation<String?, Error>?
        private var acquisition: Task<Void, Never>?
        private var timer: Task<Void, Never>?

        var isActive: Bool {
            lock.lock()
            defer { lock.unlock() }
            return completion == nil
        }

        func install(_ continuation: CheckedContinuation<String?, Error>) -> Bool {
            lock.lock()
            let result = completion
            if result == nil { self.continuation = continuation }
            lock.unlock()
            if let result { continuation.resume(with: result) }
            return result == nil
        }

        func own(acquisition: Task<Void, Never>, timer: Task<Void, Never>) {
            lock.lock()
            let finished = completion != nil
            if !finished { self.acquisition = acquisition; self.timer = timer }
            lock.unlock()
            if finished { acquisition.cancel(); timer.cancel() }
        }

        func finish(_ result: Result<String?, Error>) {
            lock.lock()
            guard completion == nil else { lock.unlock(); return }
            completion = result
            let continuation = self.continuation
            let acquisition = self.acquisition
            let timer = self.timer
            self.continuation = nil
            self.acquisition = nil
            self.timer = nil
            lock.unlock()
            acquisition?.cancel()
            timer?.cancel()
            continuation?.resume(with: result)
        }
    }
}

private extension Array where Element == String {
    func containsAll(_ values: Dictionary<String, Bool>.Keys) -> Bool {
        Set(values).isSubset(of: Set(self))
    }
}
