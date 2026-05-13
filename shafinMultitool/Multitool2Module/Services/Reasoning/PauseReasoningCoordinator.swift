import Foundation

protocol ReasoningProvider: Sendable {
    var providerId: String { get }
    var capabilities: ReasoningCapabilities { get }

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse
}

struct ReasoningCapabilities: Equatable, Sendable {
    let supportsOffline: Bool
    let supportsRemote: Bool
    let supportsRussian: Bool
    let maxInputChars: Int
    let maxOutputChars: Int
}

struct ReasoningConstraints: Equatable, Sendable {
    let maxLatencyMs: Int
    let maxOutputTokens: Int
    let strictDeterministicGuard: Bool
    let allowSpeculativeTone: Bool

    static let pauseDefault = ReasoningConstraints(
        maxLatencyMs: 900,
        maxOutputTokens: 256,
        strictDeterministicGuard: true,
        allowSpeculativeTone: false
    )

    init(maxLatencyMs: Int,
         maxOutputTokens: Int,
         strictDeterministicGuard: Bool,
         allowSpeculativeTone: Bool) {
        self.maxLatencyMs = min(1_500, max(100, maxLatencyMs))
        self.maxOutputTokens = max(32, maxOutputTokens)
        self.strictDeterministicGuard = strictDeterministicGuard
        self.allowSpeculativeTone = allowSpeculativeTone
    }
}

struct ReasoningCorrelation: Equatable, Sendable {
    let pipelineVersion: String
    let contractVersion: String
    let providerConfigVersion: String
}

enum ReasoningViolation: String, Codable, Sendable, Hashable {
    case modeNotPause = "mode_not_pause"
    case unknownRuntimeId = "unknown_runtime_id"
    case attemptsToChangeVerdict = "attempts_to_change_verdict"
    case attemptsToChangeIssueTaxonomy = "attempts_to_change_issue_taxonomy"
    case attemptsToChangeActionTaxonomy = "attempts_to_change_action_taxonomy"
    case unsupportedTraceLinks = "unsupported_trace_links"
    case outputTooLong = "output_too_long"
    case emptyPatch = "empty_patch"
    case lowFaithfulness = "low_faithfulness"
}

struct PauseTextPatch: Equatable, Sendable {
    let shortVerdictOverride: String?
    let whyGoodByStrengthId: [String: String]
    let whyProblematicByIssueId: [String: String]
    let actionRationaleByActionId: [String: String]
    let noChangeRationaleOverride: String?

    init(shortVerdictOverride: String? = nil,
         whyGoodByStrengthId: [String: String] = [:],
         whyProblematicByIssueId: [String: String] = [:],
         actionRationaleByActionId: [String: String] = [:],
         noChangeRationaleOverride: String? = nil) {
        self.shortVerdictOverride = shortVerdictOverride
        self.whyGoodByStrengthId = whyGoodByStrengthId
        self.whyProblematicByIssueId = whyProblematicByIssueId
        self.actionRationaleByActionId = actionRationaleByActionId
        self.noChangeRationaleOverride = noChangeRationaleOverride
    }

    var isEmpty: Bool {
        let shortVerdictIsEmpty = shortVerdictOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        let noChangeIsEmpty = noChangeRationaleOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
        return shortVerdictIsEmpty
            && whyGoodByStrengthId.isEmpty
            && whyProblematicByIssueId.isEmpty
            && actionRationaleByActionId.isEmpty
            && noChangeIsEmpty
    }
}

struct ReasoningSafetyReport: Equatable, Sendable {
    let passed: Bool
    let violations: [ReasoningViolation]
}

struct ReasoningDiagnostics: Equatable, Sendable {
    let latencyMs: Int
    let tokenUsageIn: Int?
    let tokenUsageOut: Int?
    let fallbackReason: String?

    init(latencyMs: Int, tokenUsageIn: Int? = nil, tokenUsageOut: Int? = nil, fallbackReason: String? = nil) {
        self.latencyMs = max(0, latencyMs)
        self.tokenUsageIn = tokenUsageIn
        self.tokenUsageOut = tokenUsageOut
        self.fallbackReason = fallbackReason
    }
}

