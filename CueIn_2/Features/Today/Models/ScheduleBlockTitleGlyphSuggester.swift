import Foundation

// MARK: - ScheduleBlockTitleGlyphSuggester

/// Maps free-form schedule block titles to timeline SF Symbols (English-first keywords).
/// Rules run **in order**; the first match wins. Uses substring checks for phrases and
/// **whole-word** checks for short tokens that would false-positive inside other words (e.g. `sync` vs `async`).
enum ScheduleBlockTitleGlyphSuggester {

    private enum Pattern {
        /// Lowercased substring anywhere in the title.
        case substring(String)
        /// Alphanumeric token (split on non-letters); avoids `async` matching `sync`.
        case word(String)
    }

    private struct Rule {
        let pattern: Pattern
        let symbol: String
    }

    /// Ordered most-specific → general. Symbols must appear in ``ScheduleTimelineGlyphPalette``.
    private static let rules: [Rule] = [
        Rule(pattern: .substring("deep work"), symbol: "brain.head.profile"),
        Rule(pattern: .substring("deepwork"), symbol: "brain.head.profile"),
        Rule(pattern: .substring("heads down"), symbol: "moon.fill"),
        Rule(pattern: .substring("focus block"), symbol: "moon.fill"),

        Rule(pattern: .substring("video call"), symbol: "video.fill"),
        Rule(pattern: .substring("videocall"), symbol: "video.fill"),
        Rule(pattern: .substring("google meet"), symbol: "video.fill"),
        Rule(pattern: .word("zoom"), symbol: "video.fill"),
        Rule(pattern: .word("teams"), symbol: "video.fill"),

        Rule(pattern: .substring("standup"), symbol: "calendar"),
        Rule(pattern: .substring("stand-up"), symbol: "calendar"),
        Rule(pattern: .substring("stand up"), symbol: "calendar"),
        Rule(pattern: .substring("1:1"), symbol: "calendar"),
        Rule(pattern: .substring("one on one"), symbol: "calendar"),
        Rule(pattern: .substring("1-on-1"), symbol: "calendar"),

        Rule(pattern: .word("meeting"), symbol: "calendar"),
        Rule(pattern: .word("meetings"), symbol: "calendar"),
        Rule(pattern: .word("sync"), symbol: "calendar"),

        Rule(pattern: .substring("e-mail"), symbol: "envelope.fill"),
        Rule(pattern: .word("email"), symbol: "envelope.fill"),
        Rule(pattern: .word("inbox"), symbol: "envelope.fill"),

        Rule(pattern: .word("workout"), symbol: "figure.run"),
        Rule(pattern: .word("cardio"), symbol: "figure.run"),
        Rule(pattern: .substring("jogging"), symbol: "figure.run"),
        Rule(pattern: .substring("running"), symbol: "figure.run"),
        Rule(pattern: .word("run"), symbol: "figure.run"),

        Rule(pattern: .word("gym"), symbol: "dumbbell.fill"),
        Rule(pattern: .word("lifting"), symbol: "dumbbell.fill"),
        Rule(pattern: .word("weights"), symbol: "dumbbell.fill"),

        Rule(pattern: .word("walk"), symbol: "figure.walk"),
        Rule(pattern: .word("walking"), symbol: "figure.walk"),

        Rule(pattern: .word("read"), symbol: "book.fill"),
        Rule(pattern: .word("reading"), symbol: "book.fill"),

        Rule(pattern: .word("breakfast"), symbol: "fork.knife"),
        Rule(pattern: .word("brunch"), symbol: "fork.knife"),
        Rule(pattern: .word("lunch"), symbol: "fork.knife"),
        Rule(pattern: .word("dinner"), symbol: "fork.knife"),

        Rule(pattern: .word("coffee"), symbol: "cup.and.saucer.fill"),
        Rule(pattern: .word("tea"), symbol: "cup.and.saucer.fill"),

        Rule(pattern: .substring("commute"), symbol: "car.fill"),
        Rule(pattern: .substring("driving"), symbol: "car.fill"),

        Rule(pattern: .word("flight"), symbol: "airplane"),
        Rule(pattern: .word("airport"), symbol: "airplane"),

        Rule(pattern: .word("study"), symbol: "graduationcap.fill"),
        Rule(pattern: .word("class"), symbol: "graduationcap.fill"),
        Rule(pattern: .word("lecture"), symbol: "graduationcap.fill"),

        Rule(pattern: .word("coding"), symbol: "laptopcomputer"),
        Rule(pattern: .word("code"), symbol: "laptopcomputer"),

        Rule(pattern: .word("design"), symbol: "paintpalette.fill"),

        Rule(pattern: .word("call"), symbol: "phone.fill"),

        Rule(pattern: .word("music"), symbol: "music.note"),

        Rule(pattern: .substring("photo"), symbol: "camera.fill"),

        Rule(pattern: .word("game"), symbol: "gamecontroller.fill"),

        Rule(pattern: .word("shop"), symbol: "cart.fill"),
        Rule(pattern: .word("errands"), symbol: "cart.fill"),

        Rule(pattern: .word("budget"), symbol: "chart.bar.fill"),

        Rule(pattern: .substring("meditat"), symbol: "leaf.fill"),

        Rule(pattern: .word("alarm"), symbol: "alarm.fill"),
        Rule(pattern: .word("wake"), symbol: "alarm.fill"),

        Rule(pattern: .word("pomodoro"), symbol: "timer"),
        Rule(pattern: .word("timer"), symbol: "timer"),

        Rule(pattern: .word("sleep"), symbol: "moon.fill"),
        Rule(pattern: .word("nap"), symbol: "moon.fill")
    ]

    /// Returns a palette symbol name, or `nil` if nothing matches.
    static func suggestedSymbol(for rawTitle: String) -> String? {
        let normalized = rawTitle.lowercased()
        let tokens = tokenize(normalized)
        let allowed = Set(ScheduleTimelineGlyphPalette.symbols)

        for rule in rules {
            guard matches(rule.pattern, normalized: normalized, tokens: tokens) else { continue }
            guard allowed.contains(rule.symbol) else {
                assertionFailure("ScheduleBlockTitleGlyphSuggester: \(rule.symbol) missing from ScheduleTimelineGlyphPalette")
                continue
            }
            return rule.symbol
        }
        return nil
    }

    private static func tokenize(_ normalized: String) -> Set<String> {
        let parts = normalized.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        return Set(parts.filter { !$0.isEmpty })
    }

    private static func matches(_ pattern: Pattern, normalized: String, tokens: Set<String>) -> Bool {
        switch pattern {
        case .substring(let needle):
            return normalized.contains(needle)
        case .word(let word):
            return tokens.contains(word)
        }
    }
}
