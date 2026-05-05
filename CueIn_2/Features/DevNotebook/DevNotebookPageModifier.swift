import SwiftUI

// MARK: - DevNotebookScreenModifier

private struct DevNotebookScreenModifier: ViewModifier {
    let title: String

    func body(content: Content) -> some View {
        content
            .onAppear {
                DevNotebookContext.shared.screenLabel = title
            }
    }
}

extension View {
    /// Reports a human-readable screen name for dev notebook context (optional drill-down beyond tab).
    func devNotebookScreen(_ title: String) -> some View {
        modifier(DevNotebookScreenModifier(title: title))
    }
}
