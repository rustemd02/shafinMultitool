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
        let canonical = canonicalJSON(
            requestID: requestID,
            clientBuild: clientBuild,
            locale: locale,
            scriptText: scriptText,
            markedObjectIDs: markedObjectIDs,
            maximumScenes: maximumScenes,
            previousJobID: previousJobID,
            modelVersion: modelVersion,
            promptVersion: promptVersion,
            providerName: providerName,
            providerVersion: providerVersion
        )
        let digest = SHA256.hash(data: Data(canonical.utf8))
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

    private static func canonicalJSON(
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
    ) -> String {
        var parts: [String] = [
            #""client_build":"\#(jsonEscape(clientBuild))""#,
            #""locale":"\#(jsonEscape(locale))""#,
            #""marked_objects":[\#(markedObjectIDs.map { #""\#(jsonEscape($0))""# }.joined(separator: ","))]"#,
            #""maximum_scenes":\#(maximumScenes)"#,
            #""model_version":"\#(jsonEscape(modelVersion))""#,
            #""prompt_version":"\#(jsonEscape(promptVersion))""#,
            #""provider_name":"\#(jsonEscape(providerName))""#,
            #""provider_version":"\#(jsonEscape(providerVersion))""#,
            #""request_id":"\#(requestID.uuidString)""#,
            #""schema_version":"\#(SceneAPIVersion.scriptSchemaVersion)""#,
            #""schema_version_backend":"\#(SceneAPIVersion.backendSchemaVersion)""#,
            #""script_text":"\#(jsonEscape(scriptText))""#
        ]
        if let previousJobID {
            parts.append(#""previous_job_id":"\#(jsonEscape(previousJobID))""#)
        }
        return "{\(parts.sorted().joined(separator: ","))}"
    }

    private static func jsonEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }
}

enum SceneRequestBuildError: String, Equatable, Sendable, Error {
    case unsupportedLocale
    case textLengthViolation
    case markedObjectsViolation
    case constraintsViolation
}
