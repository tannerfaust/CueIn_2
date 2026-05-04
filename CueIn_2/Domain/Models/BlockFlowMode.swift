import Foundation

// MARK: - BlockFlowMode
/// How a block hands off to the next one during a **timeless** (duration-first) run.
///
/// - **Blocking**: the next block cannot become active until this block is finished
///   (time may run past the planned slice while you keep working).
/// - **Flowing**: when the planned window ends, execution is treated as moving on
///   automatically (like a chained timer).

enum BlockFlowMode: String, Codable, CaseIterable, Identifiable {
    case blocking
    case flowing

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blocking: return "Blocking"
        case .flowing:  return "Flowing"
        }
    }

    /// SF Symbol for compact chips in the block editor.
    var editorIconName: String {
        switch self {
        case .blocking: return "hand.raised.fill"
        case .flowing: return "arrow.right.circle"
        }
    }

    /// Explains live-run behaviour (see ``TodayViewModel/deriveProgressiveRunBlockStates(runStartedAt:progressNow:)``).
    var scheduleEditorHint: String {
        switch self {
        case .blocking:
            return "After Start, this block stays current past the timer until you finish it. Later blocks wait."
        case .flowing:
            return "After Start, when the timer reaches zero the schedule moves on. You can still check off steps afterward."
        }
    }
}
