import SwiftUI

// MARK: - DataAndResetSettingsView

/// Settings area for demo data, selective resets, and full local erase.
struct DataAndResetSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(CueInAppDataKeys.gimmickDemoRemoved) private var gimmickDemoRemoved = false

    @State private var confirmEraseEverything = false
    @State private var confirmRemoveDemo = false
    @State private var confirmRestoreDemo = false
    @State private var confirmClearLibrary = false
    @State private var confirmClearSchedule = false
    @State private var confirmClearTasks = false

    private enum SettingsRowRole {
        case normal
        case destructive
    }

    var body: some View {
        ZStack {
            CueInColors.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                    CueInEditorSettingsCard(title: "About") {
                        Text("Manage demo content stored on this device, clear parts of your workspace, or wipe local data. Clearing custom formulas cannot be undone.")
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    CueInEditorSettingsCard(title: "Demo data") {
                        demoSectionContent
                    }

                    CueInEditorSettingsCard(title: "Library") {
                        librarySectionContent
                    }

                    CueInEditorSettingsCard(title: "Today") {
                        todaySectionContent
                    }

                    CueInEditorSettingsCard(title: "Tasks") {
                        tasksSectionContent
                    }

                    CueInEditorSettingsCard(title: "Danger zone") {
                        dangerSectionContent
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.sm)
                .padding(.bottom, CueInSpacing.xxl)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.accentFocus)
            }
        }
        .confirmationDialog(
            "Erase all local data?",
            isPresented: $confirmEraseEverything,
            titleVisibility: .visible
        ) {
            Button("Erase everything", role: .destructive) {
                CueInAppDataService.eraseAllLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes Tasks, schedules, custom formulas, block presets, and Today display preferences on this device. Demo sample data will be restored. This cannot be undone.")
        }
        .confirmationDialog(
            "Remove demo data?",
            isPresented: $confirmRemoveDemo,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                CueInAppDataService.removeGimmickDemoData()
                gimmickDemoRemoved = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Demo tasks and fields will be deleted and Today’s task-led blocks will empty. You can restore later from this screen.")
        }
        .confirmationDialog(
            "Restore demo data?",
            isPresented: $confirmRestoreDemo,
            titleVisibility: .visible
        ) {
            Button("Restore") {
                CueInAppDataService.restoreGimmickDemoData()
                gimmickDemoRemoved = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sample tasks and Today blocks will return.")
        }
        .confirmationDialog(
            "Clear saved library?",
            isPresented: $confirmClearLibrary,
            titleVisibility: .visible
        ) {
            Button("Clear library", role: .destructive) {
                CueInAppDataService.clearUserFormulaLibrary()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes your custom day formulas and saved block presets. Bundled templates in the app stay available.")
        }
        .confirmationDialog(
            "Clear schedule state?",
            isPresented: $confirmClearSchedule,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                CueInAppDataService.clearTodayScheduleState()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears the saved schedule run, formula timers, and resets Today’s blocks (mock sample day if demo is on, otherwise empty).")
        }
        .confirmationDialog(
            "Clear Tasks tab?",
            isPresented: $confirmClearTasks,
            titleVisibility: .visible
        ) {
            Button("Clear Tasks data", role: .destructive) {
                CueInAppDataService.clearTasksTabDataOnly()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes all fields, projects, and tasks in the Tasks tab. This cannot be undone.")
        }
    }

    private var demoSectionContent: some View {
        VStack(spacing: CueInSpacing.sm) {
            statusInset(
                title: gimmickDemoRemoved ? "Demo data removed" : "Demo data active",
                subtitle: gimmickDemoRemoved
                    ? "Tasks and task-led Today use empty starter content."
                    : "Sample tasks and schedules match the bundled mock day."
            )

            settingsRow(
                title: "Remove demo data",
                subtitle: "Delete seeded Tasks content and empty Today’s blocks",
                icon: "trash",
                role: .destructive
            ) {
                confirmRemoveDemo = true
            }

            settingsRow(
                title: "Restore demo data",
                subtitle: "Re-seed Tasks and Today from the bundled sample",
                icon: "arrow.counterclockwise",
                role: .normal,
                disabled: !gimmickDemoRemoved
            ) {
                confirmRestoreDemo = true
            }
        }
    }

    private var librarySectionContent: some View {
        settingsRow(
            title: "Clear saved formulas & presets",
            subtitle: "User-created schedules and block presets only — not bundled templates",
            icon: "books.vertical",
            role: .destructive
        ) {
            confirmClearLibrary = true
        }
    }

    private var todaySectionContent: some View {
        settingsRow(
            title: "Clear schedule & formula state",
            subtitle: "Persisted run, timers, and blocks for Today",
            icon: "calendar.badge.clock",
            role: .destructive
        ) {
            confirmClearSchedule = true
        }
    }

    private var tasksSectionContent: some View {
        settingsRow(
            title: "Clear Tasks tab data",
            subtitle: "All fields, projects, and tasks",
            icon: "checklist",
            role: .destructive
        ) {
            confirmClearTasks = true
        }
    }

    private var dangerSectionContent: some View {
        settingsRow(
            title: "Erase everything",
            subtitle: "Reset app data on this device to a fresh-install state",
            icon: "exclamationmark.triangle.fill",
            role: .destructive
        ) {
            confirmEraseEverything = true
        }
    }

    private func statusInset(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            Text(title)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
            Text(subtitle)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CueInSpacing.md)
        .background(CueInColors.surfaceSecondary.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        icon: String,
        role: SettingsRowRole,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(role == .destructive ? Color.red.opacity(0.9) : CueInColors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(CueInColors.surfaceSecondary.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(role == .destructive ? Color.red.opacity(0.95) : CueInColors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(subtitle)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CueInColors.textTertiary)
            }
            .padding(.vertical, CueInSpacing.sm)
            .opacity(disabled ? 0.45 : 1)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

#Preview {
    NavigationStack {
        DataAndResetSettingsView()
    }
    .preferredColorScheme(.dark)
}
