import CoreGraphics
import Foundation

// MARK: - ReorderEngine
/// Shared reorder-by-drag algorithm used by both schedule blocks and to-do tasks.
/// Replaces: ScheduleBlockReorderEngine, TodayTodoReorderEngine (identical logic).

enum ReorderEngine {

    /// Given an ordered list of item IDs, their measured frame positions, and the current
    /// center-Y of the dragged item, return a new ordering with the dragged item inserted
    /// at its visual position.
    ///
    /// - Parameters:
    ///   - orderedIDs: The current logical order of all item IDs.
    ///   - baselineFrames: Measured CGRects (in global coordinates) for each item.
    ///   - draggedID: The ID of the item being dragged.
    ///   - centerY: The current center-Y of the dragged item (global coordinates).
    /// - Returns: A new ordering reflecting the visual position of the dragged item.
    static func visualOrder(
        orderedIDs: [UUID],
        baselineFrames: [UUID: CGRect],
        draggedID: UUID,
        centerY: CGFloat
    ) -> [UUID] {
        guard orderedIDs.contains(draggedID) else { return orderedIDs }
        let reducedIDs = orderedIDs.filter { $0 != draggedID }
        var insertPosition = reducedIDs.count

        for (index, id) in reducedIDs.enumerated() {
            guard let frame = baselineFrames[id] else { return orderedIDs }
            if centerY < frame.midY {
                insertPosition = index
                break
            }
        }

        var next = reducedIDs
        next.insert(draggedID, at: insertPosition)
        return next
    }
}
