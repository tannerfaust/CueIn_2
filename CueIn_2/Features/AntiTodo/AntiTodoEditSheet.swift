import SwiftUI

// MARK: - AntiTodoEditSheet

struct AntiTodoEditSheet: View {
    let store: AntiTodoStore
    let item: AntiTodoItem
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftTitle: String
    @State private var scheduleEnabled: Bool
    @State private var scheduleKind: AntiTodoTimeRule.Kind
    @State private var scheduleScope: AntiTodoTimeRule.DayScope
    @State private var scheduleTime: Date
    @State private var confirmDelete = false
    @FocusState private var titleFocused: Bool

    init(store: AntiTodoStore, item: AntiTodoItem, onDismiss: @escaping () -> Void) {
        self.store = store
        self.item = item
        self.onDismiss = onDismiss
        _draftTitle = State(initialValue: item.title)
        if let rule = item.timeRule {
            _scheduleEnabled = State(initialValue: true)
            _scheduleKind = State(initialValue: rule.kind)
            _scheduleScope = State(initialValue: rule.dayScope)
            _scheduleTime = State(initialValue: AntiTodoTimeRule.dateForPicker(minuteOfDay: rule.minuteOfDay))
        } else {
            _scheduleEnabled = State(initialValue: false)
            _scheduleKind = State(initialValue: .notBefore)
            _scheduleScope = State(initialValue: .everyDay)
            _scheduleTime = State(initialValue: AntiTodoTimeRule.dateForPicker(minuteOfDay: 10 * 60))
        }
    }

    private var trimmed: String {
        draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmed.isEmpty }

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
                    titleField

                    AntiTodoScheduleControls(
                        enabled: $scheduleEnabled,
                        kind: $scheduleKind,
                        dayScope: $scheduleScope,
                        time: $scheduleTime
                    )

                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete")
                        }
                        .font(CueInTypography.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CueInSpacing.md)
                    }
                    .buttonStyle(.bordered)
                    .tint(CueInColors.danger)
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
                    Text("Edit")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        var next = item
                        next.title = trimmed
                        next.timeRule = composedRule
                        store.update(next)
                        onDismiss()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? CueInColors.danger : CueInColors.textTertiary)
                    .disabled(!canSave)
                }
            }
            .alert("Delete this item?", isPresented: $confirmDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    store.delete(id: item.id)
                    onDismiss()
                    dismiss()
                }
            } message: {
                Text("It will be removed from your Anti To‑do list.")
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

    private var titleField: some View {
        TextField("Title", text: $draftTitle, axis: .vertical)
            .font(CueInTypography.title)
            .foregroundStyle(CueInColors.textPrimary)
            .tint(CueInColors.danger)
            .focused($titleFocused)
            .padding(CueInSpacing.md)
            .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(CueInColors.danger.opacity(0.22), lineWidth: 0.5)
            }
    }
}
