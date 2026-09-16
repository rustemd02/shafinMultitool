//
//  SceneGenerationAPIContracts.swift
//  shafinMultitool
//
//  M12-003: versioned Scene Generation job API contracts mirroring the
//  frozen backend/openapi-scene-v1.yaml + backend/schemas/
//  scene-job-v1.schema.json. No network code, no provider credentials, no
//  live host: the service host stays a placeholder until deployment config
//  selects it, and the M5-025 client must validate every decoded payload
//  against these contracts before it reaches project state.
//

import Foundation

/// Transport envelope versions frozen by M12-003.
enum SceneAPIVersion {
    static let backendSchemaVersion = "scene-api-v1"
    static let scriptSchemaVersion = "scene-script-v1"
    static let placeholderHost = "https://scene-generation.set-os.local/v1"
}

/// Terminal job states from the frozen API. Raw values match the OpenAPI
/// JobStatusValue enum exactly.
enum SceneJobStatusValue: String, Codable, Equatable, Sendable {
    case pending
    case running
    case awaitingClarification = "awaiting_clarification"
    case complete
    case failed
    case cancelled
}

/// Typed server failure codes from the frozen API.
enum SceneJobFailureCode: String, Codable, Equatable, Sendable {
    case invalidRequest = "invalid_request"
    case providerError = "provider_error"
    case timeout
    case killSwitch = "kill_switch"
    case cancelled
    case internalFailure = "internal"
}

/// Typed failure payload. `killSwitch` is terminal: the M5-025 client must
/// stop issuing new jobs until deployment config clears it.
struct SceneJobFailure: Codable, Equatable, Sendable {
    let code: SceneJobFailureCode
    let message: String
}

/// Job status envelope. Terminal branches are mutually exclusive by
/// construction: exactly one of result/clarification/failure is present
/// for the matching status, none for pending/running.
struct SceneJobStatus: Codable, Equatable, Sendable {
    let jobID: String
    let requestID: UUID
    let status: SceneJobStatusValue
    let result: SceneJobResult?
    let clarification: SceneClarificationPayload?
    let failure: SceneJobFailure?
    let schemaVersionBackend: String
    let modelVersion: String
    let promptVersion: String
    let providerName: String
    let providerVersion: String
    let requestHash: String
    let idempotencyKey: String
    let serverTime: Date

    enum CodingKeys: String, CodingKey {
        case jobID = "job_id"
        case requestID = "request_id"
        case status
        case result
        case clarification
        case failure
        case schemaVersionBackend = "schema_version_backend"
        case modelVersion = "model_version"
        case promptVersion = "prompt_version"
        case providerName = "provider_name"
        case providerVersion = "provider_version"
        case requestHash = "request_hash"
        case idempotencyKey = "idempotency_key"
        case serverTime = "server_time"
    }
}

/// Complete-branch result. The scene script payload reuses the M3-023
/// scene-script-v1 shape; versions must equal the envelope triple.
struct SceneJobResult: Codable, Equatable, Sendable {
    let status: String
    let sceneScript: SceneScript
    let modelVersion: String
    let promptVersion: String
    let schemaVersion: String
    let warnings: [String]

    enum CodingKeys: String, CodingKey {
        case status
        case sceneScript = "scene_script"
        case modelVersion = "model_version"
        case promptVersion = "prompt_version"
        case schemaVersion = "schema_version"
        case warnings
    }
}

