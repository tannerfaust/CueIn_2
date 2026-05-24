import SwiftUI

/// Banner pinned to the top of the Tasks list whenever the integration sync
/// surfaces 3-way conflicts. Tapping presents a resolution sheet listing every
/// conflicted task with two unambiguous actions: keep the local version
/// (force-pushes CueIn → Linear/Notion) or take the remote version (pulls
/// Linear/Notion → CueIn, discarding the local edit).
///
/// Deliberately simple two-choice UX — the popular pattern in apps that sync
/// to external task managers. A field-level merge sheet (Yours / Theirs / Last
/// synced per property) is tracked as a follow-up in `SYNC_REFACTOR_TODO.md`.
struct SyncConflictBanner: View {
    @Bindable private var tasksStore = TasksStore.shared
    @State private var showingResolutionSheet = false

    var body: some View {
        Group {
            if tasksStore.hasUnresolvedConflicts {
                Button {
                    showingResolutionSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(headlineCopy)
                                .font(.subheadline.weight(.semibold))
                            Text("Tap to review and choose which version wins.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.orange.opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .sheet(isPresented: $showingResolutionSheet) {
                    SyncConflictResolutionSheet()
                }
            }
        }
    }

    private var headlineCopy: String {
        let count = tasksStore.taskConflicts.count
        if count == 1, let only = tasksStore.taskConflicts.values.first {
            switch only.source {
            case .linear:
                return "1 task changed in CueIn and Linear"
            case .notion:
                return "1 task changed in CueIn and Notion"
            }
        }
        return "\(count) tasks changed in two places"
    }
}

struct SyncConflictResolutionSheet: View {
    @Bindable private var tasksStore = TasksStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("These tasks were edited in CueIn and in the connected app since the last sync. Pick which version to keep — the other will be overwritten.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                ForEach(orderedConflicts, id: \.id) { conflict in
                    SyncConflictRow(conflict: conflict)
                }
            }
            .navigationTitle("Resolve sync conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var orderedConflicts: [TaskConflict] {
        // Most recently observed at the top so the user sees what just landed.
        Array(tasksStore.taskConflicts.values).sorted { $0.observedAt > $1.observedAt }
    }
}

private struct SyncConflictRow: View {
    let conflict: TaskConflict
    @Bindable private var tasksStore = TasksStore.shared
    @State private var resolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: sourceIcon)
                    .foregroundStyle(sourceTint)
                Text(localTitle ?? "Task")
                    .font(.headline)
                Spacer()
            }

            if let snapshotPreview {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(sourceLabel) version")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(snapshotPreview)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
            }

            HStack(spacing: 10) {
                Button {
                    Task { await resolve(keepLocal: true) }
                } label: {
                    Label("Keep mine", systemImage: "person.fill.checkmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(resolving)

                Button {
                    Task { await resolve(keepLocal: false) }
                } label: {
                    Label("Use \(sourceLabel)", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(resolving)
            }
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private var localTitle: String? {
        tasksStore.tasks.first { $0.id == conflict.cueInID }?.title
    }

    private var sourceIcon: String {
        switch conflict.source {
        case .linear: return "l.square.fill"
        case .notion: return "n.square.fill"
        }
    }

    private var sourceTint: Color {
        switch conflict.source {
        case .linear: return .indigo
        case .notion: return .black
        }
    }

    private var sourceLabel: String {
        switch conflict.source {
        case .linear: return "Linear"
        case .notion: return "Notion"
        }
    }

    private var snapshotPreview: String? {
        guard let title = conflict.remoteSnapshot["title"], !title.isEmpty else {
            return conflict.remoteSnapshot["notes"]
        }
        if let notes = conflict.remoteSnapshot["notes"], !notes.isEmpty {
            return "\(title)\n\(notes)"
        }
        return title
    }

    private func resolve(keepLocal: Bool) async {
        resolving = true
        defer { resolving = false }
        switch conflict.source {
        case .linear:
            await LinearIntegrationStore.shared.resolveConflict(taskID: conflict.cueInID, keepLocal: keepLocal)
        case .notion:
            await NotionIntegrationStore.shared.resolveConflict(taskID: conflict.cueInID, keepLocal: keepLocal)
        }
    }
}
