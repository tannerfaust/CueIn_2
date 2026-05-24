import SwiftUI

// MARK: - TasksModuleSettingsView

/// Dedicated Tasks module settings (display, integrations, Notion list behavior).
struct TasksModuleSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(TasksModulePreferences.showNotionInCueInListsKey)
    private var showNotionInCueInLists = true
    @AppStorage(TasksModulePreferences.showLinearInCueInListsKey)
    private var showLinearInCueInLists = true
    @AppStorage(TasksTaskDisplayPrefs.densityKey) private var densityRaw = TasksDisplayDensity.compact.rawValue
    @AppStorage(TasksTaskDisplayPrefs.metadataKey) private var metadataRaw = TasksMetadataLevel.balanced.rawValue
    @AppStorage(TasksTaskDisplayPrefs.showProjectKey) private var showProject = true
    @AppStorage(TasksTaskDisplayPrefs.showDueKey) private var showDue = true
    @AppStorage(TasksTaskDisplayPrefs.showEstimateKey) private var showEstimate = true
    @AppStorage(TasksTaskDisplayPrefs.showPriorityKey) private var showPriority = true

    var body: some View {
        NavigationStack {
            ZStack {
                CueInColors.background.ignoresSafeArea()

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: CueInSpacing.md) {
                        CueInEditorSettingsCard(title: "Integrations") {
                            NotionIntegrationSettingsSection()
                            Divider().opacity(0.5).padding(.vertical, CueInSpacing.xs)
                            LinearIntegrationSettingsSection()
                        }

                        CueInEditorSettingsCard(title: "Notion in CueIn lists") {
                            notionListSection
                        }

                        CueInEditorSettingsCard(title: "Linear in CueIn lists") {
                            linearListSection
                        }

                        CueInEditorSettingsCard(title: "Task display") {
                            displaySection
                        }
                    }
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
                    .padding(.vertical, CueInSpacing.md)
                    .padding(.bottom, CueInLayout.scrollBottomInset)
                }
            }
            .navigationTitle("Tasks settings")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .cueInNavigationToolbarMaterial()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(CueInColors.textPrimary)
                }
            }
        }
    }

    private var notionListSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Toggle(isOn: $showNotionInCueInLists) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show Notion tasks in CueIn lists")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Text("Includes Tasks, To-do, Inbox, Upcoming, and All.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }
            .tint(CueInColors.accentFocus)

            if !showNotionInCueInLists {
                Label("Notion tasks stay under the Notion section in the sidebar.", systemImage: "info.circle")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var linearListSection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Toggle(isOn: $showLinearInCueInLists) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Show Linear tasks in CueIn lists")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Text("Includes Tasks, To-do, Inbox, Upcoming, and All.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }
            .tint(CueInColors.accentFocus)

            if !showLinearInCueInLists {
                Label("Linear tasks stay under the Linear section in the sidebar.", systemImage: "info.circle")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private var displaySection: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Picker("Density", selection: $densityRaw) {
                ForEach(TasksDisplayDensity.allCases) { density in
                    Text(density.label).tag(density.rawValue)
                }
            }

            Picker("Information", selection: $metadataRaw) {
                ForEach(TasksMetadataLevel.allCases) { level in
                    Text(level.label).tag(level.rawValue)
                }
            }

            Divider().opacity(0.5)

            Toggle("Show project", isOn: $showProject)
            Toggle("Show dates", isOn: $showDue)
            Toggle("Show estimate", isOn: $showEstimate)
            Toggle("Show priority", isOn: $showPriority)
        }
    }
}

#Preview {
    TasksModuleSettingsView()
        .cueInPreferredColorScheme()
}
