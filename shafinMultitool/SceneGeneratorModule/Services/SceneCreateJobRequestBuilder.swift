//
//  SceneCreateJobRequestBuilder.swift
//  shafinMultitool
//
//  M12-004: client-side request builder enforcing the frozen request
//  limits. The builder accepts only the allowlisted payload (UTF-8
//  screenplay text, locale, marked-object identifiers, constraints,
//  client/build/schema metadata) and computes the lowercase-hex SHA-256
//  request hash over the canonical JSON. Media and personal-data fields
//  are unrepresentable: there is no parameter for frames, audio,
//  contacts, advertising IDs, or file uploads.
//

import CryptoKit
import Foundation

/// Fail-closed builder for the frozen create-job request body.
enum SceneCreateJobRequestBuilder {
    static let maximumTextCharacters = 4000
    static let maximumTextUTF8Bytes = 64 * 1024
    static let maximumMarkedObjects = 32
    static let maximumScenes = 8

    static func build(
        requestID: UUID,
        clientBuild: String,
        locale: String,
        scriptText: String,
        markedObjectIDs: [String],
        maximumScenes: Int,
        previousJobID: String?,
        modelVersion: String,
        promptVersion: String,
        providerName: String,
        providerVersion: String
    ) -> Result<SceneCreateJobRequest, SceneRequestBuildError> {
        guard locale == "ru" || locale == "en" else {
            return .failure(.unsupportedLocale)
        }
        guard !scriptText.isEmpty, scriptText.count <= maximumTextCharacters else {
            return .failure(.textLengthViolation)
        }
        guard scriptText.utf8.count <= maximumTextUTF8Bytes else {
            return .failure(.textLengthViolation)
        }
        guard markedObjectIDs.count <= maximumMarkedObjects,
              markedObjectIDs.allSatisfy({ !$0.isEmpty && $0.count <= 128 }) else {
            return .failure(.markedObjectsViolation)
        }
        guard (1...Self.maximumScenes).contains(maximumScenes) else {
            return .failure(.constraintsViolation)
        }
        let requestWithoutHash = SceneCreateJobRequest(
            requestID: requestID,
            clientBuild: clientBuild,
            schemaVersion: SceneAPIVersion.scriptSchemaVersion,
            locale: locale,
            scriptText: scriptText,
            markedObjectIDs: markedObjectIDs,
            maximumScenes: maximumScenes,
            previousJobID: previousJobID,
            requestHash: "",
            schemaVersionBackend: SceneAPIVersion.backendSchemaVersion,
            modelVersion: modelVersion,
            promptVersion: promptVersion,
            providerName: providerName,
            providerVersion: providerVersion
        )
        let canonicalData: Data
        do {
            let encoded = try JSONEncoder().encode(requestWithoutHash)
            guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
                return .failure(.encodingFailure)
            }
            object.removeValue(forKey: "request_hash")
            canonicalData = try JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
        } catch {
            return .failure(.encodingFailure)
        }
        let digest = SHA256.hash(data: canonicalData)
        let requestHash = digest.map { String(format: "%02x", $0) }.joined()
        return .success(
            SceneCreateJobRequest(
                requestID: requestID,
                clientBuild: clientBuild,
                schemaVersion: SceneAPIVersion.scriptSchemaVersion,
                locale: locale,
                scriptText: scriptText,
                markedObjectIDs: markedObjectIDs,
                maximumScenes: maximumScenes,
                previousJobID: previousJobID,
                requestHash: requestHash,
                schemaVersionBackend: SceneAPIVersion.backendSchemaVersion,
                modelVersion: modelVersion,
                promptVersion: promptVersion,
                providerName: providerName,
                providerVersion: providerVersion
            )
        )
    }
}

enum SceneRequestBuildError: String, Equatable, Sendable, Error {
    case unsupportedLocale
    case textLengthViolation
    case markedObjectsViolation
    case constraintsViolation
    case encodingFailure
}
