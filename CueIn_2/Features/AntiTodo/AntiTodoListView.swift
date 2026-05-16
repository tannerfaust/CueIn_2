import SwiftUI

// MARK: - AntiTodoListView

struct AntiTodoListView: View {
    @Bindable private var store = AntiTodoStore.shared
    @State private var editingItem: AntiTodoItem?

    var body: some View {
        NavigationStack {
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: CueInSpacing.md) {
                    header

                    if store.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(store.items) { item in
                            AntiTodoRowView(item: item) {
                                editingItem = item
                            }
                        }
                    }
                }
                .padding(.horizontal, CueInSpacing.screenHorizontal)
                .padding(.top, CueInSpacing.sm)
                .padding(.bottom, CueInLayout.scrollBottomInset)
            }
            .background(CueInColors.background.ignoresSafeArea())
            .navigationTitle("Anti To‑do")
            .navigationBarTitleDisplayMode(.large)
        }
        .cueInPreferredColorScheme()
        .sheet(item: $editingItem) { item in
            AntiTodoEditSheet(store: store, item: item, onDismiss: { editingItem = nil })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(CueInSheetPresentation.cornerRadius)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.xs) {
            Text("Name what you are choosing not to do. Optionally add a time window when it matters most.")
                .font(CueInTypography.body)
                .foregroundStyle(CueInColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, CueInSpacing.xs)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            Image(systemName: "slash.circle")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(CueInColors.textTertiary)

            Text("Nothing here yet")
                .font(CueInTypography.headline)
                .foregroundStyle(CueInColors.textPrimary)

            Text("Tap + to add a trap, habit, or impulse you want to steer away from.")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CueInSpacing.lg)
        .background {
            RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        }
    }
}
