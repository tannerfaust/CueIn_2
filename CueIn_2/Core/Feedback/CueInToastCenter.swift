import SwiftUI

// MARK: - CueInToastCenter
/// App-wide reversible feedback surface.
/// Keep action ownership at the call site so undo can restore the exact object state.

@MainActor
@Observable
final class CueInToastCenter {
    static let shared = CueInToastCenter()

    private var dismissTask: Task<Void, Never>?

    var toast: CueInUndoToastModel?

    private init() {}

    func show(
        icon: String,
        title: String,
        message: String,
        tint: Color? = nil,
        duration: Duration? = .seconds(4),
        undoTitle: String = "Undo",
        style: CueInToastStyle = .normal,
        actions: [CueInToastActionModel] = [],
        undo: @escaping @MainActor () -> Void
    ) {
        dismissTask?.cancel()
        let resolvedTint = tint ?? Color(hex: 0x64A8FF)
        let nextToast = CueInUndoToastModel(
            icon: icon,
            title: title,
            message: message,
            tint: resolvedTint,
            undoTitle: undoTitle,
            style: style,
            actions: actions,
            undo: undo
        )

        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            toast = nextToast
        }

        if let duration {
            dismissTask = Task { @MainActor in
                try? await Task.sleep(for: duration)
                guard !Task.isCancelled else { return }
                dismiss(id: nextToast.id)
            }
        } else {
            dismissTask = nil
        }
    }

    func showWarning(
        icon: String,
        title: String,
        message: String,
        actions: [CueInToastActionModel] = [],
        dismissTitle: String = "Dismiss"
    ) {
        show(
            icon: icon,
            title: title,
            message: message,
            tint: Color(hex: 0xFF4F8B),
            duration: nil,
            undoTitle: dismissTitle,
            style: .warning,
            actions: actions
        ) {}
    }

    func performUndo(for toast: CueInUndoToastModel) {
        toast.undo()
        dismiss(id: toast.id)
    }

    func dismiss(id: UUID? = nil) {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            if let id {
                if toast?.id == id {
                    toast = nil
                }
            } else {
                toast = nil
            }
        }
    }
}

enum CueInToastStyle {
    case normal
    case warning
}

struct CueInToastActionModel: Identifiable {
    let id = UUID()
    let title: String
    let systemImage: String?
    let action: @MainActor () -> Void

    init(
        title: String,
        systemImage: String? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }
}

struct CueInUndoToastModel: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let message: String
    let tint: Color
    let undoTitle: String
    let style: CueInToastStyle
    let actions: [CueInToastActionModel]
    let undo: @MainActor () -> Void
}
