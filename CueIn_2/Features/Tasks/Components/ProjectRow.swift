import SwiftUI

// MARK: - ProjectRow
/// Single-line project row with color dot, name, status, and a compact progress bar.

struct ProjectRow: View {
    let project: Project
    let store: TasksStore

    private var color: Color { store.color(for: project) }
    private var stats: (done: Int, total: Int) { store.progress(project: project) }
    private var progress: Double {
        stats.total > 0 ? Double(stats.done) / Double(stats.total) : 0
    }

    var body: some View {
        HStack(spacing: CueInSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(color.opacity(0.14))
                    .frame(width: 26, height: 26)
                Image(systemName: project.resolvedIconSystemName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(project.name)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                    if project.status != .active {
                        HStack(spacing: 2) {
                            Image(systemName: project.status.icon)
                                .font(.system(size: 8))
                            Text(project.status.label)
                                .font(Font.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(project.status.tint)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(project.status.tint.opacity(0.12))
                        .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Text("\(stats.total) tasks")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                    if stats.done > 0 {
                        Text("·")
                            .font(CueInTypography.micro)
                            .foregroundStyle(CueInColors.textTertiary)
                        Text("\(stats.done) done")
                            .font(CueInTypography.micro)
                            .foregroundStyle(color.opacity(0.7))
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CueInColors.surfaceTertiary)
                            .frame(height: 3)
                        Capsule()
                            .fill(color)
                            .frame(width: geo.size.width * progress, height: 3)
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
                }
                .frame(width: 52, height: 3)

                Text("\(Int(progress * 100))%")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.vertical, CueInSpacing.md)
        .contentShape(Rectangle())
    }
}
