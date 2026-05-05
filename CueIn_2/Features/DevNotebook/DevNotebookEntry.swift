import Foundation
import SwiftUI

// MARK: - DevNotebookEntryKind

enum DevNotebookEntryKind: String, Codable, CaseIterable, Identifiable {
    case bigIdea
    case moduleIdea
    case bug
    case designIdea

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bigIdea: return "Big idea"
        case .moduleIdea: return "Ideas for this module"
        case .bug: return "Bug"
        case .designIdea: return "Design idea"
        }
    }

    var systemImage: String {
        switch self {
        case .bigIdea: return "lightbulb.max.fill"
        case .moduleIdea: return "square.stack.3d.up.fill"
        case .bug: return "ladybug.fill"
        case .designIdea: return "paintpalette.fill"
        }
    }

    var accent: Color {
        switch self {
        case .bigIdea: return Color(red: 0.45, green: 0.78, blue: 1.0)
        case .moduleIdea: return Color(red: 0.55, green: 0.95, blue: 0.65)
        case .bug: return Color(red: 1.0, green: 0.45, blue: 0.42)
        case .designIdea: return Color(red: 0.85, green: 0.55, blue: 1.0)
        }
    }
}

// MARK: - DevNotebookEntry

struct DevNotebookEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var kind: DevNotebookEntryKind
    var body: String
    /// Tab name at capture time (e.g. Today, Tasks).
    var moduleLabel: String
    /// Human-readable location string (tab · engine · screen).
    var contextLine: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: DevNotebookEntryKind,
        body: String,
        moduleLabel: String,
        contextLine: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.body = body
        self.moduleLabel = moduleLabel
        self.contextLine = contextLine
    }

    var listTitle: String {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = t.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if first.count <= 80 { return first.isEmpty ? "(empty)" : first }
        return String(first.prefix(77)) + "…"
    }
}
