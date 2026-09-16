import CryptoKit
import Foundation

enum ScenePlanProviderRoute: String, Codable, Sendable {
    case localProvider, remoteService, ruleFallback
}

/// Source identity travels beside semantic model output. Remote identities are
/// declarations validated against the job protocol; local artifact identities
/// are hashes of the file actually selected for the specific loaded context.
enum SceneGenerationContributor: Codable, Equatable, Sendable {
    case remoteService(SceneRemoteGenerationReceipt)
    case localModel(SceneLocalGenerationReceipt)
    case deterministicRules(componentVersion: String)
    case unknown(stage: Stage)

    enum Stage: String, Codable, Sendable {
        case planIR, eventTable, patchOps, semanticRepair
        case legacyChunk, unrecordedSource
    }
}

struct SceneRemoteGenerationReceipt: Codable, Equatable, Sendable {
    let jobID: String
    let requestID: UUID
    let requestHash: String
    let idempotencyKey: String
    let backendSchemaVersion: String
    let scriptSchemaVersion: String
    let modelVersion: String
    let promptVersion: String
    let providerName: String
    let providerVersion: String
}

struct SceneLocalGenerationReceipt: Codable, Equatable, Sendable {
    let stage: SceneGenerationContributor.Stage
    let artifact: SceneLocalModelArtifact?
    let promptSHA256: String
    let grammarSHA256: String?
    let grammarApplied: Bool
    let maximumTokens: Int
    let temperature: Float
    let samplingProfile: String
}

struct SceneLocalModelArtifact: Codable, Equatable, Sendable {
    let filename: String
    let sha256: String
    let byteCount: UInt64

    /// Called once per context load. It does not load an entire GGUF into RAM.
    /// Hashing failure is unknown identity, never permission to invent a version.
    static func identify(at url: URL) throws -> SceneLocalModelArtifact {
        let before = fingerprint(at: url)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var count: UInt64 = 0
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            hasher.update(data: bytes)
            count += UInt64(bytes.count)
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard before != nil, before == fingerprint(at: url),
              let expectedSize = attributes[.size] as? NSNumber,
              count == expectedSize.uint64Value else {
            throw CocoaError(.fileReadUnknown)
        }
        return SceneLocalModelArtifact(
            filename: url.lastPathComponent,
            sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
            byteCount: count
        )
    }

    /// FileManager performs a fresh stat; URL resource values may be cached.
    static func fingerprint(at url: URL) -> String? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let device = a[.systemNumber] as? NSNumber,
              let inode = a[.systemFileNumber] as? NSNumber,
              let size = a[.size] as? NSNumber,
              let modified = a[.modificationDate] as? Date else { return nil }
        return "\(device)|\(inode)|\(size)|\(modified.timeIntervalSince1970)"
    }
}

struct SceneChunkGenerationProvenance: Codable, Equatable, Sendable {
    let sceneID: String
    let chunkID: String
    let chunkIndex: Int
    let sourceRange: ScriptOffsetRange
    let sourceTextSHA256: String
    let runtimeMode: String?
    let providerRoute: ScenePlanProviderRoute?
    let contributors: [SceneGenerationContributor]

    init(
        sceneID: String, chunkID: String, chunkIndex: Int,
        sourceRange: ScriptOffsetRange, sourceText: String,
        runtimeMode: String?, providerRoute: ScenePlanProviderRoute? = nil,
        contributors: [SceneGenerationContributor]
    ) {
        self.sceneID = sceneID
        self.chunkID = chunkID
        self.chunkIndex = chunkIndex
        self.sourceRange = sourceRange
        self.sourceTextSHA256 = GenerationProvenance.sha256(sourceText)
        self.runtimeMode = runtimeMode
        self.providerRoute = providerRoute
        self.contributors = contributors.isEmpty ? [.unknown(stage: .unrecordedSource)] : contributors
    }
}

