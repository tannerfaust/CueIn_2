import SwiftUI

// MARK: - Liquid glass toggle chrome (iOS 26)
/// Shared capsule shell + selection thumb for segmented controls (Today mode bar, block editor strips).

struct CueInLiquidGlassToggleShellModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.cueInGlass(
            .capsule,
            tint: Color.white.opacity(0.08),
            showsBorder: true,
            borderColor: Color.white.opacity(0.12),
            borderWidth: 0.6
        )
    }
}

struct CueInLiquidGlassToggleThumb: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.clear)
            .cueInGlass(
                .capsule,
                tint: Color.white.opacity(0.16),
                showsBorder: true,
                borderColor: Color.white.opacity(0.10),
                borderWidth: 0.5
            )
    }
}

// MARK: - Full-width segment strip

/// Equal-width segments inside a liquid glass capsule — Blocking/Flowing, task source, etc.
struct CueInLiquidGlassSegmentStrip: View {
    struct Segment: Identifiable {
        let id: String
        let title: String
        let systemImage: String
        var accessibilityHint: String?

        init(id: String, title: String, systemImage: String, accessibilityHint: String? = nil) {
            self.id = id
            self.title = title
            self.systemImage = systemImage
            self.accessibilityHint = accessibilityHint
        }
    }

    let segments: [Segment]
    let selectionID: String
    let onSelect: (String) -> Void

    @Namespace private var thumbNamespace

    private static let rowHeight: CGFloat = 32

    var body: some View {
        HStack(spacing: 0) {
            ForEach(segments) { seg in
                segmentCell(seg)
            }
        }
        .padding(2)
        .modifier(CueInLiquidGlassToggleShellModifier())
        .frame(maxWidth: .infinity)
    }

    private func segmentCell(_ seg: Segment) -> some View {
        let isSelected = selectionID == seg.id
        return Button {
            guard !isSelected else { return }
            withAnimation(.spring(response: 0.26, dampingFraction: 0.88)) {
                onSelect(seg.id)
            }
        } label: {
            ZStack {
                if isSelected {
                    CueInLiquidGlassToggleThumb()
                        .matchedGeometryEffect(id: "cueInLiquidSegThumb", in: thumbNamespace)
                        .padding(1)
                }

                HStack(spacing: 5) {
                    Image(systemName: seg.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                    Text(seg.title)
                        .font(CueInTypography.caption)
                }
                .foregroundStyle(isSelected ? CueInColors.textPrimary : CueInColors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity)
                .frame(height: Self.rowHeight)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seg.title)
        .accessibilityHint(seg.accessibilityHint ?? "")
    }
}