struct ReasoningRequest: Sendable {
    let requestId: String
    let frameId: String
    let mode: AnalysisMode
    let locale: String
    let critique: CritiqueReport
    let plan: RecommendationPlan
    let trace: ExplainabilityTraceBundle?
    let pausePresentationDraft: PauseCritiquePresentation
    let constraints: ReasoningConstraints
    let correlation: ReasoningCorrelation
}

struct ReasoningResponse: Sendable {
    let requestId: String
    let frameId: String
    let providerId: String
    let textPatch: PauseTextPatch
    let optionalTraceItems: [ExplainabilityTraceItem]
    let safety: ReasoningSafetyReport
    let diagnostics: ReasoningDiagnostics
}

enum PauseReasoningRefinementResult: Sendable {
    case skipped(reason: String, diagnostics: ReasoningDiagnostics)
    case refined(presentation: PauseCritiquePresentation,
                 optionalTraceItems: [ExplainabilityTraceItem],
                 diagnostics: ReasoningDiagnostics)
    case rejected(violations: [ReasoningViolation], diagnostics: ReasoningDiagnostics)
    case failed(reason: String, diagnostics: ReasoningDiagnostics)
}

enum ReasoningProviderFactory {
    static func makeDefaultProvider() -> ReasoningProvider? {
        let configured = ProcessInfo.processInfo.environment["CAMERA_REASONING_PROVIDER"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch configured {
        case "template":
            return TemplatePauseReasoningProvider()
        default:
            return nil
        }
    }
}

struct TemplatePauseReasoningProvider: ReasoningProvider {
    let providerId: String = "template_pause_reasoning_v1"
    let capabilities = ReasoningCapabilities(
        supportsOffline: true,
        supportsRemote: false,
        supportsRussian: true,
        maxInputChars: 6000,
        maxOutputChars: 180
    )

    func refinePauseExplanation(request: ReasoningRequest) async throws -> ReasoningResponse {
        let shortVerdictOverride: String?
        switch request.critique.verdict {
        case .good:
            shortVerdictOverride = "Кадр уже работает: акцент читается и критичных дефектов нет."
        case .mixed:
            shortVerdictOverride = "Кадр близок к рабочему, но 1-2 правки заметно улучшат читаемость."
        case .needsFix:
            shortVerdictOverride = "Сначала исправьте приоритетные дефекты, затем уточните композицию."
        }

        let strengthPatch: [String: String] = Dictionary(uniqueKeysWithValues: request.pausePresentationDraft.strengths.map { row in
            (row.strengthId, appendSentence(base: row.rationale, sentence: "Это усиливает визуальный акцент сцены."))
        })
        let issuePatch: [String: String] = Dictionary(uniqueKeysWithValues: request.pausePresentationDraft.issues.map { row in
            (row.issueId, appendSentence(base: row.rationale, sentence: "Это напрямую снижает читаемость ключевого объекта."))
        })
        let actionPatch: [String: String] = Dictionary(uniqueKeysWithValues: request.pausePresentationDraft.actions.map { row in
            (row.actionId, appendSentence(base: row.expectedOutcome, sentence: "Начните именно с этого шага."))
        })
        let noChangeOverride: String?
        if request.pausePresentationDraft.actions.isEmpty,
           request.critique.verdict == .good,
           let rationale = request.pausePresentationDraft.noChangeRationale {
            noChangeOverride = appendSentence(base: rationale, sentence: "Дополнительные правки сейчас не обязательны.")
        } else {
            noChangeOverride = nil
        }

        return ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: providerId,
            textPatch: PauseTextPatch(
                shortVerdictOverride: shortVerdictOverride,
                whyGoodByStrengthId: strengthPatch,
                whyProblematicByIssueId: issuePatch,
                actionRationaleByActionId: actionPatch,
                noChangeRationaleOverride: noChangeOverride
            ),
            optionalTraceItems: [],
            safety: ReasoningSafetyReport(passed: true, violations: []),
            diagnostics: ReasoningDiagnostics(latencyMs: 0)
        )
    }

