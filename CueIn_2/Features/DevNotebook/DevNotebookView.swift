import SwiftUI

// MARK: - DevNotebookView

struct DevNotebookView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("cuein.devNotebook.showCaptureButton") private var showCaptureButton = false
    @Bindable private var store = DevNotebookStore.shared
    @State private var filter: DevNotebookFilter = .all
    @State private var showCompose = false
    @State private var showClearConfirm = false
    @State private var showShareSheet = false
    @State private var shareURL: URL?
    @State private var showExportEmptyAlert = false

    var body: some View {
        List {
            Section {
                Toggle("Show capture button", isOn: $showCaptureButton)
                    .tint(CueInColors.accentFixed)

                Picker("Filter", selection: $filter) {
                    Text("All").tag(DevNotebookFilter.all)
                    ForEach(DevNotebookEntryKind.allCases) { kind in
                        Text(kind.title).tag(DevNotebookFilter.kind(kind))
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                if displayedEntries.isEmpty {
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "note.text",
                        description: Text("Use the capture button or New note to add ideas and bugs.")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(displayedEntries) { entry in
                        DevNotebookRow(entry: entry)
                            .listRowInsets(EdgeInsets(
                                top: CueInSpacing.sm,
                                leading: CueInSpacing.screenHorizontal,
                                bottom: CueInSpacing.sm,
                                trailing: CueInSpacing.screenHorizontal
                            ))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    store.delete(id: entry.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(CueInColors.background)
        .navigationTitle("Dev notebook")
        .navigationBarTitleDisplayMode(.inline)
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
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section("All notes") {
                        Button("Markdown (.md)", systemImage: "doc.richtext") {
                            startExport(useFilterOnly: false, format: .markdown)
                        }
                        Button("CSV (.csv)", systemImage: "tablecells") {
                            startExport(useFilterOnly: false, format: .csv)
                        }
                    }
                    if filter != .all {
                        Section("Current filter (\(filter.exportMenuShortTitle))") {
                            Button("Markdown (.md)", systemImage: "doc.richtext") {
                                startExport(useFilterOnly: true, format: .markdown)
                            }
                            Button("CSV (.csv)", systemImage: "tablecells") {
                                startExport(useFilterOnly: true, format: .csv)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .medium))
                }
                .disabled(store.entries.isEmpty)
                .accessibilityLabel("Export notebook")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("New note", systemImage: "square.and.pencil") {
                        showCompose = true
                    }
                    Button("Clear all…", systemImage: "trash", role: .destructive) {
                        showClearConfirm = true
                    }
                    .disabled(store.entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 17, weight: .medium))
                }
            }
        }
        .sheet(isPresented: $showCompose) {
            DevNotebookCaptureSheet(isPresented: $showCompose, defaultKind: .moduleIdea) { kind, body in
                let snap = DevNotebookContext.shared.makeSnapshot()
                store.add(DevNotebookEntry(
                    kind: kind,
                    body: body,
                    moduleLabel: snap.moduleLabel,
                    contextLine: snap.contextLine
                ))
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
        .confirmationDialog("Delete all dev notes?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear all", role: .destructive) {
                store.clearAll()
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showShareSheet, onDismiss: cleanupShareFile) {
            if let shareURL {
                DevNotebookActivityView(activityItems: [shareURL])
                    .presentationDetents([.medium, .large])
            }
        }
        .alert("Nothing to export", isPresented: $showExportEmptyAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("There are no notes in this scope. Add notes or choose another filter.")
        }
    }

    private var displayedEntries: [DevNotebookEntry] {
        store.entries(filter: filter)
    }

    private func startExport(useFilterOnly: Bool, format: DevNotebookExportFormat) {
        let list: [DevNotebookEntry] = useFilterOnly ? displayedEntries : store.entries
        guard !list.isEmpty else {
            showExportEmptyAlert = true
            return
        }
        let scopeLabel: String
        let slug: String
        if useFilterOnly {
            scopeLabel = filter.exportDocumentTitle
            slug = filter.exportSlugLabel
        } else {
            scopeLabel = "All notes"
            slug = "all-notes"
        }
        do {
            shareURL = try DevNotebookExporter.writeTempFile(
                entries: list,
                format: format,
                fileNameSlug: slug,
                documentScopeTitle: scopeLabel
            )
            showShareSheet = true
        } catch {
            shareURL = nil
        }
    }

    private func cleanupShareFile() {
        if let url = shareURL {
            try? FileManager.default.removeItem(at: url)
        }
        shareURL = nil
    }
}

// MARK: - Filter export labels

private extension DevNotebookFilter {
    var exportMenuShortTitle: String {
        switch self {
        case .all: return "All"
        case .kind(let k): return k.title
        }
    }

    /// Slug for exported filename (e.g. `bug`, `all-notes`).
    var exportSlugLabel: String {
        switch self {
        case .all: return "all-notes"
        case .kind(let k): return k.rawValue
        }
    }

    /// Readable scope line inside Markdown exports.
    var exportDocumentTitle: String {
        switch self {
        case .all: return "All notes"
        case .kind(let k): return k.title
        }
    }
}

// MARK: - Row

private struct DevNotebookRow: View {
    let entry: DevNotebookEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        CueInCard(padding: CueInSpacing.md) {
            VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.sm) {
                    Image(systemName: entry.kind.systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(entry.kind.accent)

                    Text(entry.kind.title)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textSecondary)

                    Spacer(minLength: 0)

                    Text(Self.timeFormatter.string(from: entry.createdAt))
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                        .monospacedDigit()
                }

                Text(entry.listTitle)
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: CueInSpacing.sm) {
                    Text(entry.moduleLabel)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(CueInColors.surfaceTertiary, in: Capsule(style: .continuous))

                    Spacer(minLength: 0)
                }

                Text(entry.contextLine)
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    NavigationStack {
        DevNotebookView()
    }
    .cueInPreferredColorScheme()
}
