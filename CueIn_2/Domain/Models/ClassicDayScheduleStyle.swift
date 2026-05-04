import Foundation

// MARK: - ClassicDayScheduleStyle
/// Variants of the classic, block-driven Today experience.
///
/// - **timedSlots**: blocks are anchored to real clock times for the day (calendar-like).
/// - **timeless**: blocks are defined mainly by **durations**; after *Start run* (with a chosen
///   **day end**), a pluggable ``DayRunPlanning`` engine lays out `start`/`end` inside that window.
///   Tasks stay inside their blocks; each block's ``BlockFlowMode`` controls blocking vs flowing handoff.

enum ClassicDayScheduleStyle: String, Codable, CaseIterable, Identifiable {
    case timedSlots
    case timeless

    var id: String { rawValue }

    var label: String {
        switch self {
        case .timedSlots: return "Clock slots"
        case .timeless:   return "Timeless"
        }
    }
}
