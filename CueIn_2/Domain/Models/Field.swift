import SwiftUI

// MARK: - Field
/// A top-level "area of work" (e.g. CueIn, Health, Learning, Operations).
/// Holds no tasks directly — tasks reference `fieldID`. Projects belong to a field.

struct Field: Identifiable, Codable, Hashable {

    let id: UUID
    var name: String
    var summary: String
    var iconName: String
    var colorHex: UInt
    var createdAt: Date
    /// Bumped whenever the user edits the field. Required for cross-device pulls
    /// to advance the per-table sync cursor; do not derive from `createdAt`.
    var updatedAt: Date
    var isArchived: Bool

    init(
        id: UUID = UUID(),
        name: String,
        summary: String = "",
        iconName: String = "square.grid.2x2.fill",
        colorHex: UInt = 0x8E8E93,
        createdAt: Date = Date(),
        updatedAt: Date? = nil,
        isArchived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.iconName = iconName
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.isArchived = isArchived
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(UUID.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.summary = try c.decode(String.self, forKey: .summary)
        self.iconName = try c.decode(String.self, forKey: .iconName)
        self.colorHex = try c.decode(UInt.self, forKey: .colorHex)
        self.createdAt = try c.decode(Date.self, forKey: .createdAt)
        self.updatedAt = (try? c.decode(Date.self, forKey: .updatedAt)) ?? self.createdAt
        self.isArchived = try c.decode(Bool.self, forKey: .isArchived)
    }

    var color: Color { Color(hex: colorHex) }

    /// SF Symbol for UI when a task has no project. Falls back when `iconName` is empty.
    var resolvedIconSystemName: String {
        let s = iconName.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? "square.grid.2x2.fill" : s
    }
}

// MARK: - FieldPalette
/// Preset icons + colors surfaced in the create/edit sheets.

enum FieldPalette {

    static let icons: [String] = [
        "app.fill",
        "heart.fill",
        "book.fill",
        "wrench.and.screwdriver.fill",
        "briefcase.fill",
        "dumbbell.fill",
        "graduationcap.fill",
        "paintbrush.fill",
        "leaf.fill",
        "person.2.fill",
        "sparkles",
        "moon.stars.fill",
        "lightbulb.fill",
        "dollarsign.circle.fill",
        "flame.fill",
        "target",
    ]

    static let colors: [UInt] = [
        0x34C759,  // focus green
        0x5BC6B9,  // routine teal
        0xE2B253,  // fixed amber
        0xA99BE0,  // mini lavender
        0xE98989,  // soft coral
        0x79B6E8,  // soft blue
        0xF0B272,  // warm sand
        0xC096E0,  // soft violet
        0x7DD3B8,  // mint
        0xB0B0B0,  // neutral gray
    ]
}
