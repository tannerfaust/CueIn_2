import SwiftUI

#if os(macOS)
import AppKit

struct MacAppShellView: View {
    private enum Destination: String, CaseIterable, Identifiable {
        case schedule
        case timeline
        case tasks
        case projects
        case goals
        case stats
        case hub

        var id: String { rawValue }

        var title: String {
            switch self {
            case .schedule: return "Schedule"
            case .timeline: return "To-do / Timeline"
            case .tasks: return "Tasks"
            case .projects: return "Projects"
            case .goals: return "Goals"
            case .stats: return "Stats"
            case .hub: return "Hub"
            }
        }

        var sidebarTitle: String {
            switch self {
            case .timeline: return "To-do"
            default: return title
            }
        }

        var systemImage: String {
            switch self {
            case .schedule: return "rectangle.split.3x1"
            case .timeline: return "calendar.day.timeline.left"
            case .tasks: return "checkmark.circle"
            case .projects: return "folder"
            case .goals: return "target"
            case .stats: return "chart.bar"
            case .hub: return "square.grid.2x2"
            }
        }
    }

    @AppStorage("cuein.mac.sidebar.selection") private var storedSelection = Destination.timeline.rawValue
    @AppStorage(DayEngineMode.storageKey) private var todayModeRawValue = DayEngineMode.taskLed.rawValue
    @AppStorage(TodayDisplayPreferences.taskLedViewMode) private var taskLedViewModeRaw
        = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
    @State private var selection: Destination = .timeline
    @State private var showingQuickCapture = false
    @State private var showingSettings = false
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @Bindable private var syncEngine = CueInSyncEngine.shared
    @Bindable private var authStore = SupabaseAuthStore.shared

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            MacDetailContainer(title: selection.title) {
                destinationView(for: selection)
            }
        }
        .background(CueInColors.background)
        .cueInPreferredColorScheme()
        .frame(minWidth: 1020, minHeight: 680)
        .onAppear {
            selection = Destination(rawValue: storedSelection) ?? .timeline
            applyDestinationMode(selection)
        }
        .onChange(of: selection) { _, newValue in
            storedSelection = newValue.rawValue
            applyDestinationMode(newValue)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showingQuickCapture = true
                } label: {
                    Label("New Task", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)

                Button {
                    Task { await syncEngine.syncNow() }
                } label: {
                    Label(syncTitle, systemImage: syncIcon)
                }
                .keyboardShortcut("r", modifiers: .command)

                Menu {
                    if authStore.isSignedIn {
                        Button("Sync Now") {
                            Task { await syncEngine.syncNow() }
                        }
                        Button("Sign Out") {
                            Task { await authStore.signOut() }
                        }
                    } else {
                        Button("Open Account Settings") {
                            showingSettings = true
                        }
                    }
                    Divider()
                    Button("Settings...") {
                        showingSettings = true
                    }
                    .keyboardShortcut(",", modifiers: .command)
                } label: {
                    Label(accountTitle, systemImage: authStore.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                }
            }
        }
        .sheet(isPresented: $showingQuickCapture) {
            QuickCaptureSheet(
                onDismiss: { showingQuickCapture = false },
                onExpand: { _ in showingQuickCapture = false }
            )
            .frame(minWidth: 520, minHeight: 520)
        }
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                DataAndResetSettingsView()
                    .frame(minWidth: 640, minHeight: 680)
            }
            .cueInPreferredColorScheme()
        }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Section("Plan") {
                sidebarRow(.schedule)
                sidebarRow(.timeline)
            }
            Section("Work") {
                sidebarRow(.tasks)
                sidebarRow(.projects)
                sidebarRow(.goals)
            }
            Section("Review") {
                sidebarRow(.stats)
            }
            Section("System") {
                sidebarRow(.hub)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .safeAreaInset(edge: .top, spacing: 0) {
            MacSidebarHeader()
        }
    }

    private func sidebarRow(_ destination: Destination) -> some View {
        Label(destination.sidebarTitle, systemImage: destination.systemImage)
            .tag(destination)
            .help(destination.title)
    }

    @ViewBuilder
    private func destinationView(for destination: Destination) -> some View {
        switch destination {
        case .schedule:
            TodayView()
        case .timeline:
            TodayView()
        case .tasks:
            TasksView()
        case .projects:
            ProjectsTabView()
        case .goals:
            GoalsTabView()
        case .stats:
            StatsView()
        case .hub:
            HubView()
        }
    }

    private func applyDestinationMode(_ destination: Destination) {
        switch destination {
        case .schedule:
            todayModeRawValue = DayEngineMode.formulaBased.rawValue
        case .timeline:
            todayModeRawValue = DayEngineMode.taskLed.rawValue
            if TodayDisplayPreferences.TaskLedViewMode(rawValue: taskLedViewModeRaw) == nil {
                taskLedViewModeRaw = TodayDisplayPreferences.TaskLedViewMode.timeline.rawValue
            }
        default:
            break
        }
    }

    private var accountTitle: String {
        authStore.isSignedIn ? "Account" : "Sign In"
    }

    private var syncTitle: String {
        switch syncEngine.state {
        case .idle: return "Sync"
        case .syncing: return "Syncing"
        case .blocked: return "Sync Blocked"
        case .failed: return "Sync Failed"
        case .synced: return "Synced"
        }
    }

    private var syncIcon: String {
        switch syncEngine.state {
        case .idle: return "arrow.triangle.2.circlepath"
        case .syncing: return "arrow.triangle.2.circlepath.circle"
        case .blocked: return "lock.circle"
        case .failed: return "exclamationmark.triangle"
        case .synced: return "checkmark.circle"
        }
    }
}
#endif

private struct MacSidebarHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "circle.grid.cross.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(CueInColors.accentFocus)
                VStack(alignment: .leading, spacing: 1) {
                    Text("CueIn")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(CueInColors.textPrimary)
                    Text("Plan, execute, review")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(CueInColors.textTertiary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MacDetailContainer<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            CueInColors.background.ignoresSafeArea()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(title)
        #if os(macOS)
        .navigationSubtitle("Synced workspace")
        #endif
    }
}
