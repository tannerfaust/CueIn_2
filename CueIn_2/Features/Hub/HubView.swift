import SwiftUI

// MARK: - HubView
/// Placeholder Hub tab — neutral, clean module grid.

struct HubView: View {
    @State private var showSettings = false
    @Bindable private var todayViewModel = TodayViewModel.shared

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                // Header
                VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                    Text("Hub")
                        .font(CueInTypography.largeTitle)
                        .foregroundStyle(CueInColors.textPrimary)

                    Text("Build and manage your system")
                        .font(CueInTypography.body)
                        .foregroundStyle(CueInColors.textSecondary)
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.base)

                // Module grid
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: CueInSpacing.md),
                        GridItem(.flexible(), spacing: CueInSpacing.md),
                    ],
                    spacing: CueInSpacing.md
                ) {
                    moduleCard(icon: "target", title: "Goals", subtitle: "Define your direction")
                    moduleCard(icon: "doc.text.fill", title: "Schedules", subtitle: "Day & week templates")
                    moduleCard(icon: "arrow.triangle.2.circlepath", title: "Routines", subtitle: "Repeatable systems")
                    moduleCard(icon: "brain.head.profile", title: "AI Tools", subtitle: "Smart assistance")
                    moduleCard(icon: "link", title: "Integrations", subtitle: "Connect your tools")
                    moduleCard(icon: "calendar", title: "Planning", subtitle: planningSubtitle)
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)

                planningSection

                // Goals
                VStack(alignment: .leading, spacing: CueInSpacing.md) {
                    HStack {
                        Text("Active Goals")
                            .font(CueInTypography.title)
                            .foregroundStyle(CueInColors.textPrimary)
                        Spacer()
                        Text("3 goals")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                    }

                    goalRow(title: "Ship CueIn v1", progress: 0.45)
                    goalRow(title: "Read 24 books this year", progress: 0.33)
                    goalRow(title: "Run 5K under 25 min", progress: 0.68)
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)

                Button {
                    showSettings = true
                } label: {
                    CueInCard {
                        HStack(spacing: CueInSpacing.md) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(CueInColors.textSecondary)
                                .frame(width: 34, height: 34)
                                .background(CueInColors.surfaceSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Settings")
                                    .font(CueInTypography.bodyMedium)
                                    .foregroundStyle(CueInColors.textPrimary)
                                Text("Preferences, account, and system options")
                                    .font(CueInTypography.caption)
                                    .foregroundStyle(CueInColors.textTertiary)
                            }

                            Spacer()

                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, CueInSpacing.screenHorizontal)
            }
            .padding(.bottom, CueInLayout.scrollBottomInset)
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                DataAndResetSettingsView()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    // MARK: - Components

    private var planningSubtitle: String {
        let count = todayViewModel.futurePinnedScheduleBlocks.count
        if count == 0 { return "Week & month view" }
        return "\(count) future pin\(count == 1 ? "" : "s")"
    }

    private var planningSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack {
                Text("Planning")
                    .font(CueInTypography.title)
                    .foregroundStyle(CueInColors.textPrimary)
                Spacer()
                Text(planningSubtitle)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
            }

            if todayViewModel.futurePinnedScheduleBlocks.isEmpty {
                CueInCard(padding: CueInSpacing.md) {
                    HStack(spacing: CueInSpacing.md) {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(CueInColors.textTertiary)
                            .frame(width: 34, height: 34)
                            .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("No future pinned blocks")
                                .font(CueInTypography.bodyMedium)
                                .foregroundStyle(CueInColors.textPrimary)
                            Text("Pinned blocks scheduled after today will appear here.")
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.textTertiary)
                        }
                    }
                }
            } else {
                VStack(spacing: CueInSpacing.sm) {
                    ForEach(todayViewModel.futurePinnedScheduleBlocks.prefix(6)) { block in
                        futurePinnedBlockRow(block)
                    }
                }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    @ViewBuilder
    private func moduleCard(icon: String, title: String, subtitle: String) -> some View {
        CueInCard {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(CueInColors.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)

                    Text(subtitle)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func futurePinnedBlockRow(_ block: DayBlock) -> some View {
        CueInCard(padding: CueInSpacing.md) {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: block.resolvedTimelineGlyph)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(CueInColors.resolvedTimelineAccent(blockType: block.type, hex: block.timelineAccentHex))
                    .frame(width: 34, height: 34)
                    .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(block.title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)

                    Text(Self.futurePinnedDateLabel(block.startTime))
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }

                Spacer()

                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CueInColors.accentFixed)
            }
        }
    }

    @ViewBuilder
    private func goalRow(title: String, progress: Double) -> some View {
        CueInCard(padding: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textSecondary)
                        .monospacedDigit()
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CueInColors.surfaceTertiary)
                        Capsule()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: geo.size.width * progress)
                    }
                }
                .frame(height: 4)
            }
        }
    }

    private static func futurePinnedDateLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d HH:mm")
        return formatter.string(from: date)
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        HubView()
    }
    .preferredColorScheme(.dark)
}
