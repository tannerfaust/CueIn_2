import SwiftUI

#if os(iOS)

// MARK: - FloatingTabBar
/// Floating Liquid Glass tab bar tuned to match the native iOS 26 visual language.

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    let tabs: [AppTab]
    @Namespace private var indicatorNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw
        = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue

    private var taskLedPresentation: TodayDisplayPreferences.TaskLedViewMode {
        TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
    }

    private var barHeight: CGFloat { CueInLayout.floatingBarHeight }
    /// Selection pill stays slightly shorter than the bar for glass margins.
    private var pillHeight: CGFloat { barHeight - 14 }
    private var selectionAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.32, dampingFraction: 0.78, blendDuration: 0.08)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tabs) { tab in
                tabItem(for: tab)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 7)
        .frame(height: barHeight)
        .modifier(TabBarGlassModifier())
        // Keep the bar compact regardless of the system Dynamic Type size.
        .dynamicTypeSize(.xSmall ... .large)
        .animation(selectionAnimation, value: selectedTab)
    }

    @ViewBuilder
    private func tabItem(for tab: AppTab) -> some View {
        let isSelected = selectedTab == tab
        let activeSymbol = tabBarSymbol(for: tab, isSelected: isSelected)
        let title = tabBarTitleString(for: tab)

        Button {
            withAnimation(selectionAnimation) {
                selectedTab = tab
            }
        } label: {
            ZStack {
                if isSelected {
                    selectedPill
                        .frame(height: pillHeight)
                        .matchedGeometryEffect(id: "pill", in: indicatorNamespace)
                        .transition(.scale(scale: 0.88).combined(with: .opacity))
                }

                VStack(spacing: 3) {
                    tabBarIcon(isSelected: isSelected, systemName: activeSymbol)
                    tabBarTitle(title: title)
                }
                .foregroundStyle(isSelected ? CueInColors.textPrimary : CueInColors.textTertiary)
                .scaleEffect(isSelected && !reduceMotion ? 1.04 : 1)
                .offset(y: isSelected && !reduceMotion ? -1 : 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func tabBarSymbol(for tab: AppTab, isSelected: Bool) -> String {
        if tab == .taskLed {
            return taskLedPresentation.icon
        }
        return isSelected ? tab.icon : tab.iconInactive
    }

    private func tabBarTitleString(for tab: AppTab) -> String {
        if tab == .taskLed {
            return taskLedPresentation.title
        }
        return tab.label
    }

    @ViewBuilder
    private func tabBarIcon(isSelected: Bool, systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 22, weight: isSelected ? .semibold : .regular))
            .frame(width: 26, height: 26)
    }

    @ViewBuilder
    private func tabBarTitle(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .fixedSize()
    }

    @ViewBuilder
    private var selectedPill: some View {
        if #available(iOS 26, *) {
            Color.clear
                .glassEffect(
                    .regular
                        .tint(CueInColors.activeHint)
                        .interactive(),
                    in: .capsule
                )
                .glassEffectID("selected-tab", in: indicatorNamespace)
        } else {
            Capsule()
                .fill(CueInColors.activeHint)
        }
    }
}

private struct TabBarGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .cueInGlass(
                .capsule,
                tint: CueInColors.activeHint,
                interactive: false,
                showsBorder: true,
                borderColor: CueInColors.cardBorder,
                borderWidth: 0.75,
                shadow: CueInGlassShadow(color: Color.black.opacity(0.24), radius: 22, x: 0, y: 8)
            )
    }
}

#Preview {
    ZStack {
        LinearGradient(
            colors: [Color(red: 0.7, green: 0.33, blue: 0.04),
                     Color(red: 0.4, green: 0.18, blue: 0.04)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()

        VStack(spacing: 10) {
            ForEach(0..<6, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 14)
                    .fill(.black.opacity(0.45))
                    .frame(height: 72)
                    .padding(.horizontal, 16)
            }
        }

        VStack {
            Spacer()
            HStack(alignment: .center, spacing: 10) {
                FloatingTabBar(
                    selectedTab: .constant(.taskLed),
                    tabs: AppTab.defaultTabs
                )
                FloatingPlusButton(onTap: {})
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }
    .cueInPreferredColorScheme()
}

#endif
