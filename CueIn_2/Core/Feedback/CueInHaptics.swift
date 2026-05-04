import UIKit

// MARK: - CueInHaptics
/// Lightweight haptic affordances. Keep `prepare()` close to the gesture for responsiveness.

enum CueInHaptics {
    @MainActor
    static func listRowMoved() {
        impact(.light)
    }

    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
}
