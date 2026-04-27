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

        let firstLine = trimmed.components(separatedBy: .newlines).first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed
        if let heading = parseHeading(firstLine) {
            return SceneTopLevelMetadata(
                sceneHeading: heading.sceneHeading,
                locationName: heading.locationName ?? fallbackLocationName,
                interiorExterior: heading.interiorExterior,
                timeOfDay: heading.timeOfDay ?? inferTimeOfDay(from: trimmed)
            )
        }

        return SceneTopLevelMetadata(
            sceneHeading: nil,
            locationName: fallbackLocationName,
            interiorExterior: inferInteriorExterior(from: trimmed),
            timeOfDay: inferTimeOfDay(from: trimmed)
        )
    }

    private func parseHeading(_ line: String) -> SceneTopLevelMetadata? {
        let patterns: [(pattern: String, genericLocationDashTime: Bool)] = [
            (#"^(INT|EXT|INT\/EXT)\.?\s+([^-\n]+?)(?:\s*-\s*(.+))?$"#, false),
            (#"^(ИНТ|ЭКСТ|ИНТ\/ЭКСТ)\.?\s+([^-\n]+?)(?:\s*-\s*(.+))?$"#, false),
            (#"^(НАТ)\.?\s+([^-\n]+?)(?:\s*-\s*(.+))?$"#, false),
            (#"^([A-ZА-Я0-9][A-ZА-Я0-9 \/_]{2,})\s*[—-]\s*([A-ZА-Яa-zа-я0-9 \/_]{2,})$"#, true),
        ]

        for entry in patterns {
            let pattern = entry.pattern
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = regex.firstMatch(in: line, options: [], range: nsRange) else {
                continue
            }

            let prefix: String
            let location: String?
            let rawTime: String?
            if entry.genericLocationDashTime {
                prefix = ""
                location = capture(match: match, index: 1, in: line)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                rawTime = capture(match: match, index: 2, in: line)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                prefix = capture(match: match, index: 1, in: line)?.uppercased() ?? ""
                location = capture(match: match, index: 2, in: line)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                rawTime = capture(match: match, index: 3, in: line)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }

            return SceneTopLevelMetadata(
                sceneHeading: line.uppercased(),
                locationName: location,
                interiorExterior: normalizeInteriorExterior(prefix),
                timeOfDay: normalizeTimeOfDay(rawTime)
            )
        }
        return nil
    }

    private func inferInteriorExterior(from text: String) -> String? {
        let lowercased = text.lowercased()
        let interiorHints = ["в комнате", "в квартире", "в офисе", "в помещении", "внутри", "в доме"]
        let exteriorHints = ["на улице", "снаружи", "во дворе", "на дороге", "на площади", "на крыше"]

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
        if lowercased.contains("утр") || lowercased.contains("morning") {
            return "morning"
        }
        if lowercased.contains("дн") || lowercased.contains("day") || lowercased.contains("afternoon") {
            return "day"
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
