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
    private let modelContainer = CueInModelContainerFactory.makeModelContainer()

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .preferredColorScheme(.dark)
                .modelContainer(modelContainer)
                .task {
                    CueInSyncRuntimeBridge.shared.configure(modelContext: modelContainer.mainContext)
                    await SupabaseAuthStore.shared.refreshIfNeeded()
                }
        }
    }
}
