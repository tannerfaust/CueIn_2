import SwiftUI

// MARK: - TimelessRunSetupSheet
/// Picks **run end** and starts the proportional timeless planner (`startTimelessRun`).

struct TimelessRunSetupSheet: View {
    @Binding var draftRunEnd: Date
    let onStart: (Date) -> Void
    let onCancel: () -> Void

    var body: some View {
        CueInBottomSheet(title: "Timeless run", onDismiss: onCancel) {
            VStack(alignment: .leading, spacing: CueInSpacing.lg) {
                Text("Choose when your run should end. Blocks stretch or compress to fit that window.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("End run")
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textTertiary)

                DatePicker(
                    "",
                    selection: $draftRunEnd,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .tint(CueInColors.textPrimary)

                Button {
                    let floor = Date().addingTimeInterval(60)
                    onStart(max(draftRunEnd, floor))
                } label: {
                    Text("Start run")
                        .font(CueInTypography.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, CueInSpacing.md)
                        .foregroundStyle(.black)
                        .background(CueInColors.textPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: CueInSpacing.cardRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(draftRunEnd <= Date())

                Button("Cancel", role: .cancel, action: onCancel)
                    .font(CueInTypography.body)
                    .foregroundStyle(CueInColors.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    TimelessRunSetupSheet(
        draftRunEnd: .constant(Date().addingTimeInterval(8 * 3600)),
        onStart: { _ in },
        onCancel: {}
    )
    .cueInPreferredColorScheme()
}
