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

// MARK: - DevNotebookAIModel

/// Suggested AI agent to implement or review this note later.
enum DevNotebookAIModel: String, Codable, CaseIterable, Identifiable {
    case codex
    case cursor
    case gemini
    case opus

    var id: String { rawValue }

    var title: String {
        switch self {
        case .codex: return "Codex"
        case .cursor: return "Cursor"
        case .gemini: return "Gemini"
        case .opus: return "Opus"
        }
    }

    var systemImage: String {
        switch self {
        case .codex: return "chevron.left.forwardslash.chevron.right"
        case .cursor: return "cursorarrow.rays"
        case .gemini: return "sparkles"
        case .opus: return "brain.head.profile"
        }
    }

    var accent: Color {
        switch self {
        case .codex: return Color(red: 0.35, green: 0.82, blue: 0.72)
        case .cursor: return Color(red: 0.55, green: 0.72, blue: 1.0)
        case .gemini: return Color(red: 0.45, green: 0.65, blue: 1.0)
        case .opus: return Color(red: 0.92, green: 0.72, blue: 0.45)
        }
    }
}

// MARK: - DevNotebookEntry

struct DevNotebookEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var createdAt: Date
    var kind: DevNotebookEntryKind
    var aiModel: DevNotebookAIModel?
    var body: String
    /// Tab name at capture time (e.g. Today, Tasks).
    var moduleLabel: String
    /// Human-readable location string (tab · engine · screen).
    var contextLine: String

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        kind: DevNotebookEntryKind,
        aiModel: DevNotebookAIModel? = nil,
        body: String,
        moduleLabel: String,
        contextLine: String
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.aiModel = aiModel
        self.body = body
        self.moduleLabel = moduleLabel
        self.contextLine = contextLine
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, kind, aiModel, body, moduleLabel, contextLine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        kind = try container.decode(DevNotebookEntryKind.self, forKey: .kind)
        aiModel = try container.decodeIfPresent(DevNotebookAIModel.self, forKey: .aiModel)
        body = try container.decode(String.self, forKey: .body)
        moduleLabel = try container.decode(String.self, forKey: .moduleLabel)
        contextLine = try container.decode(String.self, forKey: .contextLine)
    }

    var listTitle: String {
        let t = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = t.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if first.count <= 80 { return first.isEmpty ? "(empty)" : first }
        return String(first.prefix(77)) + "…"
    }
}
