import SwiftUI

// MARK: - PomodoroTimerRing

struct PomodoroTimerRing: View {
    var progress: Double
    var accent: Color
    var lineWidth: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(CueInColors.surfaceTertiary, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(
                    AngularGradient(
                        colors: [accent.opacity(0.55), accent, accent.opacity(0.75)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: progress)
        }
        .accessibilityHidden(true)
    }
}
