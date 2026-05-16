import SwiftUI

// MARK: - StatsView
/// Stats tab: Activity-style rings driven by Algorithm adherence, awake window, and Today tasks.
/// Page-specific settings live in the navigation menu (⋯).

struct StatsView: View {
    @State private var showStatsSettings = false
    @Bindable private var todayViewModel = TodayViewModel.shared
    @Bindable private var tasksStore = TasksStore.shared

    @AppStorage(StatsDisplayPreferences.showActivityRings) private var showActivityRings = true
    @AppStorage(StatsDisplayPreferences.showTodayProgressCard) private var showTodayProgressCard = true
    @AppStorage(StatsDisplayPreferences.showWeeklySnapshot) private var showWeeklySnapshot = false
    @AppStorage(StatsDisplayPreferences.showTimeAllocation) private var showTimeAllocation = false
    @AppStorage(StatsDisplayPreferences.showTrends) private var showTrends = false
    @AppStorage(StatsDisplayPreferences.showActivitySparkline) private var showActivitySparkline = false

    @AppStorage(StatsDisplayPreferences.dayWakeMinutes) private var dayWakeMinutes = StatsDisplayPreferences.dayWakeMinutesDefault
    @AppStorage(StatsDisplayPreferences.daySleepMinutes) private var daySleepMinutes = StatsDisplayPreferences.daySleepMinutesDefault

