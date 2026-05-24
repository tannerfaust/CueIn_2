//
//  CueIn_2App.swift
//  CueIn_2
//
//  Created by Tanner Fause on 23.04.2026.
//

import SwiftUI
import SwiftData

@main
struct CueIn_2App: App {
    @Environment(\.scenePhase) private var scenePhase

    private let modelContainer = CueInModelContainerFactory.makeModelContainer()

    init() {
        PomodoroNotificationDelegate.shared.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if os(macOS)
                MacAppShellView()
                #else
                AppShellView()
                #endif
            }
                .cueInPreferredColorScheme()
                .modelContainer(modelContainer)
                .task {
                    CueInSyncRuntimeBridge.shared.configure(modelContext: modelContainer.mainContext)
                    await SupabaseAuthStore.shared.refreshIfNeeded()
                    if SupabaseAuthStore.shared.isSignedIn {
                        CueInSyncEngine.shared.loadCachedWorkspaceForCurrentUser()
                        await CueInSyncEngine.shared.syncNow()
                        await NotionIntegrationStore.shared.syncIfDue()
                        await LinearIntegrationStore.shared.syncIfDue()
                    }
                }
                .onOpenURL { url in
                    Task {
                        if await NotionIntegrationStore.shared.handleIncomingURL(url) {
                            return
                        }
                        if await LinearIntegrationStore.shared.handleIncomingURL(url) {
                            return
                        }
                        await SupabaseAuthStore.shared.handleIncomingURL(url)
                    }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active, SupabaseAuthStore.shared.isSignedIn else { return }
                    Task {
                        await CueInSyncEngine.shared.syncNow()
                        await NotionIntegrationStore.shared.syncIfDue()
                        await LinearIntegrationStore.shared.syncIfDue()
                    }
                }
        }
        #if os(macOS)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Sync") {
                    Task { @MainActor in
                        await CueInSyncEngine.shared.syncNow()
                    }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
        #endif
    }
}
