import AuthenticationServices
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
    @State private var confirmClearGoals = false
    @State private var confirmDeleteAccount = false

    private enum SettingsRowRole {
        case normal
        case destructive
    }

    var body: some View {
        ZStack {
            CueInColors.background.ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                settingsCards
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
            Text("This removes Tasks, Goals, schedules, custom formulas, block presets, and Today display preferences on this device. Demo sample data will be restored. This cannot be undone.")
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
            Text("Demo tasks, fields, goals, and Today’s task-led blocks will be deleted. You can restore later from this screen.")
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
            Text("Sample tasks, goals, and Today blocks will return.")
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
        .confirmationDialog(
            "Clear Goals data?",
            isPresented: $confirmClearGoals,
            titleVisibility: .visible
        ) {
            Button("Clear Goals data", role: .destructive) {
                CueInAppDataService.clearGoalsDataOnly()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Removes all goals, stages, subgoals, strategy canvas notes, links, and reviews. This cannot be undone.")
        }
        .confirmationDialog(
            "Delete CueIn account?",
            isPresented: $confirmDeleteAccount,
            titleVisibility: .visible
        ) {
            Button("Delete account", role: .destructive) {
                Task { await SupabaseAuthStore.shared.deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This signs you out and marks your CueIn profile for deletion.")
        }
    }

    private var settingsCards: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.lg) {
            CueInEditorSettingsCard(title: "About") {
                Text("Manage local data, account sync, demo content, and workspace resets.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            CueInEditorSettingsCard(title: "Account") {
                AccountSyncSettingsView(confirmDeleteAccount: $confirmDeleteAccount)
            }

            CueInEditorSettingsCard(title: "Demo data") {
                demoSectionContent
            }

            CueInEditorSettingsCard(title: "Navigation") {
                navigationSectionContent
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

            CueInEditorSettingsCard(title: "Goals") {
                goalsSectionContent
            }

            CueInEditorSettingsCard(title: "Danger zone") {
                dangerSectionContent
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.sm)
        .padding(.bottom, CueInSpacing.xxl)
    }

    private var demoSectionContent: some View {
        VStack(spacing: CueInSpacing.sm) {
            statusInset(
                title: gimmickDemoRemoved ? "Demo data removed" : "Demo data active",
                subtitle: gimmickDemoRemoved
                    ? "Tasks, Goals, and task-led Today use empty starter content."
                    : "Sample tasks, goals, and schedules match the bundled mock day."
            )

            settingsRow(
                title: "Remove demo data",
                subtitle: "Delete seeded Tasks, Goals, and empty Today’s blocks",
                icon: "trash",
                role: .destructive
            ) {
                confirmRemoveDemo = true
            }

            settingsRow(
                title: "Restore demo data",
                subtitle: "Re-seed Tasks, Goals, and Today from the bundled sample",
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

    private var navigationSectionContent: some View {
        NavigationLink {
            AppNavigationLayoutSettingsView()
        } label: {
            settingsRowContent(
                title: "Navbar layout",
                subtitle: "Reorder pages, add pages, or hide tabs",
                icon: "rectangle.bottomthird.inset.filled",
                role: .normal,
                disabled: false
            )
        }
        .buttonStyle(.plain)
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

    private var goalsSectionContent: some View {
        settingsRow(
            title: "Clear Goals data",
            subtitle: "All goals, stages, subgoals, links, canvas notes, and reviews",
            icon: "target",
            role: .destructive
        ) {
            confirmClearGoals = true
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
            settingsRowContent(
                title: title,
                subtitle: subtitle,
                icon: icon,
                role: role,
                disabled: disabled
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func settingsRowContent(
        title: String,
        subtitle: String,
        icon: String,
        role: SettingsRowRole,
        disabled: Bool
    ) -> some View {
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
}

// MARK: - AccountSyncSettingsView

private struct AccountSyncSettingsView: View {
    @Binding var confirmDeleteAccount: Bool
    @Bindable private var authStore = SupabaseAuthStore.shared
    @Bindable private var syncEngine = CueInSyncEngine.shared

    @State private var projectURL = UserDefaults.standard.string(forKey: SupabaseConfiguration.urlDefaultsKey) ?? ""
    @State private var anonKey = UserDefaults.standard.string(forKey: SupabaseConfiguration.anonKeyDefaultsKey) ?? ""
    @State private var redirectURL = UserDefaults.standard.string(forKey: SupabaseConfiguration.redirectURLDefaultsKey) ?? "cuein://auth/callback"
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(spacing: CueInSpacing.sm) {
            statusInset

            if case .missing = authStore.configurationState {
                configurationFields
            }

            if authStore.isSignedIn {
                signedInControls
            } else {
                signedOutControls
            }

            if let lastError = authStore.lastError {
                Text(lastError)
                    .font(CueInTypography.caption)
                    .foregroundStyle(Color.red.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var statusInset: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            Text(authStore.isSignedIn ? "Signed in" : "Not signed in")
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)
            Text(statusSubtitle)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CueInSpacing.md)
        .background(CueInColors.surfaceSecondary.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var statusSubtitle: String {
        if let email = authStore.session?.user.email {
            return email
        }
        switch syncEngine.state {
        case .idle:
            return "Connect Supabase to enable account sync."
        case .syncing:
            return "Syncing..."
        case let .blocked(message), let .failed(message):
            return message
        case let .synced(date):
            return "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    private var configurationFields: some View {
        VStack(spacing: CueInSpacing.sm) {
            TextField("Supabase project URL", text: $projectURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            SecureField("Anon key", text: $anonKey)
            TextField("Redirect URL", text: $redirectURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button {
                authStore.configure(projectURL: projectURL, anonKey: anonKey, redirectURL: redirectURL)
            } label: {
                Label("Save backend", systemImage: "server.rack")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CueInColors.accentFocus)
        }
        .textFieldStyle(.roundedBorder)
    }

    private var signedOutControls: some View {
        VStack(spacing: CueInSpacing.sm) {
            SignInWithAppleButton(.signIn) { request in
                authStore.makeAppleRequest(request)
            } onCompletion: { result in
                if case let .success(authorization) = result,
                   let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                    Task { await authStore.signInWithApple(credential: credential) }
                }
            }
            .signInWithAppleButtonStyle(.white)
            .frame(height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Button {
                Task { await authStore.signInWithGoogle() }
            } label: {
                Label("Continue with Google", systemImage: "globe")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            TextField("Email", text: $email)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.emailAddress)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            HStack(spacing: CueInSpacing.sm) {
                Button("Magic link") {
                    Task { await authStore.sendMagicLink(email: email) }
                }
                .buttonStyle(.bordered)
                .disabled(email.isEmpty)

                Button("Sign in") {
                    Task { await authStore.signInWithPassword(email: email, password: password) }
                }
                .buttonStyle(.borderedProminent)
                .tint(CueInColors.accentFocus)
                .disabled(email.isEmpty || password.isEmpty)
            }

            if let lastMagicLinkEmail = authStore.lastMagicLinkEmail {
                Text("Magic link sent to \(lastMagicLinkEmail).")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(authStore.isWorking)
    }

    private var signedInControls: some View {
        VStack(spacing: CueInSpacing.sm) {
            Button {
                Task { await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace() }
            } label: {
                Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CueInColors.accentFocus)

            HStack(spacing: CueInSpacing.sm) {
                Button("Sign out") {
                    Task { await authStore.signOut() }
                }
                .buttonStyle(.bordered)

                Button("Delete account", role: .destructive) {
                    confirmDeleteAccount = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .disabled(authStore.isWorking)
    }
}

// MARK: - AppNavigationLayoutSettingsView

private struct AppNavigationLayoutSettingsView: View {
    @AppStorage(AppTab.storageKey) private var storedTabsRaw = AppTab.storageValue(for: AppTab.defaultTabs)
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw
        = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @Environment(\.dismiss) private var dismiss

    private var taskLedPresentation: TodayDisplayPreferences.TaskLedViewMode {
        TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
    }

    private var selectedTabs: [AppTab] {
        get { AppTab.storedTabs(from: storedTabsRaw) }
        nonmutating set { storedTabsRaw = AppTab.storageValue(for: newValue) }
    }

    private var hiddenTabs: [AppTab] {
        AppTab.editableTabs.filter { !selectedTabs.contains($0) }
    }

    var body: some View {
        ZStack {
            CueInColors.background.ignoresSafeArea()

            List {
                Section {
                    navbarPreview
                        .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("Pages") {
                    ForEach(selectedTabs) { tab in
                        navTabRow(tab, active: true)
                            .deleteDisabled(!tab.canRemoveFromNavigation || selectedTabs.count <= 2)
                    }
                    .onMove(perform: moveTabs)
                    .onDelete(perform: deleteTabs)
                }

                if !hiddenTabs.isEmpty {
                    Section("Add") {
                        ForEach(hiddenTabs) { tab in
                            Button {
                                add(tab)
                            } label: {
                                navTabRow(tab, active: false)
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedTabs.count >= AppTab.maximumVisibleTabs)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .navigationTitle("Navbar")
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
        .onAppear {
            storedTabsRaw = AppTab.storageValue(for: selectedTabs)
        }
    }

    private var navbarPreview: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(spacing: 6) {
                ForEach(selectedTabs) { tab in
                    VStack(spacing: 4) {
                        Image(systemName: navbarPreviewSymbol(for: tab))
                            .font(.system(size: 17, weight: .semibold))
                        Text(navbarPreviewTitle(for: tab))
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .foregroundStyle(Color.white.opacity(tab == selectedTabs.first ? 1 : 0.48))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule()
                            .fill(tab == selectedTabs.first ? Color.white.opacity(0.14) : Color.clear)
                    )
                }
            }
            .padding(7)
            .background(Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.6))

            Text("Up to \(AppTab.maximumVisibleTabs) tabs. Hub stays. Algorithm and To-do/Timeline are separate pages.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
        }
    }

    private func navbarPreviewSymbol(for tab: AppTab) -> String {
        if tab == .taskLed {
            return taskLedPresentation.icon
        }
        return tab.icon
    }

    private func navbarPreviewTitle(for tab: AppTab) -> String {
        if tab == .taskLed {
            return taskLedPresentation.title
        }
        return tab.label
    }

    private func navTabRowSymbol(for tab: AppTab, active: Bool) -> String {
        if tab == .taskLed {
            return taskLedPresentation.icon
        }
        return active ? tab.icon : tab.iconInactive
    }

    private func navTabRow(_ tab: AppTab, active: Bool) -> some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: navTabRowSymbol(for: tab, active: active))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(active ? CueInColors.textPrimary : CueInColors.textTertiary)
                .frame(width: 34, height: 34)
                .background(CueInColors.surfaceSecondary.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(tab.rearrangementPickerLabel)
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(active ? CueInColors.textPrimary : CueInColors.textSecondary)

            Spacer(minLength: 0)

            if tab == .hub {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
            } else if !active {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        selectedTabs.count >= AppTab.maximumVisibleTabs
                            ? CueInColors.textTertiary.opacity(0.45)
                            : CueInColors.accentFocus
                    )
            }
        }
        .listRowBackground(CueInColors.surfacePrimary.opacity(0.92))
    }

    private func moveTabs(from source: IndexSet, to destination: Int) {
        var tabs = selectedTabs
        tabs.move(fromOffsets: source, toOffset: destination)
        selectedTabs = tabs
    }

    private func deleteTabs(at offsets: IndexSet) {
        var tabs = selectedTabs
        for index in offsets.sorted(by: >) {
            guard tabs.indices.contains(index),
                  tabs[index].canRemoveFromNavigation,
                  tabs.count > 2 else { continue }
            tabs.remove(at: index)
        }
        selectedTabs = tabs
    }

    private func add(_ tab: AppTab) {
        guard selectedTabs.count < AppTab.maximumVisibleTabs else { return }
        selectedTabs = selectedTabs + [tab]
    }
}

#Preview {
    NavigationStack {
        DataAndResetSettingsView()
    }
    .preferredColorScheme(.dark)
}
