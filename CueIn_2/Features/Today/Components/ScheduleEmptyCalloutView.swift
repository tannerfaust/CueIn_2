import SwiftUI

// MARK: - ScheduleEmptyCalloutView
/// Shown when TimeMap mode has no template — directs people to the floating + control.

struct ScheduleEmptyCalloutView: View {
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
                .frame(height: 48)

            Text("Make or choose your TimeMap")
                .font(CueInTypography.title)
                .multilineTextAlignment(.center)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            CueInColors.textPrimary,
                            CueInColors.textPrimary.opacity(0.72),
                            CueInColors.textSecondary,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .lineSpacing(5)
                .tracking(0.35)
                .padding(.horizontal, CueInSpacing.screenHorizontal)

            Spacer()
                .frame(height: 52)

            HStack(alignment: .bottom, spacing: 0) {
                Spacer(minLength: 0)
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 50, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(CueInColors.accentFocus.opacity(0.9))
                    .rotationEffect(.degrees(8))
                    .padding(.trailing, 20)
            }

            Spacer()
                .frame(height: 72)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Make or choose your TimeMap")
        .accessibilityHint("Opens from the add button beside the tab bar.")
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        ScheduleEmptyCalloutView()
    }
    .cueInPreferredColorScheme()
}
