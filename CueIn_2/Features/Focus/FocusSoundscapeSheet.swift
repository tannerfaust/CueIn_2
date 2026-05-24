import SwiftUI

// MARK: - FocusSoundscapeSheet

/// Sliding sheet with the same Sounds experience as the dedicated Focus tab.
struct FocusSoundscapeSheet: View {
    var accent: Color = CueInColors.accentRoutine
    /// When true, starting playback from the sheet dismisses back to focus mode.
    var dismissWhenPlaybackStarts: Bool = true
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                FocusSoundscapePanel(
                    accent: accent,
                    playAndDismissOnSelection: dismissWhenPlaybackStarts,
                    onRequestDismiss: dismissSheet
                )
                    .padding(.vertical, CueInSpacing.lg)
                    .padding(.bottom, CueInSpacing.md)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Sounds")
            .cueInNavigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismissSheet()
                    }
                    .foregroundStyle(CueInColors.textPrimary)
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
    }

    private func dismissSheet() {
        onDismiss()
        dismiss()
    }
}
