import Foundation
import SwiftUI

// MARK: - CueIn Spacing System
/// 4-point grid spacing tokens.

enum CueInSpacing {
    /// 4pt
    static let xs: CGFloat = 4
    /// 8pt
    static let sm: CGFloat = 8
    /// 12pt
    static let md: CGFloat = 12
    /// 16pt — default
    static let base: CGFloat = 16
    /// 20pt
    static let lg: CGFloat = 20
    /// 24pt
    static let xl: CGFloat = 24
    /// 32pt
    static let xxl: CGFloat = 32
    /// 40pt
    static let xxxl: CGFloat = 40
    /// 48pt
    static let huge: CGFloat = 48

    // MARK: Specific tokens

    /// Card internal padding
    static let cardPadding: CGFloat = 16
    /// Card corner radius
    static let cardRadius: CGFloat = 16
    /// Chip corner radius
    static let chipRadius: CGFloat = 8
    /// Bottom tab bar height
    static let tabBarHeight: CGFloat = 60
    /// Plus button size (matches `CueInLayout.fabPlusDiameter` floating add control).
    static let plusButtonSize: CGFloat = 62
    /// Screen horizontal margin
    static let screenHorizontal: CGFloat = 20
}

// MARK: - CueIn Layout
/// Screen-size-aware layout constants.
///
/// Centralised so any future bar height change only needs one edit,
/// and so that SE-sized (375 × 667 pt, home-button) phones get the
/// correct insets automatically.

enum CueInLayout {
    /// Shared horizontal margin for the bottom nav cluster and trailing action.
    static let bottomChromeHorizontalMargin: CGFloat = 16
    /// Height of the floating tab bar itself (no action cluster).
    static let floatingBarHeight: CGFloat = 60
    /// Visual gap between the tab capsule and the trailing action column.
    static let bottomChromeSidecarSpacing: CGFloat = 12

    // MARK: Floating FAB column (execution + add)

    /// Execution bolt — scaled with the tab bar / plus cluster.
    static let fabExecutionDiameter: CGFloat = 55
    /// Main floating add — matches tab bar height scale (was 56 when bar was 54pt).
    static let fabPlusDiameter: CGFloat = 62
    static let fabExecutionIconSize: CGFloat = 20
    static let fabPlusIconSize: CGFloat = 22
    /// Space between lightning and + — matches `AppShellView` bar HStack spacing (tab ↔ FABs).
    static let floatingFabVerticalSpacing: CGFloat = 12
    /// No extra offset; column height follows real layout spacing.
    private static let fabExecutionLift: CGFloat = 0

    /// Total height of the trailing FAB column when the execution button is visible.
    static var stackedFabColumnHeight: CGFloat {
        fabExecutionLift + fabExecutionDiameter + floatingFabVerticalSpacing + fabPlusDiameter
    }

    /// Minimum bottom content inset that clears the tallest possible bar state
    /// (bar + FAB column + comfortable breathing room).
    /// Use this as `.padding(.bottom, CueInLayout.scrollBottomInset)` on every
    /// full-screen scroll view so content is never hidden behind the floating bar.
    static let scrollBottomInset: CGFloat = max(floatingBarHeight, stackedFabColumnHeight) + 36

    /// Bottom padding applied to the floating bar itself.
    /// On home-button iPhones (SE 2020 / SE 3, safeAreaInsets.bottom == 0)
    /// we add a small gap so the bar breathes above the bezel.
    /// On notched / Dynamic-Island iPhones the bar extends into the
    /// home-indicator zone so no extra padding is needed.
    static func barBottomPadding(safeAreaBottom: CGFloat) -> CGFloat {
        // Slightly tighter on home-button phones so the bar sits a touch lower; notched devices use `offset` instead.
        safeAreaBottom == 0 ? 6 : 0
    }

    /// Lowers the custom bottom chrome into the same visual band as the iOS 26 native floating tab bar.
    static func bottomChromeYOffset(safeAreaBottom: CGFloat) -> CGFloat {
        safeAreaBottom > 0 ? 12 : 7
    }

    // MARK: - Top safe-area chrome (Today + paged Execution day nav)
    /// Extra top padding so title/controls sit slightly below the status / Dynamic Island (closer to system app chrome).
    static let topChromeContentTopPadding: CGFloat = 10
    static let topChromeContentBottomPadding: CGFloat = 12
    static let topChromeButtonHeight: CGFloat = 44

    /// Paged “Execution” day header strip; matches Today chrome’s vertical weight.
    static let executionDateNavHeight: CGFloat = 52
    static let executionDateNavTopPadding: CGFloat = 6
    static let executionDateNavBottomPadding: CGFloat = 8
}
