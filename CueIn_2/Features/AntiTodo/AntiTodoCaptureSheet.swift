import SwiftUI

// MARK: - AntiTodoCaptureSheet

struct AntiTodoCaptureSheet: View {
    let store: AntiTodoStore
    let onDismiss: () -> Void

    @State private var title = ""
    @State private var scheduleEnabled = false
    @State private var scheduleKind = AntiTodoTimeRule.Kind.notBefore
    @State private var scheduleScope = AntiTodoTimeRule.DayScope.everyDay
    @State private var scheduleTime = AntiTodoTimeRule.dateForPicker(minuteOfDay: 10 * 60)
    @FocusState private var titleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private var trimmed: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canAdd: Bool { !trimmed.isEmpty }

    private var composedRule: AntiTodoTimeRule? {
        guard scheduleEnabled else { return nil }
        return AntiTodoTimeRule(
            kind: scheduleKind,
            minuteOfDay: AntiTodoTimeRule.minuteOfDay(for: scheduleTime),
            dayScope: scheduleScope
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                    captureField

                    AntiTodoScheduleControls(
                        enabled: $scheduleEnabled,
                        kind: $scheduleKind,
                        dayScope: $scheduleScope,
                        time: $scheduleTime
                    )
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.md)
                .padding(.bottom, CueInSpacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(CueInColors.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                    .foregroundStyle(CueInColors.textSecondary)
                }
                ToolbarItem(placement: .principal) {
                    Text("New")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        store.add(AntiTodoItem(title: trimmed, timeRule: composedRule))
                        onDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canAdd ? CueInColors.danger : CueInColors.textTertiary)
                    .disabled(!canAdd)
                }
            }
        }
        .cueInPreferredColorScheme()
        .onAppear {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(50))
                titleFocused = true
            }
        }
    }

    private var captureField: some View {
        HStack(alignment: .top, spacing: CueInSpacing.md) {
            ZStack {
                Circle()
                    .strokeBorder(CueInColors.danger.opacity(0.45), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
            .padding(.top, 4)

            TextField("What are you choosing not to do?", text: $title, axis: .vertical)
                .font(CueInTypography.title)
                .foregroundStyle(CueInColors.textPrimary)
                .tint(CueInColors.danger)
                .focused($titleFocused)
                .submitLabel(.done)
                .onSubmit {
                    if canAdd {
                        store.add(AntiTodoItem(title: trimmed, timeRule: composedRule))
                        onDismiss()
                        dismiss()
                    }
                }
                .lineLimit(1...4)
        }
        .padding(CueInSpacing.md)
        .background(
            CueInColors.danger.opacity(0.14),
            in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                .strokeBorder(CueInColors.danger.opacity(0.28), lineWidth: 0.5)
        }
    }
}
