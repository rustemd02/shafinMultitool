//
//  MarkedObjectMatcher.swift
//  shafinMultitool
//
//  Created on 28.01.2026.
//

import Foundation

/// Ссылка на размеченный объект, найденный в тексте
struct MarkedObjectReference {
    let markerId: UUID
    let markerName: String
    let matchedText: String        // Как именно упомянуто в тексте
    let position: Range<String.Index>  // Позиция в тексте
}

/// The only sources that may be attached to an object submitted to the
/// generator.  This is deliberately separate from `SceneObject`: the latter
/// is persisted project data and must remain backwards compatible.
enum SceneObjectBindingSource: String, Codable, Equatable {
    case marked
    case detected
    case virtual
}

/// Immutable metadata for one canonical object candidate in a generation
/// request. Marker IDs use the existing object_marked_<short-id> contract;
/// detection UUIDs remain observation provenance until a submitted
/// SceneObject reference owns the final canonical ID.
struct SceneObjectBinding: Codable, Equatable, Identifiable {
    let canonicalID: String
    let source: SceneObjectBindingSource
    let confidence: Float
    let name: String
    let aliases: [String]
    let objectType: SceneObject.ObjectType
    let worldPosition: Position3D?
    let markerID: UUID?
    let detectionID: UUID?

    var id: String { canonicalID }

    init(
        canonicalID: String,
        source: SceneObjectBindingSource,
        confidence: Float,
        name: String,
        aliases: [String],
        objectType: SceneObject.ObjectType,
        worldPosition: Position3D?,
        markerID: UUID? = nil,
        detectionID: UUID? = nil
    ) {
        self.canonicalID = canonicalID
        self.source = source
        self.confidence = min(max(confidence, 0), 1)
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.aliases = Array(
            Set(
                aliases.filter {
                    !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                }
            )
        ).sorted()
        self.objectType = objectType
        self.worldPosition = worldPosition
        self.markerID = markerID
        self.detectionID = detectionID
    }

    fileprivate static func stableOrdering(_ lhs: Self, _ rhs: Self) -> Bool {
        let lhsID = lhs.canonicalID.lowercased()
        let rhsID = rhs.canonicalID.lowercased()
        if lhsID != rhsID { return lhsID < rhsID }

        func sourceRank(_ source: SceneObjectBindingSource) -> Int {
            switch source {
            case .marked: return 0
            case .detected: return 1
            case .virtual: return 2
            }
        }

        let lhsSource = sourceRank(lhs.source)
        let rhsSource = sourceRank(rhs.source)
        if lhsSource != rhsSource { return lhsSource < rhsSource }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.confidence > rhs.confidence
    }
}

/// The immutable input sampled at the submit boundary.  Arrays are sorted by
/// canonical ID, so equivalent requests produce equivalent results regardless
/// of the order in which AR callbacks delivered their candidates.
struct SceneObjectBindingRequestSnapshot: Codable, Equatable {
    let requestID: UUID
    let epoch: UInt
    let description: String
    let candidates: [SceneObjectBinding]
    let aliasToObjectRef: [String: String]
    let ambiguousAliases: [String]
    let duplicateCanonicalIDs: [String]

    init(
        requestID: UUID,
        epoch: UInt,
        description: String,
        candidates: [SceneObjectBinding],
        aliasToObjectRef: [String: String] = [:]
    ) {
        self.init(
            requestID: requestID,
            epoch: epoch,
            description: description,
            candidates: candidates,
            aliasPairs: aliasToObjectRef.map { ($0.key, $0.value) }
        )
    }

