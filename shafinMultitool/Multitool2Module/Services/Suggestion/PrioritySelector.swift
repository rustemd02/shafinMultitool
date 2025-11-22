//
//  PrioritySelector.swift
//  multitool2
//
//  Created by Рустем on 28.10.2025.
//

import Foundation

public enum Priority: Int, Comparable {
    case critical = 0
    case important = 1
    case optional = 2

    public static func < (lhs: Priority, rhs: Priority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum SuggestionType: Int, Comparable {
    case horizon = 0
    case exposure = 1
    case composition = 2
    case lighting = 3
    case lens = 4
    case other = 5

    public static func < (lhs: SuggestionType, rhs: SuggestionType) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct Suggestion: Identifiable, Equatable {
    public let id: UUID
    public let text: String
    public let priority: Priority
    public let type: SuggestionType
    public let ttl: TimeInterval
    public let createdAt: Date

    public init(id: UUID = UUID(), text: String, priority: Priority, type: SuggestionType, ttl: TimeInterval, createdAt: Date = Date()) {
        self.id = id
        self.text = text
        self.priority = priority
        self.type = type
        self.ttl = ttl
        self.createdAt = createdAt
    }
}

@inlinable
public func selectSuggestion(_ all: [Suggestion]) -> Suggestion? {
    all.sorted { lhs, rhs in
        if lhs.priority != rhs.priority {
            return lhs.priority < rhs.priority
        }
        if lhs.type != rhs.type {
            return lhs.type < rhs.type
        }
        return lhs.createdAt < rhs.createdAt
    }.first
}