    var body: some View {
        NavigationStack {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let snapshot = StatsDayMetrics.makeSnapshot(
                    now: context.date,
                    viewModel: todayViewModel,
                    todayTasks: tasksStore.todayTasks,
                    wakeMinutesFromMidnight: dayWakeMinutes,
                    sleepMinutesFromMidnight: daySleepMinutes
                )

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                        if showActivityRings {
                            activityRingsSection(snapshot: snapshot)
                        }

                        if showTodayProgressCard {
                            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                                Text("Today")
                                    .font(CueInTypography.title)
                                    .foregroundStyle(CueInColors.textPrimary)
                                TodayProgressSummaryCard()
                            }
                            .padding(.horizontal, CueInSpacing.screenHorizontal)
                        }

                        if showWeeklySnapshot {
                            weeklySnapshotSection(snapshot: snapshot)
                        }

                        if showTimeAllocation {
                            timeAllocationSection
                        }

                        if showTrends {
                            trendsSection
                        }

                        if showActivitySparkline {
                            activitySparklineSection
                        }
                    }
                    .padding(.bottom, CueInLayout.scrollBottomInset)
                }
            }
            .onAppear {
                // Keep formula / timeline-derived labels fresh if Today hasn’t ticked recently.
                todayViewModel.currentTime = Date()
            }
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            showStatsSettings = true
                        } label: {
                            Label("Stats settings", systemImage: "slider.horizontal.3")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(CueInColors.textSecondary)
                    }
                    .accessibilityLabel("Stats options")
                }
            }
        }
        .sheet(isPresented: $showStatsSettings) {
            StatsSettingsSheet(isPresented: $showStatsSettings)
                .presentationDetents([.medium, .large])
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
                .presentationDragIndicator(.visible)
        }
    }


    private func activityRingsSection(snapshot: StatsDaySnapshot) -> some View {
        CueInCard {
            HStack(alignment: .top, spacing: CueInSpacing.lg) {
                StatsActivityRingsView(snapshot: snapshot)
                    .padding(.top, CueInSpacing.xs)

                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    ringLegend(
                        color: Color(red: 0.98, green: 0.35, blue: 0.38),
                        title: "Awake day",
                        caption: snapshot.awakeCaption
                    )
                    ringLegend(
                        color: CueInColors.accentFocus,
                        title: "Algorithm",
                        caption: snapshot.algorithmCaption
                    )
                    ringLegend(
                        color: Color(red: 0.35, green: 0.78, blue: 0.98),
                        title: "Today tasks",
                        caption: snapshot.todayTasksCaption
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private func ringLegend(color: Color, title: String, caption: String) -> some View {
        HStack(alignment: .top, spacing: CueInSpacing.sm) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text(caption)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func weeklySnapshotSection(snapshot: StatsDaySnapshot) -> some View {
        CueInCard {
            VStack(alignment: .leading, spacing: CueInSpacing.base) {
                HStack {
                    Text("This week")
                        .font(CueInTypography.headline)
                        .foregroundStyle(CueInColors.textPrimary)
                    Spacer()
                    Text("Sample")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }

                Text("Placeholder — will chart your real rings once history lands.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)

                HStack(spacing: CueInSpacing.xl) {
                    statRing(value: snapshot.awakeProgress, label: "Awake")
                    statRing(value: snapshot.algorithmProgress, label: "Algorithm")
                    statRing(value: snapshot.todayTasksProgress, label: "Tasks")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var timeAllocationSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionHeader("Time allocation", badge: "Sample")
            CueInCard {
                VStack(spacing: CueInSpacing.md) {
                    allocationBar(label: "Deep Work", hours: 14.5, total: 40)
                    allocationBar(label: "Meetings", hours: 6.0, total: 40)
                    allocationBar(label: "Routines", hours: 7.5, total: 40)
                    allocationBar(label: "Admin", hours: 4.0, total: 40)
                    allocationBar(label: "Breaks", hours: 3.5, total: 40)
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionHeader("Trends", badge: "Sample")
            HStack(spacing: CueInSpacing.md) {
                trendCard(title: "Tasks / Day", value: "8.3", trend: "+12%", isUp: true)
                trendCard(title: "Focus Hours", value: "3.2h", trend: "-5%", isUp: false)
            }

            HStack(spacing: CueInSpacing.md) {
                trendCard(title: "Block adherence", value: "78%", trend: "+8%", isUp: true)
                trendCard(title: "Replan rate", value: "2.1x", trend: "-15%", isUp: true)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var activitySparklineSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionHeader("7-day activity", badge: "Sample")
            CueInCard {
                VStack(spacing: CueInSpacing.md) {
                    sparkline(data: [0.4, 0.65, 0.8, 0.55, 0.9, 0.7, 0.75])

                    HStack {
                        ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, day in
                            Text(day)
                                .font(CueInTypography.micro)
                                .foregroundStyle(CueInColors.textTertiary)
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private func sectionHeader(_ title: String, badge: String) -> some View {
        HStack {
            Text(title)
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
            Spacer()
            Text(badge)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
        }
    }

    @ViewBuilder
    private func statRing(value: Double, label: String) -> some View {
        VStack(spacing: CueInSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(CueInColors.surfaceTertiary, lineWidth: 4)
                    .frame(width: 52, height: 52)

                Circle()
                    .trim(from: 0, to: value)
                    .stroke(
                        AngularGradient(
                            colors: [CueInColors.accentFocus.opacity(0.55), CueInColors.accentFocus, CueInColors.accentFocus.opacity(0.75)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round)
                    )
                    .frame(width: 52, height: 52)
                    .rotationEffect(.degrees(-90))

                Text("\(Int(value * 100))%")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .monospacedDigit()
            }

            Text(label)
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
        }
    }

    @ViewBuilder
    private func allocationBar(label: String, hours: Double, total: Double) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            HStack {
                Text(label)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer()
                Text(String(format: "%.1fh", hours))
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .monospacedDigit()
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CueInColors.surfaceTertiary)
                    Capsule()
                        .fill(Color.white.opacity(0.35))
                        .frame(width: geo.size.width * (hours / total))
                }
            }
            .frame(height: 5)
        }
    }

    @ViewBuilder
    private func trendCard(title: String, value: String, trend: String, isUp: Bool) -> some View {
        CueInCard {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                Text(title)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)

                Text(value)
                    .font(CueInTypography.title)
                    .foregroundStyle(CueInColors.textPrimary)
                    .monospacedDigit()

                HStack(spacing: 2) {
                    Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 9, weight: .medium))
                    Text(trend)
                        .font(CueInTypography.micro)
                }
                .foregroundStyle(CueInColors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func sparkline(data: [Double]) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h: CGFloat = 40
            let step = w / CGFloat(max(data.count - 1, 1))

            Path { path in
                for (i, val) in data.enumerated() {
                    let x = CGFloat(i) * step
                    let y = h - (val * h)
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
            }
            .stroke(Color.white.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

            ForEach(Array(data.enumerated()), id: \.offset) { i, val in
                let x = CGFloat(i) * step
                let y = h - (val * h)
                Circle()
                    .fill(Color.white.opacity(0.5))
                    .frame(width: 4, height: 4)
                    .position(x: x, y: y)
            }
        }
        .frame(height: 40)
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        StatsView()
    }
    .cueInPreferredColorScheme()
}