    private init(
        requestID: UUID,
        epoch: UInt,
        description: String,
        candidates: [SceneObjectBinding],
        aliasPairs: [(String, String)]
    ) {
        self.requestID = requestID
        self.epoch = epoch
        self.description = description

        var grouped: [String: [SceneObjectBinding]] = [:]
        for candidate in candidates {
            grouped[candidate.canonicalID.lowercased(), default: []].append(candidate)
        }
        self.duplicateCanonicalIDs = grouped
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()

        // A duplicate canonical ID is retained once in the immutable
        // candidate list and reported separately.  This guarantees that no
        // downstream dictionary can contain duplicate IDs while the resolver
        // still fails closed for references to the collided ID.
        self.candidates = grouped.values
            .compactMap { $0.sorted(by: SceneObjectBinding.stableOrdering).first }
            .sorted(by: SceneObjectBinding.stableOrdering)

        let normalizedAliasPairs = aliasPairs.compactMap { rawAlias, objectRef -> (String, String)? in
            guard let alias = MarkedObjectMatcher.normalizedAlias(rawAlias),
                  !alias.isEmpty,
                  !objectRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (alias, objectRef)
        }
        let groupedAliases = Dictionary(grouping: normalizedAliasPairs, by: \.0)
        self.ambiguousAliases = groupedAliases
            .filter { Set($0.value.map { $0.1.lowercased() }).count > 1 }
            .map(\.key)
            .sorted()
        // Existing reference bindings are lookup hints only.  A conflicting
        // normalized alias is removed instead of picking the first/last entry,
        // which would reintroduce positional identity.
        self.aliasToObjectRef = groupedAliases.reduce(into: [:]) { result, entry in
            let refs = entry.value.map(\.1).sorted()
            if Set(refs.map { $0.lowercased() }).count == 1, let ref = refs.first {
                result[entry.key] = ref
            }
        }
    }

    func withAliasBindings(_ aliases: [String: String]) -> Self {
        Self(
            requestID: requestID,
            epoch: epoch,
            description: description,
            candidates: candidates,
            aliasToObjectRef: aliases
        )
    }

    func withAliasBindingPairs(_ aliases: [(String, String)]) -> Self {
        Self(
            requestID: requestID,
            epoch: epoch,
            description: description,
            candidates: candidates,
            aliasPairs: aliases
        )
    }
}

/// Typed resolution for one script object.  Missing and ambiguous are first
/// class states; neither creates a placeholder candidate or guesses by array
/// position.
struct SceneObjectBindingResolution: Codable, Equatable, Identifiable {
    enum State: String, Codable, Equatable {
        case bound
        case missing
        case ambiguous
    }

    let reference: String
    let state: State
    let binding: SceneObjectBinding?
    let candidateIDs: [String]
    let diagnostic: String?

    var id: String { reference }
    var isBound: Bool { state == .bound && binding != nil }

    static func bound(reference: String, binding: SceneObjectBinding) -> Self {
        Self(reference: reference, state: .bound, binding: binding, candidateIDs: [binding.canonicalID], diagnostic: nil)
    }

    static func missing(reference: String, candidateIDs: [String] = [], diagnostic: String) -> Self {
        Self(reference: reference, state: .missing, binding: nil, candidateIDs: candidateIDs, diagnostic: diagnostic)
    }

    static func ambiguous(reference: String, candidateIDs: [String], diagnostic: String) -> Self {
        Self(
            reference: reference,
            state: .ambiguous,
            binding: nil,
            candidateIDs: Array(Set(candidateIDs)).sorted(),
            diagnostic: diagnostic
        )
    }
}

/// Binding output owned by one immutable request identity.
struct SceneObjectBindingResult: Codable, Equatable {
    let request: SceneObjectBindingRequestSnapshot
    let resolutions: [SceneObjectBindingResolution]
    let duplicateScriptReferences: [String]
    let diagnostics: [String]

    var requestID: UUID { request.requestID }
    var epoch: UInt { request.epoch }

    func resolution(for reference: String) -> SceneObjectBindingResolution? {
        resolutions.first { $0.reference == reference }
    }

    func binding(for reference: String) -> SceneObjectBinding? {
        resolution(for: reference)?.binding
    }

    var boundBindings: [SceneObjectBinding] {
        resolutions.compactMap(\.binding)
    }
}

/// Класс для сопоставления текста с размеченными объектами
final class MarkedObjectMatcher {

