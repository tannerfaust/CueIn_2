#if os(iOS)
import UIKit
#endif

#if os(macOS)
enum CueInHapticImpactStyle {
    case light
    case medium
    case soft
}
#endif

// MARK: - CueInHaptics
/// Lightweight haptic affordances. Keep `prepare()` close to the gesture for responsiveness.

enum CueInHaptics {
    @MainActor
    static func listRowMoved() {
        #if os(iOS)
        impact(.light)
        #endif
    }

    #if os(iOS)
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }
    #elseif os(macOS)
    @MainActor
    static func impact(_ style: CueInHapticImpactStyle) {}
    #endif
}
