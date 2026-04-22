//
//  SceneAnchorExtractor.swift
//  shafinMultitool
//
//  Created on 21.04.2026.
//

import Foundation

final class SceneAnchorExtractor {
    private let lemmatizer = Lemmatizer()
    private lazy var markedObjectMatcher = MarkedObjectMatcher(lemmatizer: lemmatizer)

    private let unsupportedActionKeywords = [
        "улыба", "танцу", "машет", "машут", "кивает", "кивают", "обнима", "целует", "жестикулиру"
    ]

    func extract(description: String, markedObjects: [MarkedObject]) -> SourceAnchorBundle {
        let text = description.lowercased()
        let actorCountHint = extractActorCountHint(from: text)
        let ordinalMentions = ["first", "second", "third"].filter { ordinal in
            switch ordinal {
            case "first":
                return text.contains("перв")
            case "second":
                return text.contains("втор")
            case "third":
                return text.contains("трет")
            default:
                return false
            }
        }

        let markerReferences = markedObjectMatcher.findMarkedObjectReferences(in: text, markedObjects: markedObjects)
        let mentionedMarkedObjects = markerReferences.map { marker in
            markedObjects.first(where: { $0.id == marker.markerId })?.canonicalMarkedObjectID ?? ""
        }.filter { !$0.isEmpty }

        let objectSurfaceMentions = Set(
            KeywordsMapping.objectKeywords.keys.filter { keyword in
                lemmatizer.textContainsKeyword(text, keyword: keyword) || text.contains(keyword)
            }
        ).sorted()

        let phaseCues = extractPhaseCues(from: text)
        let unsupportedActionFlags = unsupportedActionKeywords.filter { text.contains($0) }
        let sameTypeMarkerConflict = hasSameTypeMarkerConflict(mentionedMarkerIDs: mentionedMarkedObjects, markedObjects: markedObjects)

        var lowConfidenceFlags: [String] = []
        if actorCountHint == 0 {
            lowConfidenceFlags.append("missing_actor_count")
        }
        if ordinalMentions.count > max(actorCountHint, 1) {
            lowConfidenceFlags.append("ordinal_actor_count_mismatch")
        }
        if sameTypeMarkerConflict {
            lowConfidenceFlags.append("same_type_marker_conflict")
        }
        if phaseCues.isEmpty {
            lowConfidenceFlags.append("weak_phase_signal")
        }

        return SourceAnchorBundle(
            actorCountHint: actorCountHint,
            ordinalMentions: ordinalMentions,
            mentionedMarkedObjects: mentionedMarkedObjects,
            objectSurfaceMentions: objectSurfaceMentions,
            phaseCues: phaseCues,
            unsupportedActionFlags: unsupportedActionFlags,
            sameTypeMarkerConflict: sameTypeMarkerConflict,
            lowConfidenceFlags: lowConfidenceFlags
        )
    }

    private func extractActorCountHint(from text: String) -> Int {
        let patterns = [
            #"(\d+)\s*(?:актёр|актер|актёра|актера|актёров|актеров)"#,
            #"(\d+)\s*(?:человек|человека|людей)"#,
            #"(\d+)\s*(?:персонаж|персонажа|персонажей)"#
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               match.numberOfRanges > 1,
               let range = Range(match.range(at: 1), in: text),
               let count = Int(text[range]) {
                return count
            }
        }

        if text.contains("перв") || text.contains("втор") {
            return 2
        }
        if text.contains("трет") {
            return 3
        }
        return 1
    }

    private func extractPhaseCues(from text: String) -> [String] {
        var cues: [String] = []
        let cueKeywords: [(String, String)] = [
            ("navstrechu", "навстреч"),
            ("pass_by", "мимо"),
            ("stop", "остан"),
            ("pickup", "поднима"),
            ("open", "открыва"),
            ("give", "даёт"),
            ("talk", "говор"),
            ("sequence", "затем"),
            ("sequence", "потом")
        ]

        for (label, keyword) in cueKeywords where text.contains(keyword) {
            if !cues.contains(label) {
                cues.append(label)
            }
        }
        return cues
    }

    private func hasSameTypeMarkerConflict(mentionedMarkerIDs: [String], markedObjects: [MarkedObject]) -> Bool {
        let mentioned = mentionedMarkerIDs.compactMap { objectID in
            markedObjects.first(where: { $0.canonicalMarkedObjectID == objectID })
        }
        let types = Dictionary(grouping: mentioned, by: \.type)
        return types.values.contains { $0.count > 1 }
    }
}
