import SwiftUI

// MARK: - StatsView
/// Placeholder Stats tab — neutral, clean, no colored elements.

struct StatsView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                    Text("Stats")
                        .font(CueInTypography.largeTitle)
                        .foregroundStyle(CueInColors.textPrimary)

                    Text("See how you're actually living")
                        .font(CueInTypography.body)
                        .foregroundStyle(CueInColors.textSecondary)
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.base)

                VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                    Text("Today")
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)
                    TodayProgressSummaryCard()
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)

                // Weekly Summary
                CueInCard {
                    VStack(alignment: .leading, spacing: CueInSpacing.base) {
                        HStack {
                            Text("This Week")
                                .font(CueInTypography.headline)
                                .foregroundStyle(CueInColors.textPrimary)
                            Spacer()
                            Text("Apr 17–23")
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.textTertiary)
                        }

                        HStack(spacing: CueInSpacing.xl) {
                            statRing(value: 0.73, label: "Completion")
                            statRing(value: 0.85, label: "Consistency")
                            statRing(value: 0.61, label: "Focus Time")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)

                // Time Allocation
                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    Text("Time Allocation")
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)

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

                // Trends
                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    Text("Trends")
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)

                    HStack(spacing: CueInSpacing.md) {
                        trendCard(title: "Tasks / Day", value: "8.3", trend: "+12%", isUp: true)
                        trendCard(title: "Focus Hours", value: "3.2h", trend: "-5%", isUp: false)
                    }

                    HStack(spacing: CueInSpacing.md) {
                        trendCard(title: "Block Adherence", value: "78%", trend: "+8%", isUp: true)
                        trendCard(title: "Replan Rate", value: "2.1x", trend: "-15%", isUp: true)
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)

                // Activity
                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    Text("7-Day Activity")
                        .font(CueInTypography.title)
                        .foregroundStyle(CueInColors.textPrimary)

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
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
    }

    // MARK: - Components

    @ViewBuilder
    private func statRing(value: Double, label: String) -> some View {
        VStack(spacing: CueInSpacing.sm) {
            ZStack {
                Circle()
                    .stroke(CueInColors.surfaceTertiary, lineWidth: 4)
                    .frame(width: 52, height: 52)

                Circle()
                    .trim(from: 0, to: value)
                    .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 4, lineCap: .round))
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
            let step = w / CGFloat(data.count - 1)

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
    .preferredColorScheme(.dark)
}
