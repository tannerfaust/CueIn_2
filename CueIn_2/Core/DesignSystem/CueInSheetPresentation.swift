import SwiftUI

// MARK: - Sheet presentation (system Liquid Glass)
//
// iOS 26+ modal sheets use system **Liquid Glass** / frosted blur over the presenting scene by default.
//
// **Do not** use `.presentationBackground` with an opaque `Color` (for example
// `CueInColors.surfacePrimary`) unless you intentionally want a flat sheet — that replaces the
// default glass with a solid layer (reads as a dim “fade,” not a live blur).
//
// Standard stack: `presentationDetents` + `presentationDragIndicator(.visible)` +
// `presentationCornerRadius` — **no** opaque `presentationBackground`.

enum CueInSheetPresentation {
    static let cornerRadius: CGFloat = 24
}
