import AuthenticationServices
import SwiftUI

// MARK: - DataAndResetSettingsView

/// Settings area for demo data, selective resets, and full local erase.
struct DataAndResetSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(CueInAppDataKeys.gimmickDemoRemoved) private var gimmickDemoRemoved = false
    @AppStorage(CueInThemePreference.storageKey) private var themeRawValue = CueInThemePreference.defaultValue.rawValue

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

    private enum SettingsRowAccessory {
        case chevron
        case action
        case checkmark
        case none
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
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(CueInColors.textPrimary)
                }
                .accessibilityLabel("Back")
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
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            settingsSummaryHeader

            CueInEditorSettingsCard(title: "Account") {
                AccountSyncSettingsView(confirmDeleteAccount: $confirmDeleteAccount)
            }

            CueInEditorSettingsCard(title: "Appearance") {
                appearanceSectionContent
            }

            CueInEditorSettingsCard(title: "Navigation") {
                navigationSectionContent
            }

            CueInEditorSettingsCard(title: "Demo data") {
                demoSectionContent
            }

            CueInEditorSettingsCard(title: "Data resets") {
                todaySectionContent
                settingsDivider
                tasksSectionContent
                settingsDivider
                goalsSectionContent
                settingsDivider
                librarySectionContent
            }

            CueInEditorSettingsCard(title: "Danger zone") {
                dangerSectionContent
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.sm)
        .padding(.bottom, CueInSpacing.xxl)
    }

    private var settingsSummaryHeader: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            Text("App settings")
                .font(CueInTypography.headline)
                .foregroundStyle(CueInColors.textPrimary)
            Text("Sync, navigation, demo content, and local reset controls.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CueInSpacing.md)
        .padding(.vertical, CueInSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                subtitle: "Delete seeded Tasks, Goals, and Today blocks",
                icon: "trash",
                role: .destructive
            ) {
                confirmRemoveDemo = true
            }

            settingsRow(
                title: "Restore demo data",
                subtitle: "Re-seed Tasks, Goals, and Today",
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
                subtitle: "Choose up to \(AppTab.maximumVisibleTabs) tabs and reorder them",
                icon: "rectangle.bottomthird.inset.filled",
                role: .normal,
                disabled: false,
                accessory: .chevron
            )
        }
        .buttonStyle(.plain)
    }

    private var appearanceSectionContent: some View {
        VStack(spacing: CueInSpacing.sm) {
            ForEach(CueInThemePreference.allCases) { theme in
                Button {
                    themeRawValue = theme.rawValue
                } label: {
                    settingsRowContent(
                        title: theme.title,
                        subtitle: theme.subtitle,
                        icon: theme.icon,
                        role: .normal,
                        disabled: false,
                        accessory: selectedTheme == theme ? .checkmark : .none
                    )
                }
                .buttonStyle(.plain)

                if theme != CueInThemePreference.allCases.last {
                    settingsDivider
                }
            }
        }
    }

    private var selectedTheme: CueInThemePreference {
        CueInThemePreference(rawValue: themeRawValue) ?? .defaultValue
    }

    private var todaySectionContent: some View {
        settingsRow(
            title: "Today schedule",
            subtitle: "Saved run, timers, formulas, and blocks",
            icon: "calendar.badge.clock",
            role: .destructive
        ) {
            confirmClearSchedule = true
        }
    }

    private var tasksSectionContent: some View {
        settingsRow(
            title: "Tasks",
            subtitle: "All fields, projects, and tasks",
            icon: "checklist",
            role: .destructive
        ) {
            confirmClearTasks = true
        }
    }

    private var goalsSectionContent: some View {
        settingsRow(
            title: "Goals",
            subtitle: "Goals, stages, subgoals, links, notes, and reviews",
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

    private var settingsDivider: some View {
        Rectangle()
            .fill(CueInColors.divider)
            .frame(height: 1)
            .padding(.leading, 46)
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
                disabled: disabled,
                accessory: .action
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
        disabled: Bool,
        accessory: SettingsRowAccessory = .action
    ) -> some View {
        HStack(spacing: CueInSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(role == .destructive ? CueInColors.danger.opacity(0.9) : CueInColors.textSecondary)
                .frame(width: 34, height: 34)
                .background(CueInColors.surfaceSecondary.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(role == .destructive ? CueInColors.danger.opacity(0.95) : CueInColors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(1)
                Text(subtitle)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            switch accessory {
            case .chevron:
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(CueInColors.textTertiary)
            case .action:
                Image(systemName: "circle.fill")
                    .font(.system(size: 6, weight: .medium))
                    .foregroundStyle(role == .destructive ? CueInColors.danger.opacity(0.7) : CueInColors.textTertiary)
            case .checkmark:
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CueInColors.accentFocus)
            case .none:
                EmptyView()
            }
        }
        .padding(.vertical, 6)
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
    @State private var confirmPassword = ""
    @State private var authMode: AccountAuthMode = .signIn
    @State private var showsBackendConfiguration = false

    private enum AccountAuthMode: String, CaseIterable, Identifiable {
        case signIn
        case create

        var id: String { rawValue }

        var title: String {
            switch self {
            case .signIn: return "Sign in"
            case .create: return "Create"
            }
        }
    }

    var body: some View {
        VStack(spacing: CueInSpacing.sm) {
            statusInset

            if showsBackendConfiguration || authStore.configurationState == .missing {
                configurationFields
            } else {
                Button {
                    showsBackendConfiguration = true
                } label: {
                    Label("Edit backend", systemImage: "server.rack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            if authStore.isSignedIn {
                signedInControls
                syncStatusView
            } else {
                signedOutControls
            }

            if let lastError = authStore.lastError {
                errorMessage(lastError)
            }

            if let notice = authStore.lastAuthNotice {
                Text(notice)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
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
                showsBackendConfiguration = false
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
            Picker("Account mode", selection: $authMode) {
                ForEach(AccountAuthMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

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

            if authMode == .create {
                SecureField("Confirm password", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: CueInSpacing.sm) {
                Button("Magic link") {
                    Task { await authStore.sendMagicLink(email: email) }
                }
                .buttonStyle(.bordered)
                .disabled(email.isEmpty)

                Button(authMode == .create ? "Create account" : "Sign in") {
                    Task {
                        if authMode == .create {
                            await authStore.signUpWithPassword(email: email, password: password)
                        } else {
                            await authStore.signInWithPassword(email: email, password: password)
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(CueInColors.accentFocus)
                .disabled(primaryAuthDisabled)
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

    private var primaryAuthDisabled: Bool {
        if email.isEmpty || password.count < 6 { return true }
        if authMode == .create && password != confirmPassword { return true }
        return false
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

    private var syncStatusView: some View {
        HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.sm) {
            Text(syncStatusText)
                .font(CueInTypography.caption)
                .foregroundStyle(syncStatusColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if case let .failed(message) = syncEngine.state {
                Button {
                    UIPasteboard.general.string = message
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(CueInColors.surfaceSecondary.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy sync error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var syncStatusText: String {
        switch syncEngine.state {
        case .idle:
            return "Sync not run yet."
        case .syncing:
            return "Syncing..."
        case let .blocked(message):
            return message
        case let .failed(message):
            return "Sync failed: \(message)"
        case let .synced(date):
            return "Synced \(date.formatted(date: .omitted, time: .shortened))."
        }
    }

    private var syncStatusColor: Color {
        switch syncEngine.state {
        case .failed:
            return Color.red.opacity(0.9)
        case .synced:
            return CueInColors.success
        default:
            return CueInColors.textSecondary
        }
    }

    private func errorMessage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(message)
                    .font(CueInTypography.caption)
                    .foregroundStyle(Color.red.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: CueInSpacing.sm)

                Button {
                    UIPasteboard.general.string = message
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CueInColors.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(CueInColors.surfaceSecondary.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - AppNavigationLayoutSettingsView

private struct AppNavigationLayoutSettingsView: View {
    @AppStorage(AppTab.storageKey) private var storedTabsRaw = AppTab.storageValue(for: AppTab.defaultTabs)
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw
        = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var editMode: EditMode = .active

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

                Section {
                    ForEach(selectedTabs) { tab in
                        selectedTabRow(tab)
                    }
                    .onMove(perform: moveTabs)
                } header: {
                    Text("Shown tabs")
                } footer: {
                    Text("Drag to reorder. Use the minus button to remove a tab. Hub stays pinned in the available set.")
                }

                if !hiddenTabs.isEmpty {
                    Section {
                        ForEach(hiddenTabs) { tab in
                            Button {
                                add(tab)
                            } label: {
                                availableTabRow(tab)
                            }
                            .buttonStyle(.plain)
                            .disabled(selectedTabs.count >= AppTab.maximumVisibleTabs)
                        }
                    } header: {
                        Text("Available")
                    } footer: {
                        if selectedTabs.count >= AppTab.maximumVisibleTabs {
                            Text("Remove a shown tab before adding another.")
                        }
                    }
                }

                Section {
                    Button {
                        selectedTabs = AppTab.defaultTabs
                    } label: {
                        HStack(spacing: CueInSpacing.md) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(CueInColors.accentFocus)
                                .frame(width: 34, height: 34)
                                .background(CueInColors.surfaceSecondary.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                            Text("Restore default tabs")
                                .font(CueInTypography.bodyMedium)
                                .foregroundStyle(CueInColors.textPrimary)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedTabs == AppTab.defaultTabs)
                }
            }
            .scrollContentBackground(.hidden)
            .environment(\.editMode, $editMode)
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
            HStack {
                Text("\(selectedTabs.count)/\(AppTab.maximumVisibleTabs) tabs")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textSecondary)

                Spacer(minLength: 0)

                Text("Preview")
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
            }

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
                    .foregroundStyle(tab == selectedTabs.first ? CueInColors.textPrimary : CueInColors.textTertiary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        Capsule()
                            .fill(tab == selectedTabs.first ? CueInColors.activeHint : Color.clear)
                    )
                }
            }
            .padding(7)
            .background(CueInColors.surfacePrimary.opacity(0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(CueInColors.cardBorder, lineWidth: 0.6))

            Text("The first tab opens by default. Timer and Sounds can be pinned here or opened from Hub.")
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

    private func selectedTabRow(_ tab: AppTab) -> some View {
        HStack(spacing: CueInSpacing.md) {
            removeTabButton(tab)

            navTabRow(tab, active: true)
        }
        .listRowBackground(CueInColors.surfacePrimary.opacity(0.92))
    }

    private func availableTabRow(_ tab: AppTab) -> some View {
        navTabRow(tab, active: false)
            .opacity(selectedTabs.count >= AppTab.maximumVisibleTabs ? 0.45 : 1)
            .listRowBackground(CueInColors.surfacePrimary.opacity(0.92))
    }

    private func removeTabButton(_ tab: AppTab) -> some View {
        Button {
            remove(tab)
        } label: {
            Image(systemName: tab.canRemoveFromNavigation && selectedTabs.count > 2 ? "minus.circle.fill" : "lock.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(
                    tab.canRemoveFromNavigation && selectedTabs.count > 2
                        ? CueInColors.danger.opacity(0.95)
                        : CueInColors.textTertiary
                )
                .frame(width: 32, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!tab.canRemoveFromNavigation || selectedTabs.count <= 2)
        .accessibilityLabel(tab.canRemoveFromNavigation ? "Remove \(tab.rearrangementPickerLabel)" : "\(tab.rearrangementPickerLabel) cannot be removed")
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
    }

    private func moveTabs(from source: IndexSet, to destination: Int) {
        var tabs = selectedTabs
        tabs.move(fromOffsets: source, toOffset: destination)
        selectedTabs = tabs
    }

    private func remove(_ tab: AppTab) {
        guard tab.canRemoveFromNavigation, selectedTabs.count > 2 else { return }
        selectedTabs.removeAll { $0 == tab }
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
    .cueInPreferredColorScheme()
}
