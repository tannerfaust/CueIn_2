import SwiftUI

// MARK: - QuantifiedSelfView

struct QuantifiedSelfView: View {
    /// When set (e.g. Hub sheet), shows a **Done** button that calls this closure.
    var onRequestDismiss: (() -> Void)? = nil

    @Bindable private var store = MeasureStore.shared
    @Bindable private var tasksStore = TasksStore.shared
    @Bindable private var goalStore = GoalStrategyStore.shared

    @State private var selectedDate = Date()
    @State private var showAddSheet = false
    @State private var editingDefinition: MeasureDefinition?

    private var calendar: Calendar { .current }

    private var dayKey: String {
        calendar.measureDayKey(for: selectedDate)
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                    dateStrip

                    Text("Low-friction logging: one tap per signal. Charts show the last seven local days for context.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)

                    if store.sortedDefinitions.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.sortedDefinitions) { definition in
                            MeasureDayTrackerCard(
                                definition: definition,
                                dayKey: dayKey,
                                store: store,
                                tasksStore: tasksStore,
                                goalStore: goalStore,
                                onEdit: { editingDefinition = definition }
                            )
                        }
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.sm)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Measures")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if let onRequestDismiss {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onRequestDismiss) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CueInColors.textPrimary)
                        }
                        .accessibilityLabel("Back")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(CueInColors.accentFocus)
                    }
                    .accessibilityLabel("New tracker")
                }
            }
        }
        .cueInPreferredColorScheme()
        .onReceive(NotificationCenter.default.publisher(for: .cueInShowAddMeasureTracker)) { _ in
            showAddSheet = true
        }
        .sheet(isPresented: $showAddSheet) {
            MeasureAddTrackerSheet(onDismiss: { showAddSheet = false })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .sheet(item: $editingDefinition) { def in
            MeasureEditDefinitionSheet(definition: def, onDismiss: { editingDefinition = nil })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    private var dateStrip: some View {
        HStack(spacing: CueInSpacing.md) {
            Button {
                selectedDate = calendar.measureShiftDays(-1, from: selectedDate)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(CueInColors.surfaceSecondary.opacity(0.75), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(CueInColors.textPrimary)

            VStack(spacing: 2) {
                Text(dateHeadline)
                    .font(CueInTypography.headline)
                    .foregroundStyle(CueInColors.textPrimary)
                Text(dayKey)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)

            Button {
                selectedDate = calendar.measureShiftDays(1, from: selectedDate)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(CueInColors.surfaceSecondary.opacity(0.75), in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(CueInColors.textPrimary)
        }
    }

    private var dateHeadline: String {
        if calendar.isDateInToday(selectedDate) { return "Today" }
        if calendar.isDateInYesterday(selectedDate) { return "Yesterday" }
        if calendar.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        return selectedDate.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)

            Text("No trackers yet")
                .font(CueInTypography.headline)
                .foregroundStyle(CueInColors.textPrimary)

            Text("Add coffee, sleep, mood, or anything you want to see over time. Templates keep setup to a single tap.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                showAddSheet = true
            } label: {
                Text("Add your first tracker")
                    .font(CueInTypography.bodyMedium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CueInColors.accentFocus)
            .padding(.top, CueInSpacing.sm)
        }
        .padding(CueInSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CueInColors.surfacePrimary.opacity(0.72), in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - MeasureDayTrackerCard

private struct MeasureDayTrackerCard: View {
    let definition: MeasureDefinition
    let dayKey: String
    let store: MeasureStore
    let tasksStore: TasksStore
    let goalStore: GoalStrategyStore
    let onEdit: () -> Void

    private var spark: [CGFloat] {
        store.sparklineNormalized(definitionID: definition.id, endingDayKey: dayKey, days: 7)
    }

    var body: some View {
        CueInCard {
            VStack(alignment: .leading, spacing: CueInSpacing.md) {
                HStack(alignment: .top, spacing: CueInSpacing.sm) {
                    Image(systemName: definition.iconSystemName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(definition.title)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)

                        if let caption = linkCaption {
                            Text(caption)
                                .font(CueInTypography.caption)
                                .foregroundStyle(CueInColors.textTertiary)
                                .lineLimit(2)
                        }
                    }

                    Spacer(minLength: 0)

                    Button(action: onEdit) {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(CueInColors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Edit tracker")
                }

                MeasureSparklineView(values: spark)

                controls
            }
        }
    }

    private var linkCaption: String? {
        var parts: [String] = []
        if let tid = definition.relatedTaskID,
           let t = tasksStore.tasks.first(where: { $0.id == tid }) {
            parts.append("Task · \(t.title)")
        }
        if let gid = definition.relatedGoalID,
           let g = goalStore.goal(gid) {
            parts.append("Goal · \(g.title)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var controls: some View {
        switch definition.kind {
        case .count:
            countControls
        case .scale:
            scaleControls
        case .flag:
            flagControl
        case .duration:
            durationControls
        }
    }

    private var countValue: Int {
        if case .count(let n) = store.value(definitionID: definition.id, dayKey: dayKey) {
            return n
        }
        return 0
    }

    private var countControls: some View {
        HStack(spacing: CueInSpacing.md) {
            Button {
                store.incrementCount(definitionID: definition.id, dayKey: dayKey, delta: -1)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.system(size: 32, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CueInColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(countValue <= 0)

            VStack(spacing: 2) {
                Text("\(countValue)")
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CueInColors.textPrimary)
                if let target = definition.dailyTarget {
                    Text("\(min(countValue, target)) / \(target) today")
                        .font(CueInTypography.caption)
                        .foregroundStyle(
                            countValue >= target ? CueInColors.accentFocus.opacity(0.9) : CueInColors.textTertiary
                        )
                } else {
                    Text("tap + to add")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }
            .frame(maxWidth: .infinity)

            Button {
                store.incrementCount(definitionID: definition.id, dayKey: dayKey, delta: 1)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 32, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CueInColors.accentFocus)
            }
            .buttonStyle(.plain)
        }
    }

    private var scaleSelection: Int? {
        if case .scale(let s) = store.value(definitionID: definition.id, dayKey: dayKey) {
            return definition.clampedScale(s)
        }
        return nil
    }

    @ViewBuilder
    private var scaleControls: some View {
        let span = definition.scaleMax - definition.scaleMin + 1
        if span <= 6 {
            HStack(spacing: 6) {
                ForEach(definition.scaleMin...definition.scaleMax, id: \.self) { mark in
                    let selected = scaleSelection == mark
                    Button {
                        store.setValue(.scale(mark), definitionID: definition.id, dayKey: dayKey)
                    } label: {
                        Text("\(mark)")
                            .font(.system(size: 15, weight: selected ? .semibold : .regular, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selected
                                    ? CueInColors.accentFocus.opacity(0.22)
                                    : CueInColors.surfaceSecondary.opacity(0.55),
                                in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: CueInSpacing.chipRadius, style: .continuous)
                                    .strokeBorder(
                                        selected ? CueInColors.accentFocus.opacity(0.55) : CueInColors.cardBorder,
                                        lineWidth: selected ? 1 : 0.5
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selected ? CueInColors.textPrimary : CueInColors.textSecondary)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: CueInSpacing.xs) {
                Text(scaleSelection.map { "Value: \($0)" } ?? "Not logged")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                Slider(
                    value: Binding(
                        get: { Double(scaleSelection ?? definition.scaleMin) },
                        set: { store.setValue(.scale(Int($0.rounded())), definitionID: definition.id, dayKey: dayKey) }
                    ),
                    in: Double(definition.scaleMin)...Double(definition.scaleMax),
                    step: 1
                )
                .tint(CueInColors.accentFocus)
            }
        }
    }

    private var flagValue: Bool {
        if case .flag(let b) = store.value(definitionID: definition.id, dayKey: dayKey) {
            return b
        }
        return false
    }

    private var flagControl: some View {
        Toggle(isOn: Binding(
            get: { flagValue },
            set: { store.setValue(.flag($0), definitionID: definition.id, dayKey: dayKey) }
        )) {
            Text(flagValue ? "Yes" : "No")
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
        }
        .tint(CueInColors.accentFocus)
    }

    private var durationMinutes: Int {
        if case .duration(let m) = store.value(definitionID: definition.id, dayKey: dayKey) {
            return max(0, m)
        }
        return 0
    }

    private let durationPresets = [15, 30, 45, 60, 90, 120]

    private var durationControls: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack {
                Text(durationMinutes == 0 ? "—" : formatMinutes(durationMinutes))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CueInColors.textPrimary)
                Spacer()
                Button("Clear") {
                    store.setValue(.duration(0), definitionID: definition.id, dayKey: dayKey)
                }
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .disabled(durationMinutes == 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CueInSpacing.sm) {
                    ForEach(durationPresets, id: \.self) { m in
                        let selected = durationMinutes == m
                        Button {
                            store.setValue(.duration(m), definitionID: definition.id, dayKey: dayKey)
                        } label: {
                            Text(shortDurationLabel(m))
                                .font(CueInTypography.caption)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    selected
                                        ? CueInColors.accentFocus.opacity(0.22)
                                        : CueInColors.surfaceSecondary.opacity(0.55),
                                    in: Capsule()
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(selected ? CueInColors.textPrimary : CueInColors.textSecondary)
                    }
                }
            }
        }
    }

    private func shortDurationLabel(_ m: Int) -> String {
        if m % 60 == 0 { return "\(m / 60)h" }
        return "\(m)m"
    }

    private func formatMinutes(_ m: Int) -> String {
        let h = m / 60
        let rem = m % 60
        if h == 0 { return "\(rem) min" }
        if rem == 0 { return "\(h) h" }
        return "\(h) h \(rem)m"
    }
}

// MARK: - MeasureSparklineView

private struct MeasureSparklineView: View {
    let values: [CGFloat]

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(values.indices, id: \.self) { i in
                let h = max(4, 26 * min(1, max(0.04, values[i])))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .frame(width: 6, height: h)
            }
        }
        .frame(height: 28)
        .accessibilityLabel("Last seven days trend")
    }
}

#Preview {
    QuantifiedSelfView()
}
