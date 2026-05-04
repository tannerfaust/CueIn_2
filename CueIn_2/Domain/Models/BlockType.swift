import Foundation

// MARK: - BlockType
/// Accent / lane hint for Timeline & execution rows — **not** the schedule role.
/// Scheduling shape uses ``DayBlock/pinsToClock``, ``DayBlock/schedulingPriority``, etc.

enum BlockType: String, CaseIterable, Identifiable, Codable {
    case focus
    case routine
    case fixed
    case mini

    var id: String { rawValue }

    // MARK: Display

    var label: String {
        switch self {
        case .focus:   return "Focus"
        case .routine: return "Routine"
        case .fixed:   return "Fixed"
        case .mini:    return "Mini"
        }
    }

    var icon: String {
        switch self {
        case .focus:   return "flame.fill"
        case .routine: return "arrow.triangle.2.circlepath"
        case .fixed:   return "pin.fill"
        case .mini:    return "bolt.fill"
        }
    }
}

// MARK: - SwiftUI accent bridge
// The palette lives in `CueInColors` so it stays part of the design system.
// Exposed here as a simple switch so views don't need to know colors per type.
import SwiftUI

extension BlockType {
    /// Intentionally restrained — only two types carry a color:
    /// • Focus → green (primary accent, success)
    /// • Fixed → amber (warning-adjacent: "can't move")
    /// Routine and Mini are deliberately neutral so the timeline stays calm.
    var accent: Color {
        switch self {
        case .focus:           return CueInColors.accentFocus
        case .fixed:           return CueInColors.accentFixed
        case .routine, .mini:  return CueInColors.textTertiary.opacity(0.65)
        }
    }
}
