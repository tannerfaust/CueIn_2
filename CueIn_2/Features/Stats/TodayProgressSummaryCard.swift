import SwiftUI

// MARK: - TodayProgressSummaryCard
/// Snapshot of tasks slated for today (store’s `todayTasks`) plus per-field counts.
/// Lives on Stats; Tasks stays a flat list without this header block.

struct TodayProgressSummaryCard: View {
    @Bindable private var store: TasksStore

    @MainActor init() {
        self.store = .shared
    }

    var body: some View {
        let todays = store.todayTasks
        let done = todays.filter(\.isCompleted).count
        let total = todays.count
        let progress: Double = total > 0 ? Double(done) / Double(total) : 0

        CueInCard {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "sun.max.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(CueInColors.accentFixed)
                        Text("TODAY")
                            .font(Font.system(size: 10, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                    Spacer()
                    Text("\(done) / \(total) done")
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textSecondary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(CueInColors.surfaceTertiary).frame(height: 4)
                        Capsule().fill(CueInColors.accentFocus)
                            .frame(width: geo.size.width * progress, height: 4)
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 4)

                let columns = [
                    GridItem(.flexible(minimum: 0), spacing: CueInSpacing.md),
                    GridItem(.flexible(minimum: 0), spacing: CueInSpacing.md),
                ]
                LazyVGrid(columns: columns, alignment: .leading, spacing: CueInSpacing.sm) {
                    ForEach(store.fields.prefix(4)) { f in
                        let s = store.progress(field: f)
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Circle()
                                .fill(f.color)
                                .frame(width: 5, height: 5)
                                .offset(y: 1)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.name)
                                    .font(CueInTypography.caption)
                                    .foregroundStyle(CueInColors.textTertiary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(s.done)/\(s.total)")
                                    .font(CueInTypography.micro)
                                    .foregroundStyle(f.color.opacity(0.85))
                                    .monospacedDigit()
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        TodayProgressSummaryCard()
            .padding()
    }
    .cueInPreferredColorScheme()
}
