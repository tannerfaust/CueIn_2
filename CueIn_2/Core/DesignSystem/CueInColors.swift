import SwiftUI
#if os(iOS)
import UIKit
#endif

enum CueInThemePreference: String, CaseIterable, Identifiable {
    case dark
    case light

    static let storageKey = "cuein.appearance.theme"
    static let defaultValue: CueInThemePreference = .dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        }
    }

    var subtitle: String {
        switch self {
        case .dark: return "Deep graphite surfaces"
        case .light: return "Clean white Reminders-style surfaces"
        }
    }

    var icon: String {
        switch self {
        case .dark: return "moon.fill"
        case .light: return "sun.max.fill"
        }
    }

    var colorScheme: ColorScheme {
        switch self {
        case .dark: return .dark
        case .light: return .light
        }
    }

    static var current: CueInThemePreference {
        let rawValue = UserDefaults.standard.string(forKey: storageKey)
        return CueInThemePreference(rawValue: rawValue ?? "") ?? defaultValue
    }
}

private struct CueInPreferredColorSchemeModifier: ViewModifier {
    @AppStorage(CueInThemePreference.storageKey) private var themeRawValue = CueInThemePreference.defaultValue.rawValue

    private var theme: CueInThemePreference {
        CueInThemePreference(rawValue: themeRawValue) ?? .defaultValue
    }

    func body(content: Content) -> some View {
        content.preferredColorScheme(theme.colorScheme)
    }
}

extension View {
    func cueInPreferredColorScheme() -> some View {
        modifier(CueInPreferredColorSchemeModifier())
    }
}

// MARK: - CueIn Color System
/// Neutral, minimalist palette. Dark stays graphite; light is white, grouped, and Reminders-clean.

enum CueInColors {

    // MARK: Backgrounds

    /// App canvas.
    static var background: Color { themed(dark: 0x0D0D0D, light: 0xF7F7F8) }

    /// Primary card surface.
    static var surfacePrimary: Color { themed(dark: 0x1C1C1E, light: 0xFFFFFF) }

    /// Elevated surface
    static var surfaceSecondary: Color { themed(dark: 0x2C2C2E, light: 0xF2F2F7) }

    /// Tertiary / subtle layering
    static var surfaceTertiary: Color { themed(dark: 0x3A3A3C, light: 0xE5E5EA) }

    // MARK: Text

    /// High-emphasis text.
    static var textPrimary: Color { themed(dark: Color.white, light: Color.black, darkOpacity: 0.92, lightOpacity: 0.88) }

    /// Medium-emphasis text
    static var textSecondary: Color { themed(dark: Color.white, light: Color.black, darkOpacity: 0.55, lightOpacity: 0.56) }

    /// Low-emphasis / metadata
    static var textTertiary: Color { themed(dark: Color.white, light: Color.black, darkOpacity: 0.30, lightOpacity: 0.34) }

    // MARK: Semantic — only used for actual meaning

    /// Completed / success — soft teal
    static var success: Color { themed(dark: 0x30D158, light: 0x34C759) }

    /// Warning / caution
    static var warning: Color { themed(dark: 0xFFD60A, light: 0xC88A00) }

    /// Destructive
    static var danger: Color { themed(dark: 0xFF453A, light: 0xFF3B30) }

    // MARK: Subtle tints — very muted, only for differentiation

    /// Active block subtle tint
    static var activeHint: Color { themed(dark: Color.white, light: Color.black, darkOpacity: 0.06, lightOpacity: 0.035) }

    // MARK: Dividers

    static var divider: Color { themed(dark: Color.white, light: Color.black, darkOpacity: 0.08, lightOpacity: 0.08) }

    /// Card border — very subtle
    static var cardBorder: Color { themed(dark: Color.white, light: Color.black, darkOpacity: 0.06, lightOpacity: 0.07) }

    // MARK: Block-type accents
    /// Muted accent colors used as thin rails / chip tints on the Today timeline.
    /// Kept low-chroma so the canvas stays calm per Style Guide.

    /// Focus — the product's primary accent. Green, matches `success`.
    static var accentFocus: Color { Color(hex: 0x34C759) }

    /// Routine — soft teal / sea-green, steady and restorative.
    static var accentRoutine: Color { Color(hex: 0x5BC6B9) }

    /// Fixed — warm amber, signals "this can't move".
    static var accentFixed: Color { Color(hex: 0xE2B253) }

    /// Mini — muted lavender, signals "lightweight / filler".
    static var accentMini: Color { Color(hex: 0xA99BE0) }

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

    /// Soft pastel fill for the **running** schedule block card — mixed from the block's own accent.
    static func scheduleRunningBlockWash(accent: Color) -> Color {
        let partner: Color = CueInThemePreference.current == .light
            ? Color.white
            : surfaceSecondary
        let partnerAmount: CGFloat = CueInThemePreference.current == .light ? 0.84 : 0.78
        return accent.cueInBlended(with: partner, partnerAmount: partnerAmount)
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

    private static func themed(dark: UInt, light: UInt) -> Color {
        Color(hex: CueInThemePreference.current == .light ? light : dark)
    }

    private static func themed(
        dark: Color,
        light: Color,
        darkOpacity: CGFloat,
        lightOpacity: CGFloat
    ) -> Color {
        let isLight = CueInThemePreference.current == .light
        return (isLight ? light : dark).opacity(isLight ? lightOpacity : darkOpacity)
    }
}

// MARK: - Color blend

extension Color {
    /// Linear blend toward `partner`; `partnerAmount` 0 = self, 1 = partner.
    fileprivate func cueInBlended(with partner: Color, partnerAmount: CGFloat) -> Color {
        let t = min(max(partnerAmount, 0), 1)
        #if os(iOS)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        guard UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1),
              UIColor(partner).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        else { return self.opacity(1 - t) }
        return Color(
            red: Double(r1 + (r2 - r1) * t),
            green: Double(g1 + (g2 - g1) * t),
            blue: Double(b1 + (b2 - b1) * t),
            opacity: Double(a1 + (a2 - a1) * t)
        )
        #else
        return self.opacity(1 - t)
        #endif
    }
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

#if os(iOS)
private extension UIColor {
    convenience init(hex: UInt, alpha: CGFloat = 1.0) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}
#endif
