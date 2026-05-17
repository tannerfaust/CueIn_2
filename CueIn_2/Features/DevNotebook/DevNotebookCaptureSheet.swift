import SwiftUI

// MARK: - DevNotebookCaptureSheet

struct DevNotebookCaptureSheet: View {
    @Binding var isPresented: Bool
    var defaultKind: DevNotebookEntryKind = .moduleIdea
    var onSave: (DevNotebookEntryKind, String) -> Void

    @AppStorage("cuein.devNotebook.lastEntryKind") private var lastKindRaw = DevNotebookEntryKind.moduleIdea.rawValue
    @State private var selectedKind: DevNotebookEntryKind = .moduleIdea
    @State private var bodyText = ""
    @FocusState private var editorFocused: Bool

    private var snapshot: (moduleLabel: String, contextLine: String) {
        DevNotebookContext.shared.makeSnapshot()
    }

    private var trimmedBody: String {
        bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool { !trimmedBody.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                CueInColors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                        kindPicker

                        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                            Text("Will save with")
                                .font(CueInTypography.captionMedium)
                                .foregroundStyle(CueInColors.textTertiary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(snapshot.moduleLabel)
                                    .font(CueInTypography.bodyMedium)
                                    .foregroundStyle(CueInColors.textPrimary)
                                Text(snapshot.contextLine)
                                    .font(CueInTypography.caption)
                                    .foregroundStyle(CueInColors.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(CueInSpacing.md)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                        }

                        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
                            Text("Note")
                                .font(CueInTypography.captionMedium)
                                .foregroundStyle(CueInColors.textTertiary)

                            TextEditor(text: $bodyText)
                                .scrollContentBackground(.hidden)
                                .font(CueInTypography.body)
                                .foregroundStyle(CueInColors.textPrimary)
                                .padding(CueInSpacing.md)
                                .frame(minHeight: 160)
                                .background(CueInColors.surfaceSecondary, in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                                .focused($editorFocused)
                        }
                    }
                    .padding(.horizontal, CueInSpacing.screenHorizontal)
                    .padding(.top, CueInSpacing.md)
                    .padding(.bottom, CueInSpacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Dev note")
            .cueInNavigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        persistKind()
                        onSave(selectedKind, trimmedBody)
                        isPresented = false
                    }
                    .disabled(!canSave)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            if let parsed = DevNotebookEntryKind(rawValue: lastKindRaw) {
                selectedKind = parsed
            } else {
                selectedKind = defaultKind
            }
            editorFocused = true
        }
    }

    private var kindPicker: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Text("Type")
                .font(CueInTypography.captionMedium)
                .foregroundStyle(CueInColors.textTertiary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CueInSpacing.sm) {
                    ForEach(DevNotebookEntryKind.allCases) { kind in
                        kindChip(kind)
                    }
                }
            }
        }
    }

    private func kindChip(_ kind: DevNotebookEntryKind) -> some View {
        let selected = selectedKind == kind
        return Button {
            selectedKind = kind
            persistKind()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                Text(kind.title)
                    .font(CueInTypography.captionMedium)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, CueInSpacing.md)
            .padding(.vertical, CueInSpacing.sm)
            .background(
                selected ? kind.accent.opacity(0.28) : CueInColors.surfaceSecondary,
                in: RoundedRectangle(cornerRadius: CueInSpacing.chipRadius + 4, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CueInSpacing.chipRadius + 4, style: .continuous)
                    .stroke(selected ? kind.accent.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 1)
            )
            .foregroundStyle(selected ? Color.white : CueInColors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func persistKind() {
        lastKindRaw = selectedKind.rawValue
    }
}

#Preview {
    DevNotebookCaptureSheet(isPresented: .constant(true)) { _, _ in }
        .cueInPreferredColorScheme()
}
