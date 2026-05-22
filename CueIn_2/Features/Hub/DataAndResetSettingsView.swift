import AuthenticationServices
import SwiftUI
#if os(iOS)
import UIKit
#endif

#if os(iOS)
private typealias CueInSettingsKeyboardType = UIKeyboardType
#else
private enum CueInSettingsKeyboardType {
    case emailAddress
    case URL
}
#endif

private extension View {
    @ViewBuilder
    func cueInSettingsKeyboardType(_ keyboardType: CueInSettingsKeyboardType) -> some View {
        #if os(iOS)
        self.keyboardType(keyboardType)
        #else
        self
        #endif
    }
}

// MARK: - DataAndResetSettingsView

/// Settings area for demo data, selective resets, and full local erase.
struct DataAndResetSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(CueInAppDataKeys.gimmickDemoRemoved) private var gimmickDemoRemoved = false
    @AppStorage(CueInAppDataKeys.hideBundledDummyTestDayTimeMap) private var hideBundledDummyTestDayTimeMap = false
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
        .cueInNavigationBarTitleDisplayMode(.inline)
        .cueInNavigationToolbarMaterial()
        .toolbar {
            ToolbarItem(placement: CueInToolbarPlacement.topBarLeading) {
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
            Text("This removes Tasks, Goals, TimeMaps, TimeMap block presets, and Today display preferences on this device. Demo sample data will be restored. This cannot be undone.")
        }
        .confirmationDialog(
            "Remove demo data?",
            isPresented: $confirmRemoveDemo,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                CueInAppDataService.removeGimmickDemoData()
                gimmickDemoRemoved = true
                hideBundledDummyTestDayTimeMap = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Demo tasks, fields, goals, bundled TimeMaps, and Today blocks will be removed. You can restore later from this screen.")
        }
        .confirmationDialog(
            "Restore demo data?",
            isPresented: $confirmRestoreDemo,
            titleVisibility: .visible
        ) {
            Button("Restore") {
                CueInAppDataService.restoreGimmickDemoData()
                gimmickDemoRemoved = false
                hideBundledDummyTestDayTimeMap = false
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sample tasks, goals, bundled TimeMaps, and Today blocks will return.")
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
            Text("Removes your saved TimeMaps and TimeMap block presets. Bundled templates in the app stay available.")
        }
        .confirmationDialog(
            "Clear TimeMap state?",
            isPresented: $confirmClearSchedule,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                CueInAppDataService.clearTodayScheduleState()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Clears the saved TimeMap run, timers, and resets Today’s time blocks (mock sample day if demo is on, otherwise empty).")
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
            Text("This permanently deletes your CueIn account and cloud data. Local cached data on this device may remain until the app clears or replaces it.")
        }
    }

    private var settingsCards: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            settingsSummaryHeader

            CueInEditorSettingsCard(title: "Account") {
                AccountExperienceSettingsView(confirmDeleteAccount: $confirmDeleteAccount)
            }

            CueInEditorSettingsCard(title: "Integrations") {
                NotionIntegrationSettingsView()
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
                    ? "Tasks, Goals, TimeMaps, and Today use empty starter content."
                    : "Sample tasks, goals, and TimeMaps match the bundled mock day."
            )

            settingsRow(
                title: "Remove demo data",
                subtitle: "Delete seeded Tasks, Goals, Today blocks, and demo TimeMaps",
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
        VStack(spacing: CueInSpacing.sm) {
            HStack(spacing: CueInSpacing.md) {
                Image(systemName: "square.dashed")
                    .font(.system(size: 16))
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(CueInColors.surfaceSecondary.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hide Test day starter scheme")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text("Removes the bundled empty-blocks sample from Library, pickers, and block lists.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(3)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: $hideBundledDummyTestDayTimeMap)
                    .labelsHidden()
                    .tint(CueInColors.accentFocus)
                    .onChange(of: hideBundledDummyTestDayTimeMap) { _, _ in
                        Task { @MainActor in
                            TodayViewModel.shared.reloadAvailableFormulasFromLibrary()
                        }
                    }
            }
            .padding(.vertical, 6)

            settingsDivider

            settingsRow(
                title: "Clear saved TimeMaps & block presets",
                subtitle: "User-created TimeMaps and TimeMap block presets only — not bundled templates",
                icon: "books.vertical",
                role: .destructive
            ) {
                confirmClearLibrary = true
            }
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
            title: "Today TimeMap",
            subtitle: "Saved run, timers, TimeMap, and time blocks",
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

// MARK: - NotionIntegrationSettingsView

private struct NotionIntegrationSettingsView: View {
    @Bindable private var authStore = SupabaseAuthStore.shared
    @Bindable private var notionStore = NotionIntegrationStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            statusPanel

            HStack(spacing: CueInSpacing.sm) {
                switch notionStore.state {
                case .connected:
                    notionButton(title: "Sync Notion", icon: "arrow.triangle.2.circlepath", isPrimary: true) {
                        Task { await notionStore.syncNow(action: .full) }
                    }
                    notionButton(title: "Disconnect", icon: "xmark.circle", isPrimary: false) {
                        Task { await notionStore.disconnect() }
                    }
                case .working:
                    notionButton(title: "Working...", icon: "hourglass", isPrimary: true, disabled: true) {}
                default:
                    notionButton(
                        title: "Connect Notion",
                        icon: "square.and.arrow.up.on.square",
                        isPrimary: true,
                        disabled: !authStore.isSignedIn
                    ) {
                        Task { await notionStore.connect() }
                    }
                }
            }

            if let result = notionStore.lastSyncResult {
                Text(syncSummary(result))
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("CueIn uses Notion OAuth and creates CueIn-managed Projects and Tasks databases in a page you grant access to. Tokens stay on the backend.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            await notionStore.refreshStatus()
        }
    }

    private var statusPanel: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            Image(systemName: statusIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 42, height: 42)
                .background(statusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text("Notion")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text(statusText)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.surfaceSecondary.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusIcon: String {
        switch notionStore.state {
        case .connected: return "checkmark.circle.fill"
        case .working: return "arrow.triangle.2.circlepath.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .disconnected: return "square.grid.2x2"
        }
    }

    private var statusColor: Color {
        switch notionStore.state {
        case .connected: return CueInColors.success
        case .working: return CueInColors.accentFocus
        case .failed: return CueInColors.danger
        case .disconnected: return CueInColors.textSecondary
        }
    }

    private var statusText: String {
        guard authStore.isSignedIn else {
            return "Sign in to CueIn Cloud before connecting Notion."
        }
        switch notionStore.state {
        case .disconnected:
            return "Notion is not connected."
        case let .connected(connection):
            let name = connection.workspaceName ?? "Notion workspace"
            if let lastSyncedAt = connection.lastSyncedAt {
                return "\(name). Last synced \(lastSyncedAt.formatted(date: .omitted, time: .shortened))."
            }
            return "\(name) connected."
        case let .working(message):
            return message
        case let .failed(message):
            return message
        }
    }

    private func syncSummary(_ result: NotionSyncResult) -> String {
        let pulled = (result.projectsPulled ?? 0) + (result.tasksPulled ?? 0)
        let pushed = (result.projectsPushed ?? 0) + (result.tasksPushed ?? 0)
        return "Last Notion sync: \(pulled) pulled, \(pushed) pushed."
    }

    private func notionButton(
        title: String,
        icon: String,
        isPrimary: Bool,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(CueInTypography.captionMedium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, CueInSpacing.sm)
                .padding(.horizontal, CueInSpacing.sm)
                .background(disabled ? CueInColors.surfaceSecondary : (isPrimary ? CueInColors.accentFocus : CueInColors.surfaceSecondary))
                .foregroundStyle(disabled ? CueInColors.textTertiary : (isPrimary ? Color.white : CueInColors.textPrimary))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - AccountExperienceSettingsView

private struct AccountExperienceSettingsView: View {
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
            case .signIn: return "Log in"
            case .create: return "Sign up"
            }
        }
    }

    private enum AccountButtonStyle {
        case primary
        case secondary
        case destructive
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            accountStatusPanel

            if authStore.isSignedIn {
                signedInPanel
            } else {
                signedOutPanel
            }

            noticeAndErrorPanel
            #if DEBUG
            backendConfigurationPanel
            #endif
        }
        .onAppear {
            #if DEBUG
            if authStore.configurationState == .missing {
                showsBackendConfiguration = true
            }
            #endif
        }
        .task {
            await authStore.validateStoredSession()
        }
    }

    private var accountStatusPanel: some View {
        HStack(alignment: .center, spacing: CueInSpacing.md) {
            Image(systemName: authStore.isSignedIn ? "person.crop.circle.badge.checkmark" : "person.crop.circle")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(authStore.isSignedIn ? CueInColors.success : CueInColors.textSecondary)
                .frame(width: 42, height: 42)
                .background(CueInColors.surfaceSecondary.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(authStore.isSignedIn ? "CueIn Cloud" : "Account")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text(statusSubtitle)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if authStore.isSignedIn {
                Image(systemName: syncStatusIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(syncStatusColor)
                    .frame(width: 28, height: 28)
                    .background(syncStatusColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.surfaceSecondary.opacity(0.62))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var statusSubtitle: String {
        if let email = authStore.session?.user.email {
            return email
        }
        switch syncEngine.state {
        case .idle:
            return "Create an account to sync across devices."
        case .syncing:
            return "Syncing..."
        case let .blocked(message), let .failed(message):
            return message
        case let .synced(date):
            return "Last synced \(date.formatted(date: .omitted, time: .shortened))"
        }
    }

    private var signedOutPanel: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            Text("Sign in or create an account")
                .font(CueInTypography.bodyMedium)
                .foregroundStyle(CueInColors.textPrimary)

            VStack(spacing: CueInSpacing.sm) {
                SignInWithAppleButton(.continue) { request in
                    authStore.makeAppleRequest(request)
                } onCompletion: { result in
                    if case let .success(authorization) = result,
                       let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                        Task { await authStore.signInWithApple(credential: credential) }
                    }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                accountButton(
                    title: "Continue with Google",
                    icon: "globe",
                    style: .secondary,
                    disabled: authStore.isWorking
                ) {
                    Task { await authStore.signInWithGoogle() }
                }
            }

            accountDivider("or use email")

            Picker("Account mode", selection: $authMode) {
                ForEach(AccountAuthMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            accountTextField("Email", text: $email, icon: "envelope", keyboardType: .emailAddress)
            accountSecureField("Password", text: $password, icon: "lock")

            if authMode == .create {
                accountSecureField("Confirm password", text: $confirmPassword, icon: "lock.rotation")
                if !confirmPassword.isEmpty && password != confirmPassword {
                    Text("Passwords do not match.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.danger)
                }
            }

            accountButton(
                title: authMode == .create ? "Create account" : "Log in",
                icon: authMode == .create ? "person.badge.plus" : "arrow.right",
                style: .primary,
                disabled: primaryAuthDisabled || authStore.isWorking
            ) {
                Task {
                    if authMode == .create {
                        await authStore.signUpWithPassword(email: email, password: password)
                    } else {
                        await authStore.signInWithPassword(email: email, password: password)
                    }
                }
            }

            Button {
                Task { await authStore.sendMagicLink(email: email) }
            } label: {
                Label("Send magic link instead", systemImage: "wand.and.stars")
                    .font(CueInTypography.caption)
                    .foregroundStyle(email.isEmpty ? CueInColors.textTertiary : CueInColors.accentFocus)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, CueInSpacing.xs)
            }
            .buttonStyle(.plain)
            .disabled(email.isEmpty || authStore.isWorking)

            if let lastMagicLinkEmail = authStore.lastMagicLinkEmail {
                Text("Magic link sent to \(lastMagicLinkEmail).")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(authStore.isWorking)
    }

    private var signedInPanel: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            accountButton(
                title: "Sync now",
                icon: "arrow.triangle.2.circlepath",
                style: .primary,
                disabled: authStore.isWorking || syncEngine.state == .syncing
            ) {
                Task { await CueInSyncRuntimeBridge.shared.migrateAndSyncCurrentWorkspace() }
            }

            syncStatusView

            accountButton(
                title: "Sign out",
                icon: "rectangle.portrait.and.arrow.right",
                style: .secondary,
                disabled: authStore.isWorking
            ) {
                Task { await authStore.signOut() }
            }

            accountDangerPanel
        }
        .disabled(authStore.isWorking)
    }

    private var primaryAuthDisabled: Bool {
        if email.isEmpty || password.count < 6 { return true }
        if authMode == .create && password != confirmPassword { return true }
        return false
    }

    private var backendConfigurationPanel: some View {
        DisclosureGroup(isExpanded: $showsBackendConfiguration) {
            configurationFields
                .padding(.top, CueInSpacing.sm)
        } label: {
            HStack(spacing: CueInSpacing.sm) {
                Image(systemName: "server.rack")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(CueInColors.textSecondary)
                Text("Developer backend")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                Spacer(minLength: 0)
                if case .ready = authStore.configurationState {
                    Text("Connected")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.success)
                }
            }
        }
        .padding(CueInSpacing.sm)
        .background(CueInColors.surfaceSecondary.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var configurationFields: some View {
        VStack(spacing: CueInSpacing.sm) {
            accountTextField("Project URL", text: $projectURL, icon: "link", keyboardType: .URL)
            accountSecureField("Publishable key", text: $anonKey, icon: "key")
            accountTextField("Redirect URL", text: $redirectURL, icon: "arrow.turn.down.right", keyboardType: .URL)

            Button {
                authStore.configure(projectURL: projectURL, anonKey: anonKey, redirectURL: redirectURL)
                showsBackendConfiguration = false
            } label: {
                Label("Save backend", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(CueInColors.accentFocus)
        }
    }

    private var noticeAndErrorPanel: some View {
        VStack(spacing: CueInSpacing.xs) {
            if let lastError = authStore.lastError {
                messageRow(
                    lastError,
                    icon: "exclamationmark.triangle.fill",
                    color: CueInColors.danger,
                    copyAccessibilityLabel: "Copy account error"
                )
            }

            if let notice = authStore.lastAuthNotice {
                messageRow(
                    notice,
                    icon: "checkmark.circle.fill",
                    color: CueInColors.success,
                    copyAccessibilityLabel: nil
                )
            }
        }
    }

    private var accountDangerPanel: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(alignment: .top, spacing: CueInSpacing.sm) {
                Image(systemName: "person.crop.circle.badge.xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(CueInColors.danger)
                    .frame(width: 28, height: 28)
                    .background(CueInColors.danger.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("Delete account")
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                    Text("Removes your account and cloud data for this user.")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            accountButton(
                title: "Delete account",
                icon: "trash",
                style: .destructive,
                disabled: authStore.isWorking
            ) {
                confirmDeleteAccount = true
            }
        }
        .padding(CueInSpacing.md)
        .background(CueInColors.danger.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CueInColors.danger.opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var syncStatusView: some View {
        HStack(alignment: .top, spacing: CueInSpacing.sm) {
            Image(systemName: syncStatusIcon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(syncStatusColor)
                .frame(width: 28, height: 28)
                .background(syncStatusColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(syncStatusText)
                .font(CueInTypography.caption)
                .foregroundStyle(syncStatusColor)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if case let .failed(message) = syncEngine.state {
                copyButton(message: message, accessibilityLabel: "Copy sync error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CueInSpacing.sm)
        .background(syncStatusColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var syncStatusIcon: String {
        switch syncEngine.state {
        case .idle:
            return "clock"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .blocked:
            return "lock.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .synced:
            return "checkmark.circle.fill"
        }
    }

    private var syncStatusText: String {
        switch syncEngine.state {
        case .idle:
            return "Sync has not run yet."
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
        case .failed, .blocked:
            return CueInColors.danger
        case .synced:
            return CueInColors.success
        case .syncing:
            return CueInColors.accentFocus
        default:
            return CueInColors.textSecondary
        }
    }

    private func accountButton(
        title: String,
        icon: String,
        style: AccountButtonStyle,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CueInSpacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(CueInTypography.bodyMedium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(buttonForeground(for: style, disabled: disabled))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(buttonBackground(for: style, disabled: disabled))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(buttonBorder(for: style, disabled: disabled), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    private func accountTextField(
        _ placeholder: String,
        text: Binding<String>,
        icon: String,
        keyboardType: CueInSettingsKeyboardType
    ) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 20)
            TextField(placeholder, text: text)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .cueInNoAutocapitalization()
                .autocorrectionDisabled()
                .cueInSettingsKeyboardType(keyboardType)
        }
        .frame(height: 46)
        .padding(.horizontal, CueInSpacing.sm)
        .background(CueInColors.surfaceSecondary.opacity(0.68))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CueInColors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func accountSecureField(_ placeholder: String, text: Binding<String>, icon: String) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 20)
            SecureField(placeholder, text: text)
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textPrimary)
                .cueInNoAutocapitalization()
                .autocorrectionDisabled()
        }
        .frame(height: 46)
        .padding(.horizontal, CueInSpacing.sm)
        .background(CueInColors.surfaceSecondary.opacity(0.68))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CueInColors.cardBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func accountDivider(_ title: String) -> some View {
        HStack(spacing: CueInSpacing.sm) {
            Rectangle()
                .fill(CueInColors.divider)
                .frame(height: 1)
            Text(title)
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .lineLimit(1)
            Rectangle()
                .fill(CueInColors.divider)
                .frame(height: 1)
        }
    }

    private func messageRow(
        _ message: String,
        icon: String,
        color: Color,
        copyAccessibilityLabel: String?
    ) -> some View {
        HStack(alignment: .top, spacing: CueInSpacing.sm) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .padding(.top, 2)

            Text(message)
                .font(CueInTypography.caption)
                .foregroundStyle(copyAccessibilityLabel == nil ? CueInColors.textSecondary : color)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            if let copyAccessibilityLabel {
                copyButton(message: message, accessibilityLabel: copyAccessibilityLabel)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CueInSpacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func copyButton(message: String, accessibilityLabel: String) -> some View {
        Button {
            CueInPasteboard.copy(message)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CueInColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(CueInColors.surfaceSecondary.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }

    private func buttonBackground(for style: AccountButtonStyle, disabled: Bool) -> Color {
        if disabled { return CueInColors.surfaceSecondary.opacity(0.42) }
        switch style {
        case .primary:
            return CueInColors.accentFocus
        case .secondary:
            return CueInColors.surfaceSecondary.opacity(0.72)
        case .destructive:
            return CueInColors.danger.opacity(0.14)
        }
    }

    private func buttonForeground(for style: AccountButtonStyle, disabled: Bool) -> Color {
        if disabled { return CueInColors.textTertiary }
        switch style {
        case .primary:
            return Color.black.opacity(0.88)
        case .secondary:
            return CueInColors.textPrimary
        case .destructive:
            return CueInColors.danger
        }
    }

    private func buttonBorder(for style: AccountButtonStyle, disabled: Bool) -> Color {
        if disabled { return CueInColors.cardBorder }
        switch style {
        case .primary:
            return CueInColors.accentFocus.opacity(0.35)
        case .secondary:
            return CueInColors.cardBorder
        case .destructive:
            return CueInColors.danger.opacity(0.28)
        }
    }
}

// MARK: - AppNavigationLayoutSettingsView

private struct AppNavigationLayoutSettingsView: View {
    @AppStorage(AppTab.storageKey) private var storedTabsRaw = AppTab.storageValue(for: AppTab.defaultTabs)
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw
        = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @Environment(\.dismiss) private var dismiss
    @State private var draftTabs: [AppTab] = AppTab.defaultTabs
    @State private var hasLoadedDraft = false
    #if os(iOS)
    @State private var editMode: EditMode = .active
    #endif

    private var taskLedPresentation: TodayDisplayPreferences.TaskLedViewMode {
        TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) ?? .timeline
    }

    private var selectedTabs: [AppTab] {
        get { AppTab.sanitize(draftTabs) }
        nonmutating set { draftTabs = AppTab.sanitize(newValue) }
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
            #if os(iOS)
            .environment(\.editMode, $editMode)
            #endif
        }
        .navigationTitle("Navbar")
        .cueInNavigationBarTitleDisplayMode(.inline)
        .cueInNavigationToolbarMaterial()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { commitAndDismiss() }
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.accentFocus)
            }
        }
        .onAppear {
            guard !hasLoadedDraft else { return }
            draftTabs = AppTab.storedTabs(from: storedTabsRaw)
            hasLoadedDraft = true
        }
        .onChange(of: taskLedViewModeRaw) { _, _ in
            CueInSyncRuntimeBridge.shared.recordAppLayoutSnapshot()
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

    private func commitAndDismiss() {
        #if os(iOS)
        editMode = .inactive
        #endif

        let nextRaw = AppTab.storageValue(for: selectedTabs)
        if storedTabsRaw != nextRaw {
            storedTabsRaw = nextRaw
            CueInSyncRuntimeBridge.shared.recordAppLayoutSnapshot()
        }

        Task { @MainActor in
            await Task.yield()
            dismiss()
        }
    }
}

#Preview {
    NavigationStack {
        DataAndResetSettingsView()
    }
    .cueInPreferredColorScheme()
}
