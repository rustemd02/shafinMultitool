//
//  SceneMetadataExtractor.swift
//  shafinMultitool
//
//  Created on 21.04.2026.
//

import Foundation

struct SceneTopLevelMetadata: Codable, Equatable {
    var sceneHeading: String?
    var locationName: String?
    var interiorExterior: String?
    var timeOfDay: String?

    static let empty = SceneTopLevelMetadata(
        sceneHeading: nil,
        locationName: nil,
        interiorExterior: nil,
        timeOfDay: nil
    )
}

final class SceneMetadataExtractor {
    func extract(description: String, fallbackLocationName: String? = nil) -> SceneTopLevelMetadata {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return SceneTopLevelMetadata(
                sceneHeading: nil,
                locationName: fallbackLocationName,
                interiorExterior: nil,
                timeOfDay: nil
            )
        }

        if let headingLine = headingCandidate(from: trimmed),
           let heading = parseHeading(headingLine) {
            return SceneTopLevelMetadata(
                sceneHeading: heading.sceneHeading,
                locationName: heading.locationName ?? fallbackLocationName,
                interiorExterior: heading.interiorExterior,
                timeOfDay: heading.timeOfDay ?? inferTimeOfDay(from: headingLine)
            )
        }

        return SceneTopLevelMetadata(
            sceneHeading: nil,
            locationName: fallbackLocationName,
            interiorExterior: inferInteriorExterior(from: trimmed),
            timeOfDay: inferTimeOfDay(from: trimmed)
        )
    }

    private func headingCandidate(from text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { condensedLine($0) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return nil }

        var startIndex = 0
        if lines.count >= 2, shouldSkipLeadingCueLine(lines[0], nextLine: lines[1]) {
            startIndex = 1
        }
        guard startIndex < lines.count else { return nil }

        let focus = Array(lines[startIndex..<min(lines.count, startIndex + 3)])
        var candidates: [String] = []
        if let first = focus.first {
            candidates.append(first)
            if focus.count >= 2 {
                candidates.append("\(first) \(focus[1])")
            }
            if focus.count >= 3, isInteriorExteriorPrefixLine(first) {
                candidates.append("\(first) \(focus[1]) \(focus[2])")
            }
        }

        for candidate in candidates {
            if parseHeading(candidate) != nil {
                return candidate
            }
        }
        return nil
    }

    private func parseHeading(_ line: String) -> SceneTopLevelMetadata? {
        let normalized = condensedLine(line)
        guard !normalized.isEmpty else {
            return nil
        }

        if let prefixed = parsePrefixedHeading(normalized) {
            return prefixed
        }
        if let generic = parseGenericHeading(normalized) {
            return generic
        }
        return nil
    }

    private func parsePrefixedHeading(_ line: String) -> SceneTopLevelMetadata? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(INT\/EXT|ИНТ\/ЭКСТ|INT|EXT|ИНТ|ЭКСТ|НАТ)\.?\s*(.+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, options: [], range: nsRange),
              let prefix = capture(match: match, index: 1, in: line)?.uppercased(),
              let remainder = capture(match: match, index: 2, in: line)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        else {
            return nil
        }
        // The heading keeps the line's own sentence punctuation (cue phrases
        // often carry a terminal period); periods are stripped only for the
        // emptiness check so a bare "ЭКСТ." line stays rejected.
        let contentOnly = remainder.trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        guard !contentOnly.isEmpty else {
            return nil
        }
        let normalizedRemainder = remainder

        let components = splitHeadingComponents(normalizedRemainder)
        let timeOfDay = extractHeadingTime(from: components)
        let location = extractHeadingLocation(from: components, timeOfDay: timeOfDay)

        return SceneTopLevelMetadata(
            sceneHeading: "\(prefix). \(normalizedRemainder)".uppercased(),
            locationName: location,
            interiorExterior: normalizeInteriorExterior(prefix),
            timeOfDay: timeOfDay
        )
    }

    private func parseGenericHeading(_ line: String) -> SceneTopLevelMetadata? {
        let components = splitHeadingComponents(line)
        guard components.count >= 2 else {
            return nil
        }
        guard let timeOfDay = extractHeadingTime(from: components) else {
            return nil
        }
        let location = extractHeadingLocation(from: components, timeOfDay: timeOfDay)
        guard location != nil else {
            return nil
        }

        return SceneTopLevelMetadata(
            sceneHeading: line.uppercased(),
            locationName: location,
            interiorExterior: nil,
            timeOfDay: timeOfDay
        )
    }

    private func splitHeadingComponents(_ remainder: String) -> [String] {
        remainder
            .replacingOccurrences(of: #"\s+[—-]\s+"#, with: "\n", options: .regularExpression)
            .components(separatedBy: .newlines)
            .map { condensedLine($0) }
            .filter { !$0.isEmpty }
    }

    private func extractHeadingTime(from components: [String]) -> String? {
        for component in components.reversed() {
            if let normalized = normalizeTimeOfDay(component) {
                return normalized
            }
        }
        return nil
    }

    private func extractHeadingLocation(from components: [String], timeOfDay: String?) -> String? {
        guard !components.isEmpty else {
            return nil
        }

        var locationComponents = components
        if timeOfDay != nil,
           let lastTimeIndex = locationComponents.lastIndex(where: { normalizeTimeOfDay($0) != nil }) {
            locationComponents.removeSubrange(lastTimeIndex...)
        }
        let location = locationComponents
            .joined(separator: " — ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return location.isEmpty ? nil : location
    }

    private func shouldSkipLeadingCueLine(_ line: String, nextLine: String) -> Bool {
        guard line.hasSuffix(":") else {
            return false
        }
        return isInteriorExteriorPrefixLine(nextLine) || parseHeading(nextLine) != nil
    }

    private func isInteriorExteriorPrefixLine(_ line: String) -> Bool {
        let normalized = condensedLine(line).uppercased()
        return [
            "INT", "INT.", "EXT", "EXT.", "INT/EXT", "INT/EXT.",
            "ИНТ", "ИНТ.", "ЭКСТ", "ЭКСТ.", "ИНТ/ЭКСТ", "ИНТ/ЭКСТ.",
            "НАТ", "НАТ."
        ].contains(normalized)
    }

    private func condensedLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func inferInteriorExterior(from text: String) -> String? {
        let lowercased = text.lowercased()
        let interiorHints = ["инт.", "int.", "в комнате", "в квартире", "в офисе", "в помещении", "внутри", "в доме"]
        let exteriorHints = ["экст.", "ext.", "нат.", "на улице", "снаружи", "во дворе", "на дороге", "на площади", "на крыше"]

        if interiorHints.contains(where: { lowercased.contains($0) }) {
            return "interior"
        }
        if exteriorHints.contains(where: { lowercased.contains($0) }) {
            return "exterior"
        }
        return nil
    }

    private func inferTimeOfDay(from text: String) -> String? {
        let lowercased = text.lowercased()
        return normalizeTimeOfDay(lowercased)
    }

    private func normalizeInteriorExterior(_ raw: String) -> String? {
        switch raw {
        case "INT", "ИНТ":
            return "interior"
        case "EXT", "ЭКСТ":
            return "exterior"
        case "НАТ":
            return "exterior"
        case "INT/EXT", "ИНТ/ЭКСТ":
            return "mixed"
        default:
            return nil
        }
    }

    private func normalizeTimeOfDay(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let lowercased = raw.lowercased()
        if lowercased.contains("рассвет") || lowercased.contains("заря") || lowercased.contains("dawn") || lowercased.contains("sunrise") {
            return "morning"
        }
        if lowercased.contains("утр") || lowercased.contains("morning") {
            return "morning"
        }
        if lowercased.contains("полд") || lowercased.contains("дн") || lowercased.contains("day") || lowercased.contains("afternoon") {
            return "day"
        }
        if lowercased.contains("сумерк") || lowercased.contains("закат") || lowercased.contains("dusk") || lowercased.contains("twilight") {
            return "evening"
        }
        if lowercased.contains("вечер") || lowercased.contains("evening") {
            return "evening"
        }
        if lowercased.contains("ноч") || lowercased.contains("night") {
            return "night"
        }
        return nil
    }

    private func capture(match: NSTextCheckingResult, index: Int, in line: String) -> String? {
        guard let range = Range(match.range(at: index), in: line) else {
            return nil
        }
        return String(line[range])
    }
}
