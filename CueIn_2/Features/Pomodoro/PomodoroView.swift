import SwiftUI
import UIKit

// MARK: - PomodoroView

struct PomodoroView: View {
    @Bindable private var store = PomodoroStore.shared
    @Environment(\.openURL) private var openURL
    @State private var showsSessionSettings = false
    /// When set (e.g. opened from Hub), shows a leading chevron that returns to Hub.
    var onRequestReturnToHub: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                    timerCard
                    primaryControls
                    rhythmPresets
                    settingsDisclosure
                }
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .navigationTitle("Timer")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let onRequestReturnToHub {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onRequestReturnToHub) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CueInColors.textPrimary)
                        }
                        .accessibilityLabel("Back to Hub")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    sessionPill
                }
            }
        .scrollDismissesKeyboard(.immediately)
        .background(CueInColors.background.ignoresSafeArea())
        .sheet(item: $store.focusCoachPresentation) { _ in
            focusCoachSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        }
    }



    private var sessionPill: some View {
        HStack(spacing: 6) {
            Image(systemName: store.isRunning ? "bolt.fill" : "timer")
                .font(.system(size: 12, weight: .semibold))
            Text(store.isRunning ? "Running" : (store.pausedRemainingSeconds == nil ? "Ready" : "Paused"))
                .font(CueInTypography.captionMedium)
        }
        .foregroundStyle(store.isRunning ? phaseAccent : CueInColors.textSecondary)
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, CueInSpacing.sm)
        .background(CueInColors.surfacePrimary, in: Capsule())
        .overlay(Capsule().strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))
    }

    private var timerCard: some View {
        CueInCard(padding: CueInSpacing.xl, cornerRadius: 22) {
            VStack(spacing: CueInSpacing.xl) {
                ZStack {
                    PomodoroTimerRing(
                        progress: store.progress,
                        accent: phaseAccent,
                        lineWidth: 16
                    )
                    .frame(width: 250, height: 250)

                    VStack(spacing: CueInSpacing.sm) {
                        Text(formattedCountdown)
                            .font(.system(size: 54, weight: .semibold, design: .rounded))
                            .foregroundStyle(CueInColors.textPrimary)
                            .monospacedDigit()
                            .minimumScaleFactor(0.82)
                            .accessibilityLabel("\(store.phase.accessibilitySummary), \(formattedSpokenCountdown) remaining")

                        Text(cycleCaption)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }

                HStack(spacing: CueInSpacing.sm) {
                    compactMetric(title: "Focus", value: "\(store.durationPreferences.workMinutes)m")
                    compactMetric(title: "Break", value: "\(store.durationPreferences.shortBreakMinutes)m")
                    compactMetric(title: "Long", value: "\(store.durationPreferences.longBreakMinutes)m")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private func compactMetric(title: String, value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
                .monospacedDigit()
            Text(title)
                .font(CueInTypography.micro)
                .foregroundStyle(CueInColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, CueInSpacing.sm)
        .background(CueInColors.surfaceSecondary.opacity(0.65), in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))
    }

    private var primaryControls: some View {
        HStack(spacing: CueInSpacing.md) {
            Button {
                store.isRunning ? store.pause() : store.start()
            } label: {
                Label(primaryActionTitle, systemImage: store.isRunning ? "pause.fill" : "play.fill")
                    .font(CueInTypography.bodyMedium)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(phaseAccent)

            Button {
                store.skipPhase()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.bordered)
            .disabled(!store.canSkipPhase)
            .accessibilityLabel("Skip phase")

            Button(role: .destructive) {
                store.resetSession()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Reset timer")
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private var rhythmPresets: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            sectionTitle("Rhythm")

            HStack(spacing: CueInSpacing.sm) {
                presetButton(title: "25 / 5", work: 25, short: 5, long: 15, every: 4)
                presetButton(title: "50 / 10", work: 50, short: 10, long: 25, every: 3)
                presetButton(title: "90 / 15", work: 90, short: 15, long: 30, every: 2)
            }
            .padding(.horizontal, CueInSpacing.screenHorizontal)
        }
    }

    private func presetButton(title: String, work: Int, short: Int, long: Int, every: Int) -> some View {
        let selected = store.durationPreferences.workMinutes == work
            && store.durationPreferences.shortBreakMinutes == short
            && store.durationPreferences.longBreakMinutes == long
            && store.durationPreferences.longBreakEvery == every

        return Button {
            store.durationPreferences = PomodoroDurationPreferences(
                workMinutes: work,
                shortBreakMinutes: short,
                longBreakMinutes: long,
                longBreakEvery: every
            )
        } label: {
            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(selected ? CueInColors.textPrimary : CueInColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background(selected ? phaseAccent.opacity(0.18) : CueInColors.surfacePrimary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous)
                        .strokeBorder(selected ? phaseAccent.opacity(0.55) : CueInColors.cardBorder, lineWidth: 0.7)
                )
        }
        .buttonStyle(.plain)
        .disabled(store.isRunning)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var settingsDisclosure: some View {
        CueInCard {
            DisclosureGroup(isExpanded: $showsSessionSettings) {
                VStack(spacing: CueInSpacing.sm) {
                    durationStepperRow(title: "Focus", value: durationBinding(\.workMinutes), range: 5...120, step: 5, suffix: "min")
                    durationStepperRow(title: "Short break", value: durationBinding(\.shortBreakMinutes), range: 1...30, step: 1, suffix: "min")
                    durationStepperRow(title: "Long break", value: durationBinding(\.longBreakMinutes), range: 5...45, step: 5, suffix: "min")
                    durationStepperRow(title: "Long break every", value: durationBinding(\.longBreakEvery), range: 2...8, step: 1, suffix: "blocks")

                    Divider().overlay(CueInColors.divider)

                    Toggle("End alerts", isOn: notificationBinding)
                        .font(CueInTypography.bodyMedium)
                        .tint(phaseAccent)

                    Toggle("Keep screen awake", isOn: $store.keepScreenAwakeDuringWork)
                        .font(CueInTypography.bodyMedium)
                        .tint(phaseAccent)

                    Toggle("Start checklist", isOn: $store.showFocusCoachOnWorkStart)
                        .font(CueInTypography.bodyMedium)
                        .tint(phaseAccent)

                    Button {
                        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                            openURL(url)
                        }
                    } label: {
                        Label("Notification settings", systemImage: "bell.badge")
                            .font(CueInTypography.captionMedium)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(CueInColors.accentRoutine)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, CueInSpacing.xs)
                }
                .padding(.top, CueInSpacing.md)
            } label: {
                Text("Session settings")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
            }
            .tint(CueInColors.textSecondary)
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(CueInTypography.headline)
            .foregroundStyle(CueInColors.textPrimary)
            .padding(.horizontal, CueInSpacing.screenHorizontal)
    }

    private func durationBinding(_ keyPath: WritableKeyPath<PomodoroDurationPreferences, Int>) -> Binding<Int> {
        Binding(
            get: { store.durationPreferences[keyPath: keyPath] },
            set: { newValue in
                var preferences = store.durationPreferences
                preferences[keyPath: keyPath] = newValue
                store.durationPreferences = preferences
            }
        )
    }

    private func durationStepperRow(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int,
        suffix: String
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(title)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer()
                Text("\(value.wrappedValue) \(suffix)")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .monospacedDigit()
            }
        }
        .disabled(store.isRunning)
    }

    private var focusCoachSheet: some View {
        CueInBottomSheet(title: "Start checklist", onDismiss: { store.dismissFocusCoach() }) {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                coachRow(icon: "moon.zzz.fill", title: "Silence notifications")
                coachRow(icon: "iphone.gen3", title: "Keep the timer visible")
                coachRow(icon: "scope", title: "Name the next block")

                Button("Start") {
                    store.dismissFocusCoach()
                }
                .buttonStyle(.borderedProminent)
                .tint(phaseAccent)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func coachRow(icon: String, title: String) -> some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(phaseAccent)
                .frame(width: 34, height: 34)
                .background(phaseAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
        }
    }

    private var phaseAccent: Color {
        store.isOnWorkPhase ? CueInColors.accentFocus : CueInColors.accentRoutine
    }

    private var primaryActionTitle: String {
        store.isRunning ? "Pause" : (store.pausedRemainingSeconds == nil ? "Start" : "Resume")
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { store.notifyWhenPhaseEnds },
            set: { newValue in
                Task { await store.applyNotificationToggle(newValue) }
            }
        )
    }

    private var formattedCountdown: String {
        let m = store.remainingSeconds / 60
        let s = store.remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var formattedSpokenCountdown: String {
        let m = store.remainingSeconds / 60
        let s = store.remainingSeconds % 60
        return "\(m) minutes, \(s) seconds"
    }

    private var cycleCaption: String {
        switch store.phase {
        case .work:
            let n = store.workoutsUntilLongBreak
            return n == 1 ? "Long break next." : "\(n) focus blocks to long break."
        case .shortBreak:
            return "Short break."
        case .longBreak:
            return "Long break."
        }
    }
}

#Preview {
    PomodoroView()
        .cueInPreferredColorScheme()
}
