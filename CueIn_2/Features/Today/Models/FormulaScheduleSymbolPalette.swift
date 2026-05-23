import Foundation

// MARK: - FormulaScheduleSymbolPalette

/// SF Symbols offered when saving a TimeMap to the library.
enum FormulaScheduleSymbolPalette {
    static let symbols: [String] = [
        "calendar",
        "sparkles",
        "bolt.fill",
        "sun.max.fill",
        "moon.fill",
        "heart.text.square.fill",
        "square.stack.fill",
        "leaf.fill",
        "book.fill",
        "figure.run",
        "cup.and.saucer.fill",
        "star.fill",
        "flame.fill",
        "briefcase.fill",
        "house.fill",
        "clock.fill",
    ]

    /// Spoken label for VoiceOver — not shown in the picker UI.
    static func accessibilityLabel(for symbol: String) -> String {
        switch symbol {
        case "calendar": return "Calendar"
        case "sparkles": return "Sparkles"
        case "bolt.fill": return "Lightning"
        case "sun.max.fill": return "Sun"
        case "moon.fill": return "Moon"
        case "heart.text.square.fill": return "Journal"
        case "square.stack.fill": return "Stack"
        case "leaf.fill": return "Leaf"
        case "book.fill": return "Book"
        case "figure.run": return "Running"
        case "cup.and.saucer.fill": return "Coffee"
        case "star.fill": return "Star"
        case "flame.fill": return "Flame"
        case "briefcase.fill": return "Work"
        case "house.fill": return "Home"
        case "clock.fill": return "Clock"
        default: return "Icon"
        }
    }
}
