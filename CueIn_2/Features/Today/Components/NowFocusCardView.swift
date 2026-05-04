import SwiftUI

// MARK: - NowFocusCardView
/// The hero card answering "what should I do NOW?".
/// Designed per product principle *Execution over intention* — this is the first
/// thing the user sees on Today. Shows the current task with a live progress bar,
/// the next task as a quiet hint, and a single primary action to complete.

struct NowFocusCardView: View {
    let unresolvedTask: ExecutionTaskCard?
    let currentTask: ExecutionTaskCard?
    let nextTask: ExecutionTaskCard?
    let progress: Double
    let now: Date
    let onCompleteUnresolved: () -> Void
    let onContinueUnresolved: () -> Void
    let onRescheduleUnresolved: () -> Void
    let onCompleteCurrent: () -> Void
    let onStartNext: () -> Void

    var body: some View {
        content
            .padding(.horizontal, CueInSpacing.screenHorizontal)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: currentTask?.id)
            .animation(.spring(response: 0.42, dampingFraction: 0.86), value: nextTask?.id)
    }

    @ViewBuilder
    private var content: some View {
        if let unresolvedTask {
            unresolvedCard(for: unresolvedTask)
        } else if let currentTask {
            activeCard(for: currentTask)
        } else if let nextTask {
            idleCard(nextTask: nextTask)
        } else {
            emptyCard
        }
    }

    // MARK: - Active (current task in flight)

    private func activeCard(for task: ExecutionTaskCard) -> some View {
        let tint = activeTint(for: task)
        return VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(spacing: CueInSpacing.xs) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint.opacity(0.6), radius: 4)
                Text("NOW · \(task.blockTitle.uppercased())")
                    .font(CueInTypography.micro)
                    .tracking(0.9)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(timeRangeLabel(task))
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
            }

            Text(task.title)
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            progressBar(tint: tint)

            HStack(alignment: .center, spacing: CueInSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(remainingLabel(for: task))
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .monospacedDigit()

                    if let nextTask {
                        Text(nextHintLine(nextTask))
                            .font(CueInTypography.caption)
                            .foregroundStyle(CueInColors.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: CueInSpacing.md)

                completeButton(tint: tint)
            }
        }
        .padding(CueInSpacing.lg)
        .background(activeBackground(tint: tint))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(0.22), lineWidth: 0.75)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
    }

    // MARK: - Unresolved (scheduled time passed, not done)

    private func unresolvedCard(for task: ExecutionTaskCard) -> some View {
        let tint = CueInColors.warning
        return VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(spacing: CueInSpacing.xs) {
                Circle()
                    .fill(tint)
                    .frame(width: 6, height: 6)
                    .shadow(color: tint.opacity(0.45), radius: 4)
                Text("CHECK · \(task.blockTitle.uppercased())")
                    .font(CueInTypography.micro)
                    .tracking(0.9)
                    .foregroundStyle(tint)
                Spacer(minLength: 0)
                Text(overdueLabel(for: task))
                    .font(CueInTypography.micro)
                    .foregroundStyle(tint.opacity(0.85))
                    .monospacedDigit()
            }

            Text(task.title)
                .font(.system(size: 22, weight: .semibold, design: .default))
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text("Scheduled \(timeRangeLabel(task))")
                .font(CueInTypography.caption)
                .foregroundStyle(CueInColors.textTertiary)
                .monospacedDigit()
                .lineLimit(1)

            HStack(spacing: CueInSpacing.sm) {
                unresolvedButton(
                    title: "Done",
                    systemImage: "checkmark",
                    tint: CueInColors.accentFocus,
                    filled: true,
                    action: onCompleteUnresolved
                )

                unresolvedButton(
                    title: "+15",
                    systemImage: "clock.arrow.circlepath",
                    tint: tint,
                    filled: false,
                    action: onContinueUnresolved
                )

                unresolvedButton(
                    title: "Later",
                    systemImage: "calendar.badge.clock",
                    tint: CueInColors.textSecondary,
                    filled: false,
                    action: onRescheduleUnresolved
                )
            }
        }
        .padding(CueInSpacing.lg)
        .background(activeBackground(tint: tint))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(tint.opacity(0.28), lineWidth: 0.75)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 14, y: 6)
    }

    private func unresolvedButton(
        title: String,
        systemImage: String,
        tint: Color,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .bold))
                Text(title)
                    .font(CueInTypography.captionMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(filled ? Color.black.opacity(0.9) : CueInColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, CueInSpacing.sm + 1)
            .background {
                if filled {
                    Capsule().fill(tint)
                } else {
                    Capsule()
                        .strokeBorder(tint.opacity(0.35), lineWidth: 0.75)
                        .background(Capsule().fill(CueInColors.surfaceSecondary.opacity(0.45)))
                }
            }
        }
        .buttonStyle(PressableButtonStyle())
    }

    /// Active NOW card tint: green for anything but fixed (fixed = amber "anchor").
    /// Keeps the primary-accent identity consistent with Style Guide.
    private func activeTint(for task: ExecutionTaskCard) -> Color {
        task.blockType == .fixed ? CueInColors.accentFixed : CueInColors.accentFocus
    }

    private func progressBar(tint: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.95),
                                tint.opacity(0.6),
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(proxy.size.width * progress, 4))
                    .animation(.linear(duration: 0.25), value: progress)
            }
        }
        .frame(height: 6)
    }

    private func completeButton(tint: Color) -> some View {
        Button(action: onCompleteCurrent) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                Text("Done")
                    .font(CueInTypography.bodyMedium)
            }
            .foregroundStyle(Color.black.opacity(0.9))
            .padding(.horizontal, CueInSpacing.md + 2)
            .padding(.vertical, CueInSpacing.sm + 2)
            .background(
                Capsule().fill(tint)
            )
        }
        .buttonStyle(PressableButtonStyle())
    }

    private func activeBackground(tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CueInColors.surfacePrimary)

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            tint.opacity(0.18),
                            tint.opacity(0.02),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
    }

    // MARK: - Idle (between tasks)

    private func idleCard(nextTask: ExecutionTaskCard) -> some View {
        VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(spacing: CueInSpacing.xs) {
                Circle()
                    .fill(CueInColors.textTertiary)
                    .frame(width: 6, height: 6)
                Text("BREATHE · UP NEXT")
                    .font(CueInTypography.micro)
                    .tracking(0.9)
                    .foregroundStyle(CueInColors.textTertiary)
                Spacer(minLength: 0)
                Text(relativeStartLabel(for: nextTask))
                    .font(CueInTypography.micro)
                    .foregroundStyle(CueInColors.textTertiary)
                    .monospacedDigit()
            }

            Text(nextTask.title)
                .font(.system(size: 20, weight: .semibold, design: .default))
                .foregroundStyle(CueInColors.textPrimary)
                .lineLimit(2)

            HStack(alignment: .center, spacing: CueInSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(nextTask.blockTitle)  ·  \(nextTask.durationMinutes) min")
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textTertiary)
                }

                Spacer(minLength: CueInSpacing.md)

                Button(action: onStartNext) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .bold))
                        Text("Start now")
                            .font(CueInTypography.captionMedium)
                    }
                    .foregroundStyle(CueInColors.textPrimary)
                    .padding(.horizontal, CueInSpacing.md)
                    .padding(.vertical, CueInSpacing.sm)
                    .background(
                        Capsule()
                            .strokeBorder(CueInColors.cardBorder, lineWidth: 0.75)
                            .background(Capsule().fill(CueInColors.surfaceSecondary.opacity(0.6)))
                    )
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(CueInSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CueInColors.surfacePrimary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        }
        .shadow(color: Color.black.opacity(0.14), radius: 10, y: 4)
    }

    // MARK: - Empty (day done or not started)

    private var emptyCard: some View {
        HStack(spacing: CueInSpacing.md) {
            Circle()
                .fill(CueInColors.accentFocus.opacity(0.25))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(CueInColors.accentFocus)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text("Nothing scheduled right now")
                    .font(CueInTypography.bodyMedium)
                    .foregroundStyle(CueInColors.textPrimary)
                Text("Use this moment intentionally.")
                    .font(CueInTypography.caption)
                    .foregroundStyle(CueInColors.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(CueInSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CueInColors.surfacePrimary)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CueInColors.cardBorder, lineWidth: 0.5)
        }
    }

    // MARK: - Formatting helpers

    private func timeRangeLabel(_ task: ExecutionTaskCard) -> String {
        "\(Self.hm.string(from: task.startDate))–\(Self.hm.string(from: task.endDate))"
    }

    private func remainingLabel(for task: ExecutionTaskCard) -> String {
        let secondsLeft = max(Int(task.endDate.timeIntervalSince(now)), 0)
        let minutes = (secondsLeft + 59) / 60
        if minutes <= 0 { return "Wrapping up" }
        if minutes == 1 { return "1 min left" }
        return "\(minutes) min left"
    }

    private func overdueLabel(for task: ExecutionTaskCard) -> String {
        let seconds = max(Int(now.timeIntervalSince(task.endDate)), 0)
        let minutes = max((seconds + 59) / 60, 1)
        if minutes < 60 { return "\(minutes)m over" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h over" : "\(hours)h \(remainder)m over"
    }

    private func nextHintLine(_ task: ExecutionTaskCard) -> String {
        "Next · \(task.title) · \(Self.hm.string(from: task.startDate))"
    }

    private func relativeStartLabel(for task: ExecutionTaskCard) -> String {
        let seconds = max(task.startDate.timeIntervalSince(now), 0)
        if seconds < 60 { return "starts now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "in \(minutes) min" }
        return "at \(Self.hm.string(from: task.startDate))"
    }

    private static let hm: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

// MARK: - Pressable button style
/// Subtle press feedback used by NOW card buttons.

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}
