import SwiftUI

// MARK: - AntiTodoRowView

struct AntiTodoRowView: View {
    let item: AntiTodoItem
    let onTap: () -> Void

    private var activeNow: Bool {
        item.scheduleIsActiveNow()
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: CueInSpacing.md) {
                Image(systemName: "slash.circle.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(CueInColors.textTertiary)
                    .frame(width: 28, height: 28)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.sm) {
                        Text(item.title)
                            .font(CueInTypography.bodyMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if activeNow {
                            Text("Now")
                                .font(CueInTypography.micro)
                                .foregroundStyle(CueInColors.danger.opacity(0.95))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(CueInColors.danger.opacity(0.16), in: Capsule(style: .continuous))
                        }
                    }

                    if let caption = item.scheduleCaption() {
                        Text(caption)
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CueInColors.textTertiary)
                    .padding(.top, 4)
            }
            .padding(CueInSpacing.md)
            .background(CueInColors.surfacePrimary.opacity(0.92), in: RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous)
                    .strokeBorder(
                        activeNow ? CueInColors.danger.opacity(0.35) : CueInColors.cardBorder,
                        lineWidth: activeNow ? 1 : 0.5
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
