import SwiftUI

// MARK: - FocusTabView

/// Ambient focus audio page. Kept under the Focus feature folder because the
/// engine and preset model live here.
struct FocusTabView: View {
    /// When set (e.g. opened from Hub), shows a leading chevron that returns to Hub.
    var onRequestReturnToHub: (() -> Void)? = nil

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: CueInSpacing.xl) {
                    FocusSoundscapePanel()
                }
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Sounds")
            .cueInNavigationBarTitleDisplayMode(.large)
            .toolbar {
                if let onRequestReturnToHub {
                    ToolbarItem(placement: CueInToolbarPlacement.topBarLeading) {
                        Button(action: onRequestReturnToHub) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(CueInColors.textPrimary)
                        }
                        .accessibilityLabel("Back to Hub")
                    }
                }
            }
        }
    }
}

#Preview {
    FocusTabView()
        .cueInPreferredColorScheme()
}