/// Create-job request body. Media fields are forbidden by construction:
/// there is no image/audio/video member to fill (M12-004 owns the
/// request-limits proof; this type makes a media-bearing request
/// unrepresentable).
struct SceneCreateJobRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let clientBuild: String
    let schemaVersion: String
    let locale: String
    let scriptText: String
    let markedObjectIDs: [String]
    let maximumScenes: Int
    let previousJobID: String?
    let requestHash: String
    let schemaVersionBackend: String
    let modelVersion: String
    let promptVersion: String
    let providerName: String
    let providerVersion: String

    init(
        requestID: UUID,
        clientBuild: String,
        schemaVersion: String,
        locale: String,
        scriptText: String,
        markedObjectIDs: [String],
        maximumScenes: Int,
        previousJobID: String?,
        requestHash: String,
        schemaVersionBackend: String,
        modelVersion: String,
        promptVersion: String,
        providerName: String,
        providerVersion: String
    ) {
        self.requestID = requestID
        self.clientBuild = clientBuild
        self.schemaVersion = schemaVersion
        self.locale = locale
        self.scriptText = scriptText
        self.markedObjectIDs = markedObjectIDs
        self.maximumScenes = maximumScenes
        self.previousJobID = previousJobID
        self.requestHash = requestHash
        self.schemaVersionBackend = schemaVersionBackend
        self.modelVersion = modelVersion
        self.promptVersion = promptVersion
        self.providerName = providerName
        self.providerVersion = providerVersion
    }

    private struct MarkedObjectPayload: Codable {
        let canonicalID: String

        enum CodingKeys: String, CodingKey {
            case canonicalID = "canonical_id"
        }
    }

    private struct ConstraintsPayload: Codable {
        let maximumScenes: Int

        enum CodingKeys: String, CodingKey {
            case maximumScenes = "maximum_scenes"
        }
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case clientBuild = "client_build"
        case schemaVersion = "schema_version"
        case locale
        case scriptText = "script_text"
        case markedObjectIDs = "marked_objects"
        case constraints
        case maximumScenes = "maximum_scenes"
        case previousJobID = "previous_job_id"
        case requestHash = "request_hash"
        case schemaVersionBackend = "schema_version_backend"
        case modelVersion = "model_version"
        case promptVersion = "prompt_version"
        case providerName = "provider_name"
        case providerVersion = "provider_version"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard !container.contains(.maximumScenes) else {
            throw DecodingError.dataCorruptedError(
                forKey: .maximumScenes,
                in: container,
                debugDescription: "maximum_scenes must be nested under constraints"
            )
        }
        requestID = try container.decode(UUID.self, forKey: .requestID)
        clientBuild = try container.decode(String.self, forKey: .clientBuild)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        locale = try container.decode(String.self, forKey: .locale)
        scriptText = try container.decode(String.self, forKey: .scriptText)
        if container.contains(.markedObjectIDs) {
            markedObjectIDs = try container
                .decode([MarkedObjectPayload].self, forKey: .markedObjectIDs)
                .map(\.canonicalID)
        } else {
            markedObjectIDs = []
        }
        if container.contains(.constraints) {
            maximumScenes = try container
                .decode(ConstraintsPayload.self, forKey: .constraints)
                .maximumScenes
        } else {
            maximumScenes = 1
        }
        previousJobID = try container.decodeIfPresent(String.self, forKey: .previousJobID)
        requestHash = try container.decode(String.self, forKey: .requestHash)
        schemaVersionBackend = try container.decode(String.self, forKey: .schemaVersionBackend)
        modelVersion = try container.decode(String.self, forKey: .modelVersion)
        promptVersion = try container.decode(String.self, forKey: .promptVersion)
        providerName = try container.decode(String.self, forKey: .providerName)
        providerVersion = try container.decode(String.self, forKey: .providerVersion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(clientBuild, forKey: .clientBuild)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(locale, forKey: .locale)
        try container.encode(scriptText, forKey: .scriptText)
        try container.encode(
            markedObjectIDs.map(MarkedObjectPayload.init(canonicalID:)),
            forKey: .markedObjectIDs
        )
        try container.encode(
            ConstraintsPayload(maximumScenes: maximumScenes),
            forKey: .constraints
        )
        try container.encodeIfPresent(previousJobID, forKey: .previousJobID)
        try container.encode(requestHash, forKey: .requestHash)
        try container.encode(schemaVersionBackend, forKey: .schemaVersionBackend)
        try container.encode(modelVersion, forKey: .modelVersion)
        try container.encode(promptVersion, forKey: .promptVersion)
        try container.encode(providerName, forKey: .providerName)
        try container.encode(providerVersion, forKey: .providerVersion)
    }
}

/// Clarification answer body: exactly one of selected option or free text.
struct SceneClarificationAPIPayload: Codable, Equatable, Sendable {
    let clarificationID: String
    let requestID: UUID
    let epoch: UInt
    let selectedOptionID: String?
    let freeText: String?

    enum CodingKeys: String, CodingKey {
        case clarificationID = "clarification_id"
        case requestID = "request_id"
        case epoch
        case selectedOptionID = "selected_option_id"
        case freeText = "free_text"
    }
}

/// Fail-closed validation of a decoded job status against the frozen
/// contract. Returns the terminal payload or a typed rejection the
/// M5-025 client must surface without touching project state.
enum SceneJobValidation: Sendable {
    static func validate(_ status: SceneJobStatus) -> SceneJobValidationResult {
        guard status.schemaVersionBackend == SceneAPIVersion.backendSchemaVersion else {
            return .rejected(.unknownBackendSchemaVersion)
        }
        guard status.requestHash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            return .rejected(.malformedRequestHash)
        }
        switch status.status {
        case .pending, .running:
            guard status.result == nil, status.clarification == nil, status.failure == nil else {
                return .rejected(.unexpectedTerminalPayload)
            }
            return .notTerminal
        case .complete:
            guard let result = status.result,
                  status.clarification == nil, status.failure == nil else {
                return .rejected(.missingOrMixedTerminalPayload)
            }
            guard result.schemaVersion == SceneAPIVersion.scriptSchemaVersion else {
                return .rejected(.unknownScriptSchemaVersion)
            }
            guard result.modelVersion == status.modelVersion,
                  result.promptVersion == status.promptVersion else {
                return .rejected(.versionTripleMismatch)
            }
            return .complete(result)
        case .awaitingClarification:
            guard let clarification = status.clarification,
                  status.result == nil, status.failure == nil else {
                return .rejected(.missingOrMixedTerminalPayload)
            }
            guard clarification.requestID == status.requestID else {
                return .rejected(.staleClarificationBinding)
            }
            return .awaitingClarification(clarification)
        case .failed, .cancelled:
            guard let failure = status.failure,
                  status.result == nil, status.clarification == nil else {
                return .rejected(.missingOrMixedTerminalPayload)
            }
            if failure.code == .killSwitch {
                return .rejected(.killSwitchEngaged)
            }
            return .failed(failure)
        }
    }
}

enum SceneJobValidationResult: Equatable, Sendable {
    case notTerminal
    case complete(SceneJobResult)
    case awaitingClarification(SceneClarificationPayload)
    case failed(SceneJobFailure)
    case rejected(SceneJobRejection)
}

enum SceneJobRejection: String, Equatable, Sendable {
    case unknownBackendSchemaVersion
    case unknownScriptSchemaVersion
    case malformedRequestHash
    case missingOrMixedTerminalPayload
    case unexpectedTerminalPayload
    case versionTripleMismatch
    case staleClarificationBinding
    case killSwitchEngaged
}
