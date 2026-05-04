import SwiftUI

// MARK: - CueIn Color System
/// Neutral, dark, minimalist palette. No flashy accents.

enum CueInColors {

    // MARK: Backgrounds

    /// Near-black canvas — a hair above true black (~5% lift) for a softer, less harsh field.
    static let background = Color(hex: 0x0D0D0D)

    /// Primary card surface — very subtle lift from black
    static let surfacePrimary = Color(hex: 0x1C1C1E)

    /// Elevated surface
    static let surfaceSecondary = Color(hex: 0x2C2C2E)

    /// Tertiary / subtle layering
    static let surfaceTertiary = Color(hex: 0x3A3A3C)

    // MARK: Text

    /// High-emphasis text — clean white
    static let textPrimary = Color.white.opacity(0.92)

    /// Medium-emphasis text
    static let textSecondary = Color.white.opacity(0.55)

    /// Low-emphasis / metadata
    static let textTertiary = Color.white.opacity(0.30)

    // MARK: Semantic — only used for actual meaning

    /// Completed / success — soft teal
    static let success = Color(hex: 0x30D158)

    /// Warning / caution
    static let warning = Color(hex: 0xFFD60A)

    /// Destructive
    static let danger = Color(hex: 0xFF453A)

    // MARK: Subtle tints — very muted, only for differentiation

    /// Active block subtle tint
    static let activeHint = Color.white.opacity(0.06)

    // MARK: Dividers

    static let divider = Color.white.opacity(0.08)

    /// Card border — very subtle
    static let cardBorder = Color.white.opacity(0.06)

    // MARK: Block-type accents
    /// Muted accent colors used as thin rails / chip tints on the Today timeline.
    /// Kept low-chroma so the canvas stays calm per Style Guide.

    /// Focus — the product's primary accent. Green, matches `success`.
    static let accentFocus = Color(hex: 0x34C759)

    /// Routine — soft teal / sea-green, steady and restorative.
    static let accentRoutine = Color(hex: 0x5BC6B9)

    /// Fixed — warm amber, signals "this can't move".
    static let accentFixed = Color(hex: 0xE2B253)

    /// Mini — muted lavender, signals "lightweight / filler".
    static let accentMini = Color(hex: 0xA99BE0)

    // MARK: - Schedule block cosmetic tints
    /// Optional 0xRRGGBB override for timeline / icon colour; `nil` uses `BlockType` defaults.
    static func color(hexUInt32: UInt32) -> Color {
        Color(hex: UInt(hexUInt32 & 0x00FF_FFFF))
    }

    static func resolvedTimelineAccent(blockType: BlockType, hex: UInt32?) -> Color {
        if let h = hex {
            return color(hexUInt32: h)
        }
        return blockType.accent
    }

    /// Schedule block **Look** sheet: exactly six custom tints (plus cleared `timelineAccentHex` for automatic colour).
    static let scheduleBlockAppearanceHexChoices: [UInt32] = [
        0x34C759, // green
        0x0A84FF, // blue
        0xFF9F0A, // orange
        0xBF5AF2, // purple
        0xFF6B6B, // coral
        0x5BC6B9, // teal
    ]

    /// Legacy — prefer ``scheduleBlockAppearanceHexChoices`` for new UI.
    static let scheduleBlockAccentSwatches: [UInt32] = scheduleBlockAppearanceHexChoices
}

// MARK: - Color+Hex

extension Color {
    /// Initialize a Color from a hex integer (e.g. 0x1C1C1E).
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >>  8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255,
            opacity: alpha
        )
    }
}