/// Version 1 is the historical three-field stamp. It is decoded and retained
/// verbatim, including its unverified modelContractVersion; it is never upgraded
/// into a verified Scene origin. Version 2 records accepted direct/chunk sources.
struct GenerationProvenance: Codable, Equatable, Sendable {
    let formatVersion: Int
    let generatorVersion: String
    let modelContractVersion: String?
    let schemaVersion: String
    let appVersion: String?
    let appBuild: String?
    let sourceTextSHA256: String?
    let directContributors: [SceneGenerationContributor]?
    let chunks: [SceneChunkGenerationProvenance]?
    var lastUserModification: UserModification?

    struct UserModification: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case scriptEdit, actorBeatPosition, actorTrackPosition, spatialReplan
        }
        let kind: Kind
        let timestamp: Date
    }

    enum CodingKeys: String, CodingKey {
        case formatVersion, generatorVersion, modelContractVersion, schemaVersion
        case appVersion, appBuild, sourceTextSHA256, directContributors, chunks, lastUserModification
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 1
        generatorVersion = try c.decode(String.self, forKey: .generatorVersion)
        modelContractVersion = try c.decodeIfPresent(String.self, forKey: .modelContractVersion)
        schemaVersion = try c.decode(String.self, forKey: .schemaVersion)
        appVersion = try c.decodeIfPresent(String.self, forKey: .appVersion)
        appBuild = try c.decodeIfPresent(String.self, forKey: .appBuild)
        sourceTextSHA256 = try c.decodeIfPresent(String.self, forKey: .sourceTextSHA256)
        directContributors = try c.decodeIfPresent([SceneGenerationContributor].self, forKey: .directContributors)
        chunks = try c.decodeIfPresent([SceneChunkGenerationProvenance].self, forKey: .chunks)
        lastUserModification = try c.decodeIfPresent(UserModification.self, forKey: .lastUserModification)
    }

    private init(
        sourceText: String,
        directContributors: [SceneGenerationContributor]?,
        chunks: [SceneChunkGenerationProvenance]?
    ) {
        formatVersion = 2
        generatorVersion = "scene-generator-v1"
        modelContractVersion = nil
        schemaVersion = SceneAPIVersion.scriptSchemaVersion
        appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        sourceTextSHA256 = Self.sha256(sourceText)
        self.directContributors = directContributors
        self.chunks = chunks
        lastUserModification = nil
    }

    static func direct(
        sourceText: String, contributors: [SceneGenerationContributor]?
    ) -> Self {
        Self(
            sourceText: sourceText,
            directContributors: contributors?.isEmpty == false ? contributors : [.unknown(stage: .unrecordedSource)],
            chunks: nil
        )
    }

    static func activeScene(
        sceneID: String?, sourceText: String, chunks: [SceneChunk]
    ) -> Self {
        guard let sceneID else {
            return .direct(sourceText: sourceText, contributors: nil)
        }
        let selected = chunks.filter { $0.sceneID == sceneID }.sorted { $0.chunkIndex < $1.chunkIndex }
        guard !selected.isEmpty else {
            return .direct(sourceText: sourceText, contributors: nil)
        }
        return Self(
            sourceText: sourceText,
            directContributors: nil,
            chunks: selected.map { chunk in
                chunk.generationProvenance ?? SceneChunkGenerationProvenance(
                    sceneID: chunk.sceneID, chunkID: chunk.chunkID, chunkIndex: chunk.chunkIndex,
                    sourceRange: chunk.sourceRange, sourceText: chunk.sourceText,
                    runtimeMode: nil, contributors: [.unknown(stage: .legacyChunk)]
                )
            }
        )
    }

    var acceptedContributors: [SceneGenerationContributor] {
        directContributors ?? chunks?.flatMap(\.contributors) ?? [.unknown(stage: .unrecordedSource)]
    }

    func recordingUserModification(_ kind: UserModification.Kind, at timestamp: Date = Date()) -> Self {
        var changed = self
        changed.lastUserModification = UserModification(kind: kind, timestamp: timestamp)
        return changed
    }

    static func sha256(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
