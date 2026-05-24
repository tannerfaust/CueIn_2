import SwiftUI

// MARK: - Project
/// A concrete initiative inside a Field. Holds tasks via `TaskItem.projectID`.
/// Inherits color from its parent Field unless `colorHexOverride` is set.

struct Project: Identifiable, Codable, Hashable {

    enum Status: String, Codable, CaseIterable, Identifiable, Hashable {
        case active
        case paused
        case done
        case archived

        var id: String { rawValue }

        var label: String {
            switch self {
            case .active:   return "Active"
            case .paused:   return "Paused"
            case .done:     return "Done"
            case .archived: return "Archived"
            }
        }

        var icon: String {
            switch self {
            case .active:   return "circle.dotted"
            case .paused:   return "pause.circle"
            case .done:     return "checkmark.circle.fill"
            case .archived: return "archivebox.fill"
            }
        }

        var tint: Color {
            switch self {
            case .active:   return CueInColors.accentFocus
            case .paused:   return CueInColors.textTertiary
            case .done:     return CueInColors.success
            case .archived: return CueInColors.textTertiary
            }
        }
    }

    let id: UUID
    var name: String
    var summary: String
    var iconName: String
    var fieldID: UUID
    var status: Status
    var targetDate: Date?
    var colorHexOverride: UInt?
    var externalSource: String?
    var createdAt: Date
    /// Bumped whenever the user edits the project. Required for cross-device pulls
    /// to advance the per-table sync cursor; do not derive from `createdAt`.
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        summary: String = "",
        iconName: String = "folder.fill",
        fieldID: UUID,
        status: Status = .active,
        targetDate: Date? = nil,
        colorHexOverride: UInt? = nil,
        externalSource: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.iconName = iconName
        self.fieldID = fieldID
        self.status = status
        self.targetDate = targetDate
        self.colorHexOverride = colorHexOverride
        self.externalSource = externalSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.summary = try c.decode(String.self, forKey: .summary)
        self.iconName = try c.decode(String.self, forKey: .iconName)
        self.fieldID = try c.decode(UUID.self, forKey: .fieldID)
        self.status = try c.decode(Status.self, forKey: .status)
        self.targetDate = try c.decodeIfPresent(Date.self, forKey: .targetDate)
        self.colorHexOverride = try c.decodeIfPresent(UInt.self, forKey: .colorHexOverride)
        self.externalSource = try c.decodeIfPresent(String.self, forKey: .externalSource)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? self.createdAt
    }
}

extension Project {
    /// SF Symbol for UI (task pill, lists). Falls back when `iconName` is empty.
    var resolvedIconSystemName: String {
        let s = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "folder.fill" : s
    }

    var isNotionImported: Bool {
        externalSource?.localizedCaseInsensitiveCompare("notion") == .orderedSame
    }

    var isLinearImported: Bool {
        externalSource?.localizedCaseInsensitiveCompare("linear") == .orderedSame
    }

    var isExternal: Bool {
        externalSource != nil
    }
}

// MARK: - ProjectPalette

enum ProjectPalette {

    /// SF Symbols shown in **New / Edit Project** (`CreateProjectSheet`).
    /// `Project.iconName` can hold any system image name; this is the selectable gallery.
    static let icons: [String] = [
        "cube",
        "cube.fill",
        "folder.fill",
        "square.stack.fill",
        "shippingbox.fill",
        "doc.text.fill",
        "doc.plaintext.fill",
        "hammer.fill",
        "wrench.and.screwdriver.fill",
        "chart.line.uptrend.xyaxis",
        "chart.bar.fill",
        "briefcase.fill",
        "building.2.fill",
        "book.closed.fill",
        "graduationcap.fill",
        "flag.fill",
        "paperplane.fill",
        "airplane",
        "lightbulb.fill",
        "star.fill",
        "heart.fill",
        "leaf.fill",
        "flame.fill",
        "drop.fill",
        "paintbrush.fill",
        "camera.fill",
        "mic.fill",
        "gamecontroller.fill",
        "iphone",
        "laptopcomputer",
        "desktopcomputer",
        "wifi",
        "antenna.radiowaves.left.and.right",
        "person.2.fill",
        "person.crop.circle.badge.checkmark",
        "creditcard.fill",
        "cart.fill",
        "gift.fill",
        "cross.case.fill",
        "figure.run",
        "sportscourt.fill",
        "music.note",
        "headphones",
        "film.fill",
        "map.fill",
        "globe",
        "cloud.fill",
        "sun.max.fill",
        "moon.stars.fill",
        "gearshape.fill",
        "bolt.fill",
        "target",
        "scope",
        "checklist",
        "list.bullet.rectangle.fill",
        "calendar",
        "clock.fill",
        "bell.fill",
        "tray.full.fill",
        "archivebox.fill",
        "puzzlepiece.extension.fill",
    ]
}