    private func appendSentence(base: String, sentence: String) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sentence }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?") {
            return "\(trimmed) \(sentence)"
        }
        return "\(trimmed). \(sentence)"
    }
}

actor PauseReasoningCoordinator {
    private let provider: ReasoningProvider?

    init(provider: ReasoningProvider?) {
        self.provider = provider
    }

    func refine(request: ReasoningRequest) async -> PauseReasoningRefinementResult {
        guard request.mode == .pause else {
            return .rejected(
                violations: [.modeNotPause],
                diagnostics: ReasoningDiagnostics(latencyMs: 0, fallbackReason: "mode_not_pause")
            )
        }

        guard let provider else {
            return .skipped(
                reason: "provider_unavailable",
                diagnostics: ReasoningDiagnostics(latencyMs: 0, fallbackReason: "provider_unavailable")
            )
        }

        let startedAt = Date()
        let providerCall = await callProviderWithTimeout(provider: provider, request: request)
        let latencyMs = max(0, Int(Date().timeIntervalSince(startedAt) * 1000.0))

        switch providerCall {
        case .cancelled:
            return .failed(
                reason: "canceled_due_to_state_change",
                diagnostics: ReasoningDiagnostics(latencyMs: latencyMs, fallbackReason: "canceled_due_to_state_change")
            )
        case .timedOut:
            return .failed(
                reason: "timeout",
                diagnostics: ReasoningDiagnostics(latencyMs: latencyMs, fallbackReason: "timeout")
            )
        case .failed(let error):
            return .failed(
                reason: "transport_or_runtime_error: \(String(describing: error))",
                diagnostics: ReasoningDiagnostics(latencyMs: latencyMs, fallbackReason: "runtime_error")
            )
        case .success(let response):
            let validation = validateAndSanitize(response: response, request: request, provider: provider)
            let rejectedReason = validation.violations.contains(.lowFaithfulness) ? "low_faithfulness" : "validation_failed"

            if validation.fullReject {
                return .rejected(
                    violations: validation.violations,
                    diagnostics: ReasoningDiagnostics(
                        latencyMs: latencyMs,
                        tokenUsageIn: response.diagnostics.tokenUsageIn,
                        tokenUsageOut: response.diagnostics.tokenUsageOut,
                        fallbackReason: rejectedReason
                    )
                )
            }

            guard let sanitizedResponse = validation.sanitizedResponse else {
                return .rejected(
                    violations: validation.violations.isEmpty ? [.emptyPatch] : validation.violations,
                    diagnostics: ReasoningDiagnostics(
                        latencyMs: latencyMs,
                        tokenUsageIn: response.diagnostics.tokenUsageIn,
                        tokenUsageOut: response.diagnostics.tokenUsageOut,
                        fallbackReason: rejectedReason
                    )
                )
            }

            let refinedPresentation = applyPatch(sanitizedResponse.textPatch, to: request.pausePresentationDraft)
            if refinedPresentation == request.pausePresentationDraft {
                return .skipped(
                    reason: "empty_effect_patch",
                    diagnostics: ReasoningDiagnostics(
                        latencyMs: latencyMs,
                        tokenUsageIn: response.diagnostics.tokenUsageIn,
                        tokenUsageOut: response.diagnostics.tokenUsageOut,
                        fallbackReason: validation.violations.isEmpty ? "empty_patch" : "validation_partial_accept"
                    )
                )
            }

            return .refined(
                presentation: refinedPresentation,
                optionalTraceItems: sanitizedResponse.optionalTraceItems,
                diagnostics: ReasoningDiagnostics(
                    latencyMs: latencyMs,
                    tokenUsageIn: response.diagnostics.tokenUsageIn,
                    tokenUsageOut: response.diagnostics.tokenUsageOut,
                    fallbackReason: validation.violations.isEmpty ? nil : "validation_partial_accept"
                )
            )
        }
    }

    private enum ProviderCallResult {
        case success(ReasoningResponse)
        case failed(Error)
        case cancelled
        case timedOut
    }

    private func callProviderWithTimeout(provider: ReasoningProvider,
                                         request: ReasoningRequest) async -> ProviderCallResult {
        if Task.isCancelled {
            return .cancelled
        }
        let timeoutNs = UInt64(max(100, request.constraints.maxLatencyMs)) * 1_000_000
        return await withTaskGroup(of: ProviderCallResult.self) { group in
            group.addTask {
                if Task.isCancelled { return .cancelled }
                do {
                    let response = try await provider.refinePauseExplanation(request: request)
                    return .success(response)
                } catch {
                    return .failed(error)
                }
            }

            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: timeoutNs)
                } catch {
                    if Task.isCancelled { return .cancelled }
                }
                if Task.isCancelled { return .cancelled }
                return .timedOut
            }

            let first = await group.next() ?? .timedOut
            group.cancelAll()
            return first
        }
    }

    private struct ValidationResult {
        let sanitizedResponse: ReasoningResponse?
        let violations: [ReasoningViolation]
        let fullReject: Bool
    }

    private func validateAndSanitize(response: ReasoningResponse,
                                     request: ReasoningRequest,
                                     provider: ReasoningProvider) -> ValidationResult {
        var violations: Set<ReasoningViolation> = Set(response.safety.violations)
        let hasRequestOrFrameMismatch = response.requestId != request.requestId || response.frameId != request.frameId

        if hasRequestOrFrameMismatch {
            violations.insert(.unknownRuntimeId)
        }

        if request.mode != .pause {
            violations.insert(.modeNotPause)
        }

        let maxCharsPerField = max(64, min(provider.capabilities.maxOutputChars, 220))
        let sanitizedPatch = sanitizePatch(response.textPatch,
                                           request: request,
                                           maxCharsPerField: maxCharsPerField,
                                           violations: &violations)
        let sanitizedTraceItems = validatedOptionalTraceItems(
            sanitizeOptionalTraceItems(response.optionalTraceItems,
                                       request: request,
                                       violations: &violations),
            request: request,
            violations: &violations
        )

        if attemptToChangeVerdict(sanitizedPatch.shortVerdictOverride, verdict: request.critique.verdict) {
            violations.insert(.attemptsToChangeVerdict)
        }

        if detectLowFaithfulness(patch: sanitizedPatch, request: request) {
            violations.insert(.lowFaithfulness)
        }

        if sanitizedPatch.isEmpty {
            violations.insert(.emptyPatch)
        }

        let fullRejectTriggers: Set<ReasoningViolation> = [
            .modeNotPause,
            .attemptsToChangeVerdict,
            .attemptsToChangeIssueTaxonomy,
            .attemptsToChangeActionTaxonomy,
            .lowFaithfulness,
            .emptyPatch
        ]
        let shouldFullReject = hasRequestOrFrameMismatch || !violations.intersection(fullRejectTriggers).isEmpty

        let sortedViolations = violations.sorted { $0.rawValue < $1.rawValue }
        guard !sanitizedPatch.isEmpty else {
            return ValidationResult(sanitizedResponse: nil, violations: sortedViolations, fullReject: shouldFullReject)
        }

        let sanitizedResponse = ReasoningResponse(
            requestId: request.requestId,
            frameId: request.frameId,
            providerId: response.providerId,
            textPatch: sanitizedPatch,
            optionalTraceItems: sanitizedTraceItems,
            safety: ReasoningSafetyReport(passed: sortedViolations.isEmpty, violations: sortedViolations),
            diagnostics: response.diagnostics
        )

        return ValidationResult(
            sanitizedResponse: sanitizedResponse,
            violations: sortedViolations,
            fullReject: shouldFullReject
        )
    }

    private func sanitizePatch(_ patch: PauseTextPatch,
                               request: ReasoningRequest,
                               maxCharsPerField: Int,
                               violations: inout Set<ReasoningViolation>) -> PauseTextPatch {
        let knownStrengthIds = Set(request.pausePresentationDraft.strengths.map(\.strengthId))
        let knownIssueIds = Set(request.pausePresentationDraft.issues.map(\.issueId))
        let knownActionIds = Set(request.pausePresentationDraft.actions.map(\.actionId))

        let shortVerdict = sanitizeText(patch.shortVerdictOverride,
                                        maxCharsPerField: maxCharsPerField,
                                        violations: &violations)
        let canApplyNoChangeRationale = request.critique.verdict == .good && request.plan.primaryAction == nil
        let noChange: String?
        if canApplyNoChangeRationale {
            noChange = sanitizeText(patch.noChangeRationaleOverride,
                                    maxCharsPerField: maxCharsPerField,
                                    violations: &violations)
        } else {
            if patch.noChangeRationaleOverride?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                violations.insert(.attemptsToChangeActionTaxonomy)
            }
            noChange = nil
        }

        let good = sanitizeTextMap(patch.whyGoodByStrengthId,
                                   allowedIds: knownStrengthIds,
                                   maxCharsPerField: maxCharsPerField,
                                   violations: &violations)
        let issues = sanitizeTextMap(patch.whyProblematicByIssueId,
                                     allowedIds: knownIssueIds,
                                     maxCharsPerField: maxCharsPerField,
                                     violations: &violations)
        let actions = sanitizeTextMap(patch.actionRationaleByActionId,
                                      allowedIds: knownActionIds,
                                      maxCharsPerField: maxCharsPerField,
                                      violations: &violations)

        return PauseTextPatch(
            shortVerdictOverride: shortVerdict,
            whyGoodByStrengthId: good,
            whyProblematicByIssueId: issues,
            actionRationaleByActionId: actions,
            noChangeRationaleOverride: noChange
        )
    }

    private func sanitizeTextMap(_ source: [String: String],
                                 allowedIds: Set<String>,
                                 maxCharsPerField: Int,
                                 violations: inout Set<ReasoningViolation>) -> [String: String] {
        var result: [String: String] = [:]
        for key in source.keys.sorted() {
            guard allowedIds.contains(key) else {
                violations.insert(.unknownRuntimeId)
                continue
            }
            guard let value = sanitizeText(source[key],
                                           maxCharsPerField: maxCharsPerField,
                                           violations: &violations) else {
                continue
            }
            result[key] = value
        }
        return result
    }

    private func sanitizeText(_ value: String?,
                              maxCharsPerField: Int,
                              violations: inout Set<ReasoningViolation>) -> String? {
        guard var value else { return nil }
        value = value
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if value.count > maxCharsPerField {
            violations.insert(.outputTooLong)
            let limited = value.prefix(maxCharsPerField)
            value = String(limited).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return value.isEmpty ? nil : value
    }

    private func sanitizeOptionalTraceItems(_ items: [ExplainabilityTraceItem],
                                            request: ReasoningRequest,
                                            violations: inout Set<ReasoningViolation>) -> [ExplainabilityTraceItem] {
        let knownIssueIds = Set(request.pausePresentationDraft.issues.map(\.issueId))
        let knownStrengthIds = Set(request.pausePresentationDraft.strengths.map(\.strengthId))
        let summaryId = request.pausePresentationDraft.summaryId
        var sanitized: [ExplainabilityTraceItem] = []

        for item in items {
            var isValid = true
            if item.frameId != request.frameId || item.mode != .pause {
                isValid = false
            }
            if item.stage != .interpretation || item.sourceKind != .optionalReasoning {
                isValid = false
            }
            if item.certainty == .deterministic {
                isValid = false
            }
            if item.links.contains(where: { $0.kind == .action || $0.kind == .overlay }) {
                isValid = false
            }

            for link in item.links {
                switch link.kind {
                case .issue:
                    if !knownIssueIds.contains(link.refId) { isValid = false }
                case .strength:
                    if !knownStrengthIds.contains(link.refId) { isValid = false }
                case .summary:
                    if link.refId != summaryId { isValid = false }
                case .action, .overlay:
                    isValid = false
                }
            }

            if isValid {
                sanitized.append(item)
            } else {
                violations.insert(.unsupportedTraceLinks)
            }
        }

        return sanitized
    }

    private func validatedOptionalTraceItems(_ items: [ExplainabilityTraceItem],
                                             request: ReasoningRequest,
                                             violations: inout Set<ReasoningViolation>) -> [ExplainabilityTraceItem] {
        guard !items.isEmpty else { return [] }
        guard let deterministicTrace = request.trace else {
            violations.insert(.unsupportedTraceLinks)
            return []
        }

        let existingIds = Set(deterministicTrace.items.map(\.id))
        var seenIds: Set<String> = []
        var appendableItems: [ExplainabilityTraceItem] = []
        for item in items.sorted(by: { lhs, rhs in
            if lhs.timestampMs != rhs.timestampMs {
                return lhs.timestampMs < rhs.timestampMs
            }
            return lhs.id < rhs.id
        }) {
            let trimmedId = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedId.isEmpty, !existingIds.contains(trimmedId), !seenIds.contains(trimmedId) else {
                violations.insert(.unsupportedTraceLinks)
                continue
            }
            seenIds.insert(trimmedId)
            appendableItems.append(item)
        }

        guard !appendableItems.isEmpty else {
            return []
        }

        let conflictAnnotatedItems = annotateOptionalTraceConflicts(
            appendableItems,
            deterministicTrace: deterministicTrace,
            verdict: request.critique.verdict
        )

        let mergedBundle = ExplainabilityTraceBundle(
            frameId: deterministicTrace.frameId,
            mode: deterministicTrace.mode,
            items: deterministicTrace.items + conflictAnnotatedItems,
            rootSummaryIds: mergedRootSummaryIds(base: deterministicTrace.rootSummaryIds, appended: conflictAnnotatedItems)
        )
        let validationErrors = mergedBundle.validate(
            critiqueReport: request.critique,
            recommendationPlan: request.plan
        )
        if !validationErrors.isEmpty {
            violations.insert(.unsupportedTraceLinks)
            return []
        }

        return conflictAnnotatedItems
    }

    private func mergedRootSummaryIds(base: [String],
                                      appended: [ExplainabilityTraceItem]) -> [String] {
        var ordered = base
        var seen = Set(base)
        for item in appended where item.links.contains(where: { $0.kind == .summary }) {
            if !seen.contains(item.id) {
                seen.insert(item.id)
                ordered.append(item.id)
            }
        }
        return ordered
    }

    private func annotateOptionalTraceConflicts(_ items: [ExplainabilityTraceItem],
                                                deterministicTrace: ExplainabilityTraceBundle,
                                                verdict: FrameVerdict) -> [ExplainabilityTraceItem] {
        let deterministicInterpretations = deterministicTrace.items.filter { item in
            item.stage == .interpretation && item.sourceKind == .deterministicRule
        }

        return items.map { item in
            guard let conflictTraceId = conflictTraceId(
                for: item,
                deterministicInterpretations: deterministicInterpretations,
                verdict: verdict
            ) else {
                return item
            }
            var metadata = item.metadata
            metadata["conflictWith"] = conflictTraceId
            return ExplainabilityTraceItem(
                id: item.id,
                frameId: item.frameId,
                mode: item.mode,
                stage: item.stage,
                sourceKind: item.sourceKind,
                certainty: item.certainty,
                confidence: item.confidence,
                timestampMs: item.timestampMs,
                statement: item.statement,
                evidenceKeys: item.evidenceKeys,
                dependsOn: item.dependsOn,
                links: item.links,
                audiences: item.audiences,
                metadata: metadata
            )
        }
    }

    private func conflictTraceId(for optionalItem: ExplainabilityTraceItem,
                                 deterministicInterpretations: [ExplainabilityTraceItem],
                                 verdict: FrameVerdict) -> String? {
        let optionalPolarity = statementPolarity(optionalItem.statement)
        guard optionalPolarity != .neutral else { return nil }

        let linkedIssueIds = Set(optionalItem.links.filter { $0.kind == .issue }.map(\.refId))
        let linkedStrengthIds = Set(optionalItem.links.filter { $0.kind == .strength }.map(\.refId))
        let linkedSummaryIds = Set(optionalItem.links.filter { $0.kind == .summary }.map(\.refId))

        let candidateDeterministic = deterministicInterpretations.filter { item in
            item.links.contains { link in
                (link.kind == .issue && linkedIssueIds.contains(link.refId))
                    || (link.kind == .strength && linkedStrengthIds.contains(link.refId))
                    || (link.kind == .summary && linkedSummaryIds.contains(link.refId))
            }
        }

        if linkedIssueIds.isEmpty == false && optionalPolarity == .positive {
            return candidateDeterministic.first?.id
        }
        if linkedStrengthIds.isEmpty == false && optionalPolarity == .negative {
            return candidateDeterministic.first?.id
        }
        if linkedSummaryIds.isEmpty == false {
            switch verdict {
            case .good where optionalPolarity == .negative:
                return candidateDeterministic.first?.id
            case .needsFix where optionalPolarity == .positive:
                return candidateDeterministic.first?.id
            default:
                break
            }
        }

        for deterministicItem in candidateDeterministic {
            let deterministicPolarity = statementPolarity(deterministicItem.statement)
            if isOppositePolarity(lhs: optionalPolarity, rhs: deterministicPolarity) {
                return deterministicItem.id
            }
        }

        return nil
    }

    private enum StatementPolarity {
        case positive
        case negative
        case mixed
        case neutral
    }

    private func statementPolarity(_ text: String) -> StatementPolarity {
        let normalized = text.lowercased()
        let negativeMarkers = ["плох", "критич", "исправ", "неудач", "проблем", "ошиб", "меша", "конкур"]
        let positiveMarkers = ["хорош", "удач", "сильн", "читаем", "акцент", "баланс", "стабил"]

        let hasNegative = negativeMarkers.contains(where: { normalized.contains($0) })
        let hasPositive = positiveMarkers.contains(where: { normalized.contains($0) })

        switch (hasPositive, hasNegative) {
        case (true, false):
            return .positive
        case (false, true):
            return .negative
        case (true, true):
            return .mixed
        case (false, false):
            return .neutral
        }
    }

    private func isOppositePolarity(lhs: StatementPolarity, rhs: StatementPolarity) -> Bool {
        (lhs == .positive && rhs == .negative) || (lhs == .negative && rhs == .positive)
    }

    private func detectLowFaithfulness(patch: PauseTextPatch,
                                       request: ReasoningRequest) -> Bool {
        let certaintySensitiveWords = ["точно", "однозначно", "гарантированно", "безошибочно", "идеально"]
        let confidence = request.critique.verdictConfidence

        let strengthSources = Dictionary(uniqueKeysWithValues: request.pausePresentationDraft.strengths.map { ($0.strengthId, $0.rationale) })
        let issueSources = Dictionary(uniqueKeysWithValues: request.pausePresentationDraft.issues.map { ($0.issueId, $0.rationale) })
        let actionSources = Dictionary(uniqueKeysWithValues: request.pausePresentationDraft.actions.map { ($0.actionId, $0.expectedOutcome) })

        if let candidate = patch.shortVerdictOverride,
           hasLowOverlap(source: request.pausePresentationDraft.shortVerdict, candidate: candidate) {
            return true
        }

        if let noChange = patch.noChangeRationaleOverride {
            let source = request.pausePresentationDraft.noChangeRationale ?? request.pausePresentationDraft.shortVerdict
            if hasLowOverlap(source: source, candidate: noChange) {
                return true
            }
        }

        for (id, candidate) in patch.whyGoodByStrengthId {
            guard let source = strengthSources[id] else { continue }
            if hasLowOverlap(source: source, candidate: candidate) {
                return true
            }
        }
        for (id, candidate) in patch.whyProblematicByIssueId {
            guard let source = issueSources[id] else { continue }
            if hasLowOverlap(source: source, candidate: candidate) {
                return true
            }
        }
        for (id, candidate) in patch.actionRationaleByActionId {
            guard let source = actionSources[id] else { continue }
            if hasLowOverlap(source: source, candidate: candidate) {
                return true
            }
        }

        if confidence < 0.55 {
            let allTexts: [String?] = [patch.shortVerdictOverride, patch.noChangeRationaleOverride]
                + patch.whyGoodByStrengthId.values.map(Optional.some)
                + patch.whyProblematicByIssueId.values.map(Optional.some)
                + patch.actionRationaleByActionId.values.map(Optional.some)
            let normalized = allTexts
                .compactMap { $0?.lowercased() }
                .joined(separator: " ")
            if certaintySensitiveWords.contains(where: { normalized.contains($0) }) {
                return true
            }
        }

        return false
    }

    private func hasLowOverlap(source: String, candidate: String) -> Bool {
        let sourceTokens = Set(tokenize(source))
        let candidateTokens = Set(tokenize(candidate))

        guard !sourceTokens.isEmpty, !candidateTokens.isEmpty else {
            return false
        }

        let overlapCount = sourceTokens.intersection(candidateTokens).count
        let overlap = Double(overlapCount) / Double(max(sourceTokens.count, 1))
        return overlap < 0.10 && candidateTokens.count >= 4
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
    }

    private func attemptToChangeVerdict(_ shortVerdictOverride: String?, verdict: FrameVerdict) -> Bool {
        guard let text = shortVerdictOverride?.lowercased() else {
            return false
        }

        let negativeMarkers = ["плох", "критич", "исправ", "неудач"]
        let positiveMarkers = ["хорош", "удач", "оставьте", "не менять"]

        switch verdict {
        case .good:
            return negativeMarkers.contains(where: { text.contains($0) })
        case .needsFix:
            return positiveMarkers.contains(where: { text.contains($0) })
        case .mixed:
            let hasNegative = negativeMarkers.contains(where: { text.contains($0) })
            let hasPositive = positiveMarkers.contains(where: { text.contains($0) })
            return hasNegative != hasPositive
        }
    }

    private func applyPatch(_ patch: PauseTextPatch,
                            to draft: PauseCritiquePresentation) -> PauseCritiquePresentation {
        let updatedStrengths = draft.strengths.map { item in
            PauseStrengthRow(
                strengthId: item.strengthId,
                type: item.type,
                rationale: patch.whyGoodByStrengthId[item.strengthId] ?? item.rationale,
                confidence: item.confidence,
                supportingRegion: item.supportingRegion,
                traceRefId: item.traceRefId
            )
        }

        let updatedIssues = draft.issues.map { item in
            PauseIssueRow(
                issueId: item.issueId,
                type: item.type,
                severity: item.severity,
                confidence: item.confidence,
                rationale: patch.whyProblematicByIssueId[item.issueId] ?? item.rationale,
                affectedRegion: item.affectedRegion,
                suggestedFixTypes: item.suggestedFixTypes,
                traceRefId: item.traceRefId
            )
        }

        let updatedActions = draft.actions.map { item in
            PauseActionRow(
                actionId: item.actionId,
                actionType: item.actionType,
                priority: item.priority,
                confidence: item.confidence,
                linkedIssueIds: item.linkedIssueIds,
                expectedOutcome: patch.actionRationaleByActionId[item.actionId] ?? item.expectedOutcome,
                targetRegion: item.targetRegion,
                overlayHintId: item.overlayHintId,
                traceRefId: item.traceRefId
            )
        }

        return PauseCritiquePresentation(
            frameId: draft.frameId,
            verdict: draft.verdict,
            verdictConfidence: draft.verdictConfidence,
            summaryId: draft.summaryId,
            shortVerdict: patch.shortVerdictOverride ?? draft.shortVerdict,
            whyGood: draft.whyGood,
            whyProblematic: draft.whyProblematic,
            strengths: updatedStrengths,
            issues: updatedIssues,
            actions: updatedActions,
            noChangeRationale: patch.noChangeRationaleOverride ?? draft.noChangeRationale,
            assumptions: draft.assumptions,
            traceRootIds: draft.traceRootIds,
            fallbackUsed: draft.fallbackUsed
        )
    }
}