    /// World-space distance below which a marker and a detector observation
    /// may be treated as the same physical object. Missing/invalid positions
    /// never satisfy this threshold and therefore remain ambiguous.
    static let markedDetectionConvergenceTolerance: Float = 0.20
    
    private let lemmatizer: Lemmatizer
    
    init(lemmatizer: Lemmatizer) {
        self.lemmatizer = lemmatizer
    }

    /// Normalizes aliases for lookup only.  It intentionally does not change
    /// the canonical ID stored in a project or request.
    static func normalizedAlias(_ raw: String) -> String? {
        let folded = raw.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "ru_RU")
        )
        let tokens = folded
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let normalized = tokens.joined(separator: " ")
        return normalized.isEmpty ? nil : normalized
    }

    /// Builds a fail-closed alias map for the persisted planning contract.
    /// Conflicting normalized aliases are omitted rather than overwritten.
    static func uniqueAliasBindings(_ pairs: [(String, String)]) -> [String: String] {
        let normalizedPairs = pairs.compactMap { rawAlias, objectRef -> (String, String)? in
            guard let alias = normalizedAlias(rawAlias),
                  !alias.isEmpty,
                  !objectRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            return (alias, objectRef)
        }
        let grouped = Dictionary(grouping: normalizedPairs, by: \.0)
        return grouped.reduce(into: [:]) { result, entry in
            let refs = entry.value.map(\.1).sorted()
            if Set(refs.map { $0.lowercased() }).count == 1, let ref = refs.first {
                result[entry.key] = ref
            }
        }
    }

    static func makeRequestSnapshot(
        requestID: UUID,
        epoch: UInt,
        description: String,
        markedObjects: [MarkedObject],
        detectedObjects: [DetectedObject],
        aliasToObjectRef: [String: String] = [:]
    ) -> SceneObjectBindingRequestSnapshot {
        let markedCandidates = markedObjects.map { marker in
            let aliases = [marker.name, marker.type.rawValue]
                + KeywordsMapping.objectKeywords
                    .filter { $0.value == marker.type }
                    .map(\.key)
            return SceneObjectBinding(
                canonicalID: marker.canonicalMarkedObjectID,
                source: .marked,
                confidence: 1,
                name: marker.name.isEmpty ? marker.type.rawValue : marker.name,
                aliases: aliases,
                objectType: marker.type,
                worldPosition: marker.worldPosition,
                markerID: marker.id
            )
        }
        let detectedCandidates = detectedObjects.compactMap(ObjectDetectionBridge.makeBindingCandidate)
        return SceneObjectBindingRequestSnapshot(
            requestID: requestID,
            epoch: epoch,
            description: description,
            candidates: markedCandidates + detectedCandidates,
            aliasToObjectRef: aliasToObjectRef
        )
    }

    /// Resolves every script object against the immutable submit snapshot.
    /// The resolver uses explicit IDs and unique aliases first, then a
    /// deterministic type match.  Same-type ambiguity is never resolved by
    /// array order.
    func resolveObjectBindings(
        scriptObjects: [SceneObject],
        request: SceneObjectBindingRequestSnapshot
    ) -> SceneObjectBindingResult {
        let candidates = request.candidates.sorted(by: SceneObjectBinding.stableOrdering)
        let candidateByID = Dictionary(uniqueKeysWithValues: candidates.map { ($0.canonicalID.lowercased(), $0) })
        let duplicateCanonicalIDs = Set(request.duplicateCanonicalIDs.map { $0.lowercased() })

        var aliasCandidates: [String: [SceneObjectBinding]] = [:]
        for candidate in candidates {
            let aliases = candidate.aliases + [candidate.name, candidate.objectType.rawValue]
            for rawAlias in aliases {
                guard let alias = Self.normalizedAlias(rawAlias) else { continue }
                aliasCandidates[alias, default: []].append(candidate)
            }
        }
        for alias in aliasCandidates.keys {
            let unique = Dictionary(grouping: aliasCandidates[alias] ?? [], by: { $0.canonicalID.lowercased() })
                .values
                .compactMap { $0.sorted(by: SceneObjectBinding.stableOrdering).first }
                .sorted(by: SceneObjectBinding.stableOrdering)
            aliasCandidates[alias] = unique
        }

        let groupedScriptObjects = Dictionary(grouping: scriptObjects, by: \.id)
        let duplicateScriptReferences = groupedScriptObjects
            .filter { $0.value.count > 1 }
            .map(\.key)
            .sorted()

        func candidateIDs(_ values: [SceneObjectBinding]) -> [String] {
            Array(Set(values.map(\.canonicalID))).sorted()
        }

        func submissionBinding(
            _ candidate: SceneObjectBinding,
            reference: String
        ) -> SceneObjectBinding {
            guard candidate.source == .detected else { return candidate }
            // A detection UUID is observation provenance, not a stable entity
            // ID.  The submitted SceneObject reference owns the final
            // canonical identity.
            return SceneObjectBinding(
                canonicalID: reference,
                source: candidate.source,
                confidence: candidate.confidence,
                name: candidate.name,
                aliases: candidate.aliases,
                objectType: candidate.objectType,
                worldPosition: candidate.worldPosition,
                markerID: candidate.markerID,
                detectionID: candidate.detectionID
            )
        }

        func choose(
            reference: String,
            candidates values: [SceneObjectBinding],
            objectType: SceneObject.ObjectType,
            reason: String
        ) -> SceneObjectBindingResolution {
            let uniqueAll = Dictionary(grouping: values, by: { $0.canonicalID.lowercased() })
                .values
                .compactMap { $0.sorted(by: SceneObjectBinding.stableOrdering).first }
                .sorted(by: SceneObjectBinding.stableOrdering)
            let unique = uniqueAll.filter { $0.objectType == objectType }
            guard !unique.isEmpty else {
                return .missing(
                    reference: reference,
                    candidateIDs: candidateIDs(uniqueAll),
                    diagnostic: "type_mismatch"
                )
            }
            let ids = candidateIDs(unique)
            guard !ids.isEmpty else {
                return .missing(reference: reference, diagnostic: reason)
            }
            if ids.contains(where: { duplicateCanonicalIDs.contains($0.lowercased()) }) {
                return .ambiguous(
                    reference: reference,
                    candidateIDs: ids,
                    diagnostic: "duplicate_canonical_id"
                )
            }
            if unique.count == 1, let only = unique.first {
                return .bound(reference: reference, binding: submissionBinding(only, reference: reference))
            }

            // A marker owns identity only after one marker and one detector
            // have supplied finite, colocated world positions. A shared type
            // or alias alone is not evidence of one physical object.
            let marked = unique.filter { $0.source == .marked }
            let detected = unique.filter { $0.source == .detected }
            if marked.count == 1, detected.count == 1,
               let markerPosition = marked[0].worldPosition,
               let detectionPosition = detected[0].worldPosition {
                let distance = markerPosition.distance(to: detectionPosition)
                if distance.isFinite, distance <= Self.markedDetectionConvergenceTolerance {
                    let marker = marked[0]
                    let observation = detected[0]
                    let converged = SceneObjectBinding(
                        canonicalID: marker.canonicalID,
                        source: .marked,
                        confidence: max(marker.confidence, observation.confidence),
                        name: marker.name,
                        aliases: marker.aliases + observation.aliases,
                        objectType: marker.objectType,
                        worldPosition: marker.worldPosition,
                        markerID: marker.markerID,
                        detectionID: observation.detectionID
                    )
                    return .bound(reference: reference, binding: converged)
                }
            }
            return .ambiguous(reference: reference, candidateIDs: ids, diagnostic: "marked_detected_not_colocated")
        }

        func virtualBinding(reference: String, object: SceneObject) -> SceneObjectBindingResolution {
            let trimmedName = object.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let virtual = SceneObjectBinding(
                canonicalID: reference,
                source: .virtual,
                confidence: 0,
                name: trimmedName?.isEmpty == false ? trimmedName! : object.type.rawValue,
                aliases: [object.name ?? "", object.type.rawValue],
                objectType: object.type,
                worldPosition: nil
            )
            return .bound(reference: reference, binding: virtual)
        }

        func resolve(_ object: SceneObject) -> SceneObjectBindingResolution {
            let reference = object.id
            let referenceKey = reference.lowercased()
            if duplicateScriptReferences.contains(reference) {
                return .ambiguous(
                    reference: reference,
                    candidateIDs: [],
                    diagnostic: "duplicate_script_reference"
                )
            }

            if duplicateCanonicalIDs.contains(referenceKey) {
                return .ambiguous(
                    reference: reference,
                    candidateIDs: [reference],
                    diagnostic: "duplicate_canonical_id"
                )
            }
            if let explicit = candidateByID[referenceKey] {
                guard explicit.objectType == object.type else {
                    return .missing(
                        reference: reference,
                        candidateIDs: [explicit.canonicalID],
                        diagnostic: "type_mismatch"
                    )
                }
                return .bound(reference: reference, binding: submissionBinding(explicit, reference: reference))
            }
            let explicitReference = referenceKey.hasPrefix("object_marked_")
                || referenceKey.hasPrefix("object_detected_")
            if explicitReference {
                return .missing(reference: reference, diagnostic: "explicit_reference_missing")
            }

            if let objectName = object.name,
               let normalizedName = Self.normalizedAlias(objectName),
               let mappedRef = request.aliasToObjectRef[normalizedName] {
                let mappedKey = mappedRef.lowercased()
                if duplicateCanonicalIDs.contains(mappedKey) {
                    return .ambiguous(
                        reference: reference,
                        candidateIDs: [mappedRef],
                        diagnostic: "duplicate_alias_reference"
                    )
                }
                if let mappedCandidate = candidateByID[mappedKey] {
                    guard mappedCandidate.objectType == object.type else {
                        return .missing(
                            reference: reference,
                            candidateIDs: [mappedCandidate.canonicalID],
                            diagnostic: "type_mismatch"
                        )
                    }
                    return .bound(reference: reference, binding: submissionBinding(mappedCandidate, reference: reference))
                }
                if mappedKey.hasPrefix("object_marked_") || mappedKey.hasPrefix("object_detected_") {
                    return .missing(reference: reference, diagnostic: "alias_target_missing")
                }
                // ScenePlanIR may map an alias to a parser-owned virtual
                // reference (for example object_scene1_chair_1).  That
                // reference is not a physical candidate, so keep looking for
                // a submitted marker/detection with the same alias before
                // treating the object as virtual.
            }

            if let objectName = object.name,
               let normalizedName = Self.normalizedAlias(objectName) {
                if request.ambiguousAliases.contains(normalizedName) {
                    return .ambiguous(
                        reference: reference,
                        candidateIDs: aliasCandidates[normalizedName]?.map(\.canonicalID) ?? [],
                        diagnostic: "alias_ambiguous"
                    )
                }
                if let aliasMatches = aliasCandidates[normalizedName], !aliasMatches.isEmpty {
                    return choose(
                        reference: reference,
                        candidates: aliasMatches,
                        objectType: object.type,
                        reason: "alias_ambiguous"
                    )
                }
            }

            let mentionedMatches = candidates.filter { candidate in
                candidate.aliases.contains { alias in
                    containsLookupAlias(alias, in: request.description)
                }
            }
            if !mentionedMatches.isEmpty {
                let typeFiltered = mentionedMatches.filter { $0.objectType == object.type }
                if !typeFiltered.isEmpty {
                    return choose(
                        reference: reference,
                        candidates: typeFiltered,
                        objectType: object.type,
                        reason: "mentioned_alias_ambiguous"
                    )
                }
            }

            let typeMatches = candidates.filter { $0.objectType == object.type }
            if !typeMatches.isEmpty {
                return choose(
                    reference: reference,
                    candidates: typeMatches,
                    objectType: object.type,
                    reason: "same_type_ambiguous"
                )
            }

            guard !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .missing(reference: reference, diagnostic: "empty_reference")
            }
            return virtualBinding(reference: reference, object: object)
        }

        let initialResolutions = groupedScriptObjects.keys
            .sorted()
            .compactMap { groupedScriptObjects[$0]?.first }
            .map(resolve)
            .sorted { $0.reference < $1.reference }
        let boundProvenance = initialResolutions.flatMap { resolution -> [(String, String)] in
            guard let binding = resolution.binding else { return [] }
            var tokens = ["canonical:\(binding.canonicalID.lowercased())"]
            if let markerID = binding.markerID {
                tokens.append("marker:\(markerID.uuidString.lowercased())")
            }
            if let detectionID = binding.detectionID {
                tokens.append("detection:\(detectionID.uuidString.lowercased())")
            }
            return tokens.map { ($0, resolution.reference) }
        }
        let boundGroups = Dictionary(grouping: boundProvenance, by: \.0)
        let collidingReferences = Set(
            boundGroups.values
                .filter { $0.count > 1 }
                .flatMap { $0.map(\.1) }
        )
        let resolutions = initialResolutions.map { resolution in
            guard collidingReferences.contains(resolution.reference),
                  let binding = resolution.binding else {
                return resolution
            }
            return .ambiguous(
                reference: resolution.reference,
                candidateIDs: [binding.canonicalID],
                diagnostic: "candidate_already_bound"
            )
        }

        var diagnostics = request.duplicateCanonicalIDs.map { "duplicate_canonical_id:\($0)" }
        diagnostics.append(contentsOf: request.ambiguousAliases.map { "ambiguous_alias:\($0)" })
        diagnostics.append(contentsOf: duplicateScriptReferences.map { "duplicate_script_reference:\($0)" })
        diagnostics.append(contentsOf: resolutions.compactMap { resolution in
            guard resolution.state != .bound else { return nil }
            return "\(resolution.state.rawValue):\(resolution.reference):\(resolution.diagnostic ?? "unknown")"
        })
        return SceneObjectBindingResult(
            request: request,
            resolutions: resolutions,
            duplicateScriptReferences: duplicateScriptReferences,
            diagnostics: diagnostics.sorted()
        )
    }

    private func containsLookupAlias(_ rawAlias: String, in text: String) -> Bool {
        let lowercasedText = text.lowercased()
        let candidates = normalizedSearchCandidates(for: rawAlias.lowercased())
        return candidates.contains { candidate in
            lowercasedText.range(of: candidate) != nil
                || lemmatizer.textContainsKeyword(lowercasedText, keyword: candidate)
        }
    }
    
    // MARK: - Public API
    
    /// Находит все упоминания размеченных объектов в тексте
    /// - Parameters:
    ///   - text: Текст для поиска
    ///   - markedObjects: Список размеченных объектов
    /// - Returns: Массив ссылок на найденные объекты
    func findMarkedObjectReferences(
        in text: String,
        markedObjects: [MarkedObject]
    ) -> [MarkedObjectReference] {
        print("🔍 [MATCHER] Поиск упоминаний markedObjects в тексте: '\(text)'")
        print("🔍 [MATCHER] Размеченных объектов для поиска: \(markedObjects.count)")
        
        var references: [MarkedObjectReference] = []
        let lowercasedText = text.lowercased()
        
        for (index, marker) in markedObjects.enumerated() {
            print("🔍 [MATCHER] Проверка markedObject[\(index)]: name='\(marker.name)', type=\(marker.type.rawValue)")
            let markerName = marker.name.lowercased()
            let normalizedMarkerNames = normalizedSearchCandidates(for: markerName)
            
            // Ищем прямое упоминание имени маркера
            for candidate in normalizedMarkerNames {
                if let range = lowercasedText.range(of: candidate) {
                    print("🔍 [MATCHER]   Найдено прямое упоминание '\(candidate)'")
                    references.append(MarkedObjectReference(
                        markerId: marker.id,
                        markerName: marker.name,
                        matchedText: String(text[range]),
                        position: range
                    ))
                    break
                }
            }
            if references.last?.markerId == marker.id { continue }
            
            // Ищем через лемматизацию
            for candidate in normalizedMarkerNames {
                if lemmatizer.textContainsKeyword(lowercasedText, keyword: candidate) {
                    print("🔍 [MATCHER]   Найдено через лемматизацию '\(candidate)'")
                    // Находим точную позицию через поиск по словам
                    if let position = findWordPosition(in: lowercasedText, word: candidate) {
                        references.append(MarkedObjectReference(
                            markerId: marker.id,
                            markerName: marker.name,
                            matchedText: String(text[position]),
                            position: position
                        ))
                        break
                    }
                }
            }
            if references.last?.markerId == marker.id { continue }

            for candidate in normalizedMarkerNames {
                if let position = findMultiWordMarkerPosition(in: lowercasedText, markerName: candidate) {
                    print("🔍 [MATCHER]   Найдено по многословной лемме '\(candidate)'")
                    references.append(MarkedObjectReference(
                        markerId: marker.id,
                        markerName: marker.name,
                        matchedText: String(text[position]),
                        position: position
                    ))
                    break
                }
            }
            if references.last?.markerId == marker.id { continue }

            print("🔍 [MATCHER]   Не найдено упоминание '\(markerName)'")
            
            // Ищем с притяжательными местоимениями ("мой стол", "этот стол")
            let possessivePatterns = ["мой \(markerName)", "моя \(markerName)", "моё \(markerName)",
                                      "этот \(markerName)", "эта \(markerName)", "это \(markerName)",
                                      "тот \(markerName)", "та \(markerName)", "то \(markerName)"]
            
            for pattern in possessivePatterns {
                if lowercasedText.contains(pattern) {
                    if let range = lowercasedText.range(of: pattern) {
                        references.append(MarkedObjectReference(
                            markerId: marker.id,
                            markerName: marker.name,
                            matchedText: String(text[range]),
                            position: range
                        ))
                        break // Нашли одно упоминание, переходим к следующему маркеру
                    }
                }
            }
        }
        
        // Убираем дубликаты (если один маркер найден несколько раз, берём первое упоминание)
        var seenIds: Set<UUID> = []
        return references.filter { reference in
            if seenIds.contains(reference.markerId) {
                return false
            }
            seenIds.insert(reference.markerId)
            return true
        }
    }
    
    /// Проверяет, упоминается ли конкретный markedObject в тексте
    /// - Parameters:
    ///   - marker: Размеченный объект для проверки
    ///   - text: Текст для поиска
    /// - Returns: true, если объект упомянут в тексте
    func isMarkedObjectMentioned(
        _ marker: MarkedObject,
        in text: String
    ) -> Bool {
        let lowercasedText = text.lowercased()
        let markerName = marker.name.lowercased()
        
        // Прямое упоминание
        if lowercasedText.contains(markerName) {
            return true
        }
        
        // Через лемматизацию
        if lemmatizer.textContainsKeyword(lowercasedText, keyword: markerName) {
            return true
        }
        
        // С притяжательными местоимениями
        let possessivePatterns = ["мой \(markerName)", "моя \(markerName)", "моё \(markerName)",
                                  "этот \(markerName)", "эта \(markerName)", "это \(markerName)",
                                  "тот \(markerName)", "та \(markerName)", "то \(markerName)"]
        
        for pattern in possessivePatterns {
            if lowercasedText.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    /// Returns every marker that can represent the supplied surface word.
    /// A caller may bind only when this set has one member; array order never
    /// disambiguates repeated labels.
    func findMarkedObjectCandidates(byWord word: String, in markedObjects: [MarkedObject]) -> [MarkedObject] {
        let lowercasedWord = word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowercasedWord.isEmpty else { return [] }

        let candidates = markedObjects.filter { marker in
            let markerName = marker.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !markerName.isEmpty else { return false }
            return lowercasedWord == markerName
                || lemmatizer.matchesKeyword(lowercasedWord, keyword: markerName)
                || lowercasedWord.contains(markerName)
                || markerName.contains(lowercasedWord)
        }
        return candidates.sorted { lhs, rhs in
            if lhs.canonicalMarkedObjectID != rhs.canonicalMarkedObjectID {
                return lhs.canonicalMarkedObjectID < rhs.canonicalMarkedObjectID
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    /// Находит объект по слову из текста (с учётом markedObjects).
    /// Repeated labels fail closed instead of returning the first marker.
    func findMarkedObject(byWord word: String, in markedObjects: [MarkedObject]) -> MarkedObject? {
        let candidates = findMarkedObjectCandidates(byWord: word, in: markedObjects)
        return candidates.count == 1 ? candidates[0] : nil
    }
    
    // MARK: - Private Helpers
    
    /// Находит позицию слова в тексте с учётом лемматизации
    private func findWordPosition(in text: String, word: String) -> Range<String.Index>? {
        let lowercasedText = text.lowercased()
        let wordLemma = lemmatizer.lemmatize(word)
        
        // Пробуем найти через простое совпадение
        if let range = lowercasedText.range(of: word) {
            return range
        }
        
        // Ищем по лемме (более сложно, нужно разбить текст на слова)
        let words = lowercasedText.split(separator: " ").map(String.init)
        var currentIndex = lowercasedText.startIndex
        
        for textWord in words {
            let textWordLemma = lemmatizer.lemmatize(textWord)
            if textWordLemma == wordLemma || lemmatizer.matchesKeyword(textWord, keyword: word) {
                let wordStart = currentIndex
                // Безопасно вычисляем конец слова
                guard let wordEnd = lowercasedText.index(currentIndex, offsetBy: textWord.count, limitedBy: lowercasedText.endIndex),
                      wordEnd <= lowercasedText.endIndex,
                      wordStart < wordEnd else { continue }
                return wordStart..<wordEnd
            }
            
            // Перемещаем индекс на следующее слово
            if let nextSpace = lowercasedText[currentIndex...].range(of: " ") {
                currentIndex = nextSpace.upperBound
                // Проверяем что не вышли за границы
                guard currentIndex <= lowercasedText.endIndex else { break }
            } else {
                break
            }
        }
        
        return nil
    }

    private func findMultiWordMarkerPosition(in text: String, markerName: String) -> Range<String.Index>? {
        let markerTokens = markerName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard markerTokens.count > 1 else { return nil }

        let textTokens = text
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        let allTokensMatch = markerTokens.allSatisfy { markerToken in
            textTokens.contains { textToken in
                lemmatizer.matchesKeyword(textToken, keyword: markerToken)
                    || haveSharedStem(textToken, markerToken)
            }
        }
        guard allTokensMatch else { return nil }

        return findWordPosition(in: text, word: markerTokens[0])
    }

    private func haveSharedStem(_ lhs: String, _ rhs: String) -> Bool {
        let left = lemmatizer.lemmatize(lhs)
        let right = lemmatizer.lemmatize(rhs)
        guard left.count >= 3, right.count >= 3 else { return false }
        return String(left.prefix(3)) == String(right.prefix(3))
    }

    private func normalizedSearchCandidates(for markerName: String) -> [String] {
        let sanitized = markerName.replacingOccurrences(of: "_", with: " ")
        let tokens = sanitized.split(separator: " ").map(String.init)
        var candidates = [sanitized]
        if tokens.count > 1, ["мой", "моя", "моё", "мое", "наш", "наша", "этот", "эта", "тот", "та"].contains(tokens[0]) {
            candidates.append(tokens.dropFirst().joined(separator: " "))
        }
        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }
}
