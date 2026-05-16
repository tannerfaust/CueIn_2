import SwiftUI

// MARK: - StatsActivityRingsView
/// Concentric progress rings (Activity-style): outer = awake window, middle = algorithm, inner = today tasks.

struct StatsActivityRingsView: View {
    var snapshot: StatsDaySnapshot
    var size: CGFloat = 168

    private let outerColor = Color(red: 0.98, green: 0.35, blue: 0.38)
    private let midColor = CueInColors.accentFocus
    private let innerColor = Color(red: 0.35, green: 0.78, blue: 0.98)

    var body: some View {
        ZStack {
            ring(progress: snapshot.awakeProgress, lineWidth: 18, diameter: size, color: outerColor)
            ring(progress: snapshot.algorithmProgress, lineWidth: 14, diameter: size - 36, color: midColor)
            ring(progress: snapshot.todayTasksProgress, lineWidth: 10, diameter: size - 62, color: innerColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Activity rings")
        .accessibilityValue(
            "Awake day \(Int(snapshot.awakeProgress * 100)) percent, algorithm \(Int(snapshot.algorithmProgress * 100)) percent, today tasks \(Int(snapshot.todayTasksProgress * 100)) percent"
        )
    }

    private func ring(progress: Double, lineWidth: CGFloat, diameter: CGFloat, color: Color) -> some View {
        let p = CGFloat(min(1, max(0, progress)))
        return ZStack {
            Circle()
                .stroke(CueInColors.surfaceTertiary, lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)

            Circle()
                .trim(from: 0, to: p)
                .stroke(
                    AngularGradient(
                        colors: [color.opacity(0.55), color, color.opacity(0.8)],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.45), value: p)
        }
    }
}
