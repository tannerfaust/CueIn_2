import SwiftUI

// MARK: - FocusSoundscapePickerMenu
/// Opens the full Sounds sheet (same panel as the Sounds tab). Prefer this over the legacy compact menu.

struct FocusSoundscapePickerMenu: View {
    @Bindable var store: FocusSoundscapeStore
    var accent: Color = CueInColors.accentRoutine

    @State private var showSheet = false

    var body: some View {
        FocusSoundscapeToolbarButton(store: store, accent: accent) {
            showSheet = true
        }
        .sheet(isPresented: $showSheet) {
            FocusSoundscapeSheet(accent: accent, onDismiss: { showSheet = false })
        }
    }
}
