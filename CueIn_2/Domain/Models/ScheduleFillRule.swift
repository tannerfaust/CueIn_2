import Foundation

// MARK: - AutofillTaskPickOrder

/// How autofill ranks Timeline pool candidates before packing them into a block.
enum AutofillTaskPickOrder: String, Codable, CaseIterable, Equatable {
    /// Starred cards first, then Tasks-app priority (when linked), then earlier on the timeline.
    case priority
    /// Deep / focus-style work first, then admin and shallow blocks, then life / routine.
    case depthFirst

    var editorTitle: String {
        switch self {
        case .priority: return "By priority"
        case .depthFirst: return "By depth of work"
        }
    }

    var editorDetail: String {
        switch self {
        case .priority:
            return "Starred and urgent tasks first, then the rest by time on the timeline."
        case .depthFirst:
            return "Focus and deep-work cards first, then admin and multitask-style blocks, then lighter routine items."
        }
    }

    var summaryToken: String {
        switch self {
        case .priority: return "Priority order"
        case .depthFirst: return "Depth order"
        }
    }
}

// MARK: - ScheduleFillRule
/// Describes which Execution tasks a schedule frame is allowed to pull.
/// Field and project are string labels until the Tasks tab owns real entities.
/// `folder` is kept for decoding old data but is not used for matching or in the editor.

struct ScheduleFillRule: Codable, Equatable {
    var blockType: BlockType?
    var field: String?
    var project: String?
    var folder: String?
    /// When true, only Timeline cards that read as deep-work / focus (`ExecutionTaskCard`).
    var deepWorkOnly: Bool
    /// Packing order for autofill candidates (defaults to priority-based).
    var pickOrder: AutofillTaskPickOrder

    init(
        blockType: BlockType? = nil,
        field: String? = nil,
        project: String? = nil,
        folder: String? = nil,
        deepWorkOnly: Bool = false,
        pickOrder: AutofillTaskPickOrder = .priority
    ) {
        self.blockType = blockType
        self.field = field.cleanedOptional
        self.project = project.cleanedOptional
        self.folder = folder.cleanedOptional
        self.deepWorkOnly = deepWorkOnly
        self.pickOrder = pickOrder
    }

    enum CodingKeys: String, CodingKey {
        case blockType, field, project, folder, deepWorkOnly, pickOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        blockType = try c.decodeIfPresent(BlockType.self, forKey: .blockType)
        field = try c.decodeIfPresent(String.self, forKey: .field).cleanedOptional
        project = try c.decodeIfPresent(String.self, forKey: .project).cleanedOptional
        folder = try c.decodeIfPresent(String.self, forKey: .folder).cleanedOptional
        deepWorkOnly = try c.decodeIfPresent(Bool.self, forKey: .deepWorkOnly) ?? false
        pickOrder = try c.decodeIfPresent(AutofillTaskPickOrder.self, forKey: .pickOrder) ?? .priority
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(blockType, forKey: .blockType)
        try c.encodeIfPresent(field, forKey: .field)
        try c.encodeIfPresent(project, forKey: .project)
        try c.encodeIfPresent(folder, forKey: .folder)
        try c.encode(deepWorkOnly, forKey: .deepWorkOnly)
        try c.encode(pickOrder, forKey: .pickOrder)
    }

    var hasScope: Bool {
        field != nil || project != nil
    }

    var displayLabel: String {
        var parts: [String] = []
        if let field { parts.append(field) }
        if let project { parts.append(project) }
        if deepWorkOnly { parts.append("Deep work") }
        if pickOrder != .priority {
            parts.append(pickOrder.summaryToken)
        }
        if parts.isEmpty { return "Any task" }
        return parts.joined(separator: " · ")
    }

    func matches(_ task: ExecutionTaskCard) -> Bool {
        if deepWorkOnly {
            let isDeep =
                task.blockType == .focus
                || task.lane == .focus
            guard isDeep else { return false }
        }
        // Card / block type is not used for pool matching (legacy `blockType` is ignored).
        guard matches(field, task.field) else { return false }
        guard matches(project, task.project) else { return false }
        return true
    }

    private func matches(_ expected: String?, _ actual: String?) -> Bool {
        guard let expected else { return true }
        return actual?.caseInsensitiveCompare(expected) == .orderedSame
    }
}

private extension Optional where Wrapped == String {
    var cleanedOptional: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return value
    }
}
