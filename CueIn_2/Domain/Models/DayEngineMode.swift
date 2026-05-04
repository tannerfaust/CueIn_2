import Foundation

// MARK: - DayEngineMode
/// High-level Today modes (timeline vs formula schedule), switched from the ⋯ menu.

enum DayEngineMode: String, CaseIterable, Identifiable, Codable {
    /// Declared first so `allCases` matches top-bar toggle order (left → right).
    case taskLed
    case formulaBased

    static let storageKey = "cuein.today.mode"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .formulaBased: return "Schedule"
        case .taskLed: return "Timeline"
        }
    }

    var compactLabel: String {
        switch self {
        case .formulaBased: return "Schedule"
        case .taskLed: return "Timeline"
        }
    }
}
