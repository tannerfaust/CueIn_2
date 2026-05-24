import Foundation

// MARK: - FormulaBlockStartStrategy

enum FormulaBlockStartStrategy: Sendable {
    /// Complete the running block (and any blocks in between), then start the chosen block.
    case finishPriorAndStart
    /// Start the chosen block now; move the running block to immediately after it (keeps in-between blocks in order after that).
    case startNowDeferActiveAfter
}

// MARK: - FormulaBlockStartPrompt

/// Copy and IDs for the focus-mode “start this block now” confirmation.
struct FormulaBlockStartPrompt: Identifiable, Sendable {
    let targetBlockID: UUID
    let targetTitle: String
    let priorBlockID: UUID
    let priorTitle: String
    let betweenBlockTitles: [String]

    var id: UUID { targetBlockID }

    var dialogTitle: String {
        "Start \(targetTitle) now?"
    }

    var message: String {
        var lines: [String] = []
        lines.append("You're leaving \(priorTitle) before it ends.")
        if !betweenBlockTitles.isEmpty {
            let count = betweenBlockTitles.count
            let noun = count == 1 ? "block" : "blocks"
            let list = betweenBlockTitles.joined(separator: ", ")
            lines.append("\(count) \(noun) in between (\(list)) will be skipped if you finish and jump ahead.")
        }
        lines.append("Or start \(targetTitle) now and keep \(priorTitle) on your schedule right after it.")
        return lines.joined(separator: " ")
    }

    var finishPriorLabel: String {
        if betweenBlockTitles.isEmpty {
            return "Finish \(priorTitle), start \(targetTitle)"
        }
        return "Finish \(priorTitle) & skip to \(targetTitle)"
    }

    var deferPriorLabel: String {
        if betweenBlockTitles.isEmpty {
            return "Start \(targetTitle), \(priorTitle) next"
        }
        return "Start \(targetTitle), \(priorTitle) after"
    }
}
