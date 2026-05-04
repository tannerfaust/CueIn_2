import SwiftUI

// MARK: - ExecutionTypeBadge
/// Tiny icon + label chip showing a task's execution type.

struct ExecutionTypeBadge: View {
    let type: TaskExecutionType?
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: type?.icon ?? "circle.dashed")
                .font(.system(size: 9, weight: .semibold))
            if !compact {
                Text(type?.shortLabel ?? "No type")
                    .font(Font.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(type?.color ?? CueInColors.textTertiary)
        .padding(.horizontal, compact ? 5 : 6)
        .padding(.vertical, 3)
        .background((type?.color ?? CueInColors.textTertiary).opacity(0.12))
        .clipShape(Capsule())
    }
}

// MARK: - PriorityBadge

struct PriorityBadge: View {
    let priority: TaskPriority

    var body: some View {
        if priority != .normal {
            Image(systemName: priority.icon)
                .font(.system(size: 11, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(priority.color)
        }
    }
}

// MARK: - DurationBadge

struct DurationBadge: View {
    let minutes: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "clock")
                .font(.system(size: 9))
            Text(format(minutes))
                .font(Font.system(size: 10, weight: .medium))
        }
        .foregroundStyle(CueInColors.textTertiary)
    }

    private func format(_ m: Int) -> String {
        if m < 60 { return "\(m)m" }
        let h = m / 60
        let rem = m % 60
        return rem == 0 ? "\(h)h" : "\(h)h\(rem)m"
    }
}

// MARK: - StatusDot

struct StatusDot: View {
    let color: Color
    var size: CGFloat = 7

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
    }
}
