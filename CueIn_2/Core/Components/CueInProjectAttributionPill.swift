import SwiftUI

// MARK: - CueInProjectAttributionPill
/// Compact project / field capsule: colored icon, neutral label, outline-forward chrome.

struct CueInProjectAttributionPill: View {
    let title: String
    let systemImage: String
    let iconTint: Color
    var isMuted: Bool = false
    /// When set, caps width and truncates the label. When `nil`, the pill grows with the name (still single-line).
    var maxWidth: CGFloat? = nil
    /// When `false`, shows only the tinted icon in a compact circle (use ``title`` for accessibility).
    var showsLabel: Bool = true

    private var mutedIconOpacity: Double { isMuted ? 0.48 : 1 }
    private var fillOpacity: Double { isMuted ? 0.52 : 0.92 }
    private var strokeOpacity: Double { isMuted ? 0.055 : 0.11 }

    var body: some View {
        Group {
            if showsLabel {
                labelBody
            } else {
                iconOnlyBody
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(title)
            }
        }
    }

    private var labelBody: some View {
        Group {
            if let maxWidth {
                labelRow
                    .frame(maxWidth: maxWidth)
            } else {
                labelRow
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .background {
            Capsule(style: .continuous)
                .fill(CueInColors.surfacePrimary.opacity(fillOpacity))
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 0.5)
        }
    }

    private var labelRow: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(iconTint.opacity(mutedIconOpacity))
            Text(title)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(CueInColors.textSecondary.opacity(isMuted ? 0.4 : 0.88))
                .lineLimit(1)
                .minimumScaleFactor(maxWidth == nil ? 1 : 0.78)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private var iconOnlyBody: some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(iconTint.opacity(mutedIconOpacity))
            .frame(width: 22, height: 22)
            .background {
                Circle()
                    .fill(CueInColors.surfacePrimary.opacity(fillOpacity))
            }
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(strokeOpacity), lineWidth: 0.5)
            }
    }
}
