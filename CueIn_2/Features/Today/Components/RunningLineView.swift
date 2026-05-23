import SwiftUI

// MARK: - RunningLineBlockSegment

/// One block’s duration as a fraction of the formula day window (0…1); used to paint the running line in block accents.
struct RunningLineBlockSegment {
    var fraction: CGFloat
    var color: Color
}

// MARK: - RunningLineView
/// Live schedule progress: multiple visual treatments for the same `dayProgress` and labels.

struct RunningLineView: View {
    @AppStorage(TodayDisplayPreferences.activeBlockEmphasis) private var activeBlockEmphasisRaw
        = TodayDisplayPreferences.ActiveBlockEmphasis.brand.rawValue
    @AppStorage(TodayDisplayPreferences.runningLineSize) private var runningLineSizeRaw
        = TodayDisplayPreferences.RunningLineSize.standard.rawValue
    @AppStorage(TodayDisplayPreferences.runningLineBarWeight) private var runningLineBarWeightRaw
        = TodayDisplayPreferences.RunningLineBarWeight.standard.rawValue
    @AppStorage(TodayDisplayPreferences.runningLineFrostedCard) private var runningLineFrostedCard = true
    @AppStorage(TodayDisplayPreferences.runningLineShowBlockTitle) private var runningLineShowBlockTitle = true
    @AppStorage(TodayDisplayPreferences.runningLineShowDayPercent) private var runningLineShowDayPercent = true

    let dayProgress: Double
    let remainingLabel: String
    let currentBlockTitle: String?
    var style: TodayDisplayPreferences.RunningLineStyle = .minimal
    var accentColors: [Color] = []
    /// Block-colored spans matching ``dayProgress``; empty falls back to accent.
    var blockSegments: [RunningLineBlockSegment] = []
    /// Paused schedule in “Compress remaining” mode: solid neutral fill instead of block colors.
    var greyFillWhilePausedReplan: Bool = false
    var isStopped: Bool = false

    private var lineEmphasis: TodayDisplayPreferences.ActiveBlockEmphasis {
        TodayDisplayPreferences.migratedActiveBlockEmphasis(from: activeBlockEmphasisRaw)
    }

    private var lineSize: TodayDisplayPreferences.RunningLineSize {
        TodayDisplayPreferences.migratedRunningLineSize(from: runningLineSizeRaw)
    }

    private var barWeight: TodayDisplayPreferences.RunningLineBarWeight {
        TodayDisplayPreferences.migratedRunningLineBarWeight(from: runningLineBarWeightRaw)
    }

    private var ePrimary: Color { lineEmphasis.primary }
    private var ePartner: Color { lineEmphasis.gradientPartner }
    private var resolvedAccentColors: [Color] {
        let colors = accentColors.isEmpty ? [ePrimary, ePartner] : accentColors
        let normalized = colors.count == 1 ? [colors[0], colors[0]] : colors
        return isStopped ? normalized.map { $0.opacity(0.42) } : normalized
    }
    private var primaryAccent: Color {
        if greyFillWhilePausedReplan { return pausedReplanGrey }
        return resolvedAccentColors.first ?? ePrimary
    }
    private var pausedReplanGrey: Color { CueInColors.textTertiary.opacity(0.55) }

    private var trackH: CGFloat { barWeight.trackHeight(for: style) }

    private var hPadding: CGFloat { CueInSpacing.base * (0.9 + 0.05 * lineSize.paddingScale) }
    private var vPadding: CGFloat { CueInSpacing.md * lineSize.paddingScale }

    private var hasBlockTitle: Bool {
        runningLineShowBlockTitle
            && (currentBlockTitle != nil)
            && !(currentBlockTitle?.isEmpty ?? true)
    }

    private var clampedProgress: Double {
        min(max(dayProgress, 0), 1)
    }

    private var hasStartedProgress: Bool {
        clampedProgress > 0.0001
    }

    private func progressWidth(totalWidth: CGFloat) -> CGFloat {
        guard hasStartedProgress else { return 0 }
        return min(max(totalWidth * clampedProgress, 0), totalWidth)
    }

    /// `(trimFrom, trimTo, color)` in 0…1 of the orbit ring, matching block order.
    private var orbitRingSegmentStrokes: [(CGFloat, CGFloat, Color)] {
        if greyFillWhilePausedReplan {
            guard clampedProgress > 0 else { return [] }
            return [(0, CGFloat(clampedProgress), pausedReplanGrey.opacity(isStopped ? 0.42 : 1))]
        }
        if blockSegments.isEmpty {
            guard clampedProgress > 0 else { return [] }
            let c = (resolvedAccentColors.first ?? ePrimary).opacity(isStopped ? 0.42 : 1)
            return [(0, CGFloat(clampedProgress), c)]
        }
        var out: [(CGFloat, CGFloat, Color)] = []
        var cum: CGFloat = 0
        let p = CGFloat(clampedProgress)
        for seg in blockSegments {
            let blockStart = cum
            let blockEnd = cum + seg.fraction
            let vis0 = max(blockStart, 0)
            let vis1 = min(blockEnd, p)
            if vis1 > vis0 {
                out.append((vis0, vis1, seg.color.opacity(isStopped ? 0.42 : 1)))
            }
            cum = blockEnd
        }
        return out
    }

    @ViewBuilder
    private func runningLineClipShape<C: View>(corner: CGFloat, capsule: Bool, @ViewBuilder content: () -> C) -> some View {
        if capsule {
            content().clipShape(Capsule())
        } else {
            content().clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        }
    }

    @ViewBuilder
    private func runningLineProgressStrip(totalWidth: CGFloat, height: CGFloat, corner: CGFloat, capsule: Bool) -> some View {
        let fillW = progressWidth(totalWidth: totalWidth)
        Group {
            if greyFillWhilePausedReplan {
                runningLineClipShape(corner: corner, capsule: capsule) {
                    pausedReplanGrey
                        .opacity(isStopped ? 0.42 : 1)
                        .frame(width: fillW, height: height)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if blockSegments.isEmpty {
                runningLineClipShape(corner: corner, capsule: capsule) {
                    (resolvedAccentColors.first ?? ePrimary)
                        .opacity(isStopped ? 0.42 : 1)
                        .frame(width: fillW, height: height)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                let sumFrac = min(1, blockSegments.map(\.fraction).reduce(0, +))
                let contentW = totalWidth * sumFrac
                runningLineClipShape(corner: corner, capsule: capsule) {
                    HStack(spacing: 0) {
                        ForEach(Array(blockSegments.enumerated()), id: \.offset) { _, seg in
                            seg.color
                                .opacity(isStopped ? 0.42 : 1)
                                .frame(width: max(0, totalWidth * seg.fraction), height: height)
                        }
                    }
                    .frame(width: contentW, height: height, alignment: .leading)
                    .frame(width: fillW, alignment: .leading)
                    .clipped()
                }
            }
        }
        .shadow(color: primaryAccent.opacity(isStopped ? 0.08 : 0.18), radius: 8, x: 0, y: 0)
    }

    private var percentColor: Color {
        hasStartedProgress
            ? primaryAccent.opacity(isStopped ? 0.62 : 0.85)
            : CueInColors.textTertiary
    }

    var body: some View {
        Group {
            switch style {
            case .minimal:
                minimalLayout
            case .bar:
                barLayout
            case .liquid:
                liquidLayout
            case .orbit:
                orbitLayout
            case .ticker:
                tickerLayout
            }
        }
    }

    // MARK: - Minimal (day % + bar only)

    private var minimalLayout: some View {
        HStack(alignment: .center, spacing: CueInSpacing.sm) {
            GeometryReader { geo in
                let corner: CGFloat = max(2, trackH * 0.5)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    if hasStartedProgress {
                        runningLineProgressStrip(
                            totalWidth: geo.size.width,
                            height: trackH,
                            corner: corner,
                            capsule: false
                        )
                        .animation(.easeInOut(duration: 0.8), value: clampedProgress)
                    }
                }
            }
            .frame(height: trackH)

            if runningLineShowDayPercent {
                Text(percentString)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(percentColor)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .frame(maxWidth: .infinity)
        .background {
            if runningLineFrostedCard {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.xs)
    }

    // MARK: - Bar (original)

    private var barLayout: some View {
        VStack(alignment: .leading, spacing: CueInSpacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: CueInSpacing.sm) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isStopped ? "Paused" : "TimeMap")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.8)

                    if hasBlockTitle, let title = currentBlockTitle {
                        Text(title)
                            .font(CueInTypography.captionMedium)
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: CueInSpacing.md)

                Text(remainingLabel)
                    .font(CueInTypography.captionMedium)
                    .foregroundStyle(CueInColors.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }

            GeometryReader { geo in
                let corner: CGFloat = max(2, trackH * 0.5)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    if hasStartedProgress {
                        runningLineProgressStrip(
                            totalWidth: geo.size.width,
                            height: trackH,
                            corner: corner,
                            capsule: false
                        )
                        .animation(.easeInOut(duration: 0.8), value: clampedProgress)
                    }
                }
            }
            .frame(height: trackH)
        }
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding)
        .frame(maxWidth: .infinity)
        .background {
            if runningLineFrostedCard {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    }
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.xs)
    }

    // MARK: - Liquid (iOS 26–style glass + capsule)

    private var liquidLayout: some View {
        let contentPad = CueInSpacing.lg * (0.95 + 0.05 * lineSize.paddingScale)

        return VStack(alignment: .leading, spacing: CueInSpacing.md) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(isStopped ? "Paused" : "In flow")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CueInColors.textTertiary)

                    if hasBlockTitle, let title = currentBlockTitle {
                        Text(title)
                            .font(.system(size: lineSize.liquidBlockTitleSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(CueInColors.textPrimary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                    }
                }

                Spacer(minLength: 12)

                Text(remainingLabel)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CueInColors.textPrimary)
                    .padding(.horizontal, 14 * lineSize.paddingScale)
                    .padding(.vertical, 8 * lineSize.paddingScale)
                    .background(
                        Capsule(style: .continuous)
                            .fill(
                                (greyFillWhilePausedReplan ? pausedReplanGrey : primaryAccent)
                                    .opacity(isStopped ? 0.14 : 0.22)
                            )
                    )
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
                    }
            }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.08))

                GeometryReader { geo in
                    if hasStartedProgress {
                        runningLineProgressStrip(
                            totalWidth: geo.size.width,
                            height: max(trackH, 10),
                            corner: max(trackH, 10) * 0.5,
                            capsule: true
                        )
                        .animation(.easeInOut(duration: 0.8), value: clampedProgress)
                    }
                }
            }
            .frame(height: max(trackH, 10))
        }
        .padding(contentPad)
        .modifier(
            RunningLineMaterialChrome(
                useFrostedGlass: runningLineFrostedCard,
                cornerRadius: 28
            )
        )
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.xs * lineSize.paddingScale)
    }

    // MARK: - Orbit (ring = day, labels beside)

    private var orbitLayout: some View {
        let ring = barWeight.orbitDiameter(lineSize: lineSize)
        let strokeW = barWeight.orbitStrokeWidth()
        let trackW = max(strokeW, 3.5)

        return HStack(alignment: .center, spacing: CueInSpacing.lg * (0.85 + 0.1 * lineSize.paddingScale)) {
            ZStack {
                Circle()
                    .stroke(CueInColors.surfaceTertiary, lineWidth: trackW)
                    .frame(width: ring, height: ring)

                ForEach(Array(orbitRingSegmentStrokes.enumerated()), id: \.offset) { _, slice in
                    Circle()
                        .trim(from: slice.0, to: slice.1)
                        .stroke(
                            slice.2,
                            style: StrokeStyle(lineWidth: trackW, lineCap: .round)
                        )
                        .frame(width: ring, height: ring)
                        .rotationEffect(.degrees(-90))
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.86), value: clampedProgress)

                if runningLineShowDayPercent {
                    Text(percentString)
                        .font(.system(size: ring < 50 ? 10 : 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(CueInColors.textSecondary)
                        .monospacedDigit()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                if hasBlockTitle, let title = currentBlockTitle {
                    Text(title)
                        .font(CueInTypography.bodyMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CueInColors.textTertiary)
                    Text(remainingLabel)
                        .font(CueInTypography.caption)
                        .foregroundStyle(CueInColors.textSecondary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(CueInSpacing.md * lineSize.paddingScale)
        .background {
            if runningLineFrostedCard {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(CueInColors.surfaceSecondary.opacity(0.65))
            } else {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(CueInColors.divider.opacity(0.5), lineWidth: 0.5)
            }
        }
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.xs * lineSize.paddingScale)
    }

    private var percentString: String {
        let p = Int(round(clampedProgress * 100))
        return "\(p)%"
    }

    // MARK: - Ticker (single dense band)

    private var tickerLayout: some View {
        let iconSide = barWeight.tickerIconSide(lineSize: lineSize)

        return HStack(spacing: CueInSpacing.md * lineSize.paddingScale) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        (greyFillWhilePausedReplan ? pausedReplanGrey : primaryAccent)
                            .opacity(isStopped ? 0.22 : 0.38)
                    )
                Image(systemName: isStopped ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 18 + 2 * min(lineSize.paddingScale, 1.15)))
                    .foregroundStyle(CueInColors.textPrimary)
            }
            .frame(width: iconSide, height: iconSide)

            VStack(alignment: .leading, spacing: 2) {
                if hasBlockTitle, let title = currentBlockTitle {
                    Text(title)
                        .font(CueInTypography.captionMedium)
                        .foregroundStyle(CueInColors.textPrimary)
                        .lineLimit(1)
                }
                if runningLineShowDayPercent {
                    Text(remainingLabel + " · " + "day progress " + "\(Int(round(clampedProgress * 100)))" + "%")
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                } else {
                    Text(remainingLabel)
                        .font(CueInTypography.micro)
                        .foregroundStyle(CueInColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, hPadding)
        .padding(.vertical, vPadding * 0.9)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(CueInColors.divider, lineWidth: 0.5)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(
                            (runningLineFrostedCard ? CueInColors.background.opacity(0.2) : CueInColors.surfaceSecondary.opacity(0.4))
                        )
                }
        )
        .padding(.horizontal, CueInSpacing.screenHorizontal)
        .padding(.top, CueInSpacing.xs * lineSize.paddingScale)
    }
}

// MARK: - Material chrome (liquid: glass vs flat)

private struct RunningLineMaterialChrome: ViewModifier {
    let useFrostedGlass: Bool
    let cornerRadius: CGFloat

    @ViewBuilder
    func body(content: Content) -> some View {
        if useFrostedGlass {
            content.glassSurface(cornerRadius: cornerRadius)
        } else {
            content
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(CueInColors.surfaceSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                )
        }
    }
}

#Preview {
    ZStack {
        CueInColors.background.ignoresSafeArea()
        VStack(spacing: 24) {
            RunningLineView(
                dayProgress: 0.42,
                remainingLabel: "4h 20m left",
                currentBlockTitle: "Deep Work",
                style: .minimal
            )
            RunningLineView(
                dayProgress: 0.42,
                remainingLabel: "4h 20m left",
                currentBlockTitle: "Deep Work",
                style: .bar
            )
            RunningLineView(
                dayProgress: 0.42,
                remainingLabel: "4h 20m left",
                currentBlockTitle: "Deep Work",
                style: .liquid
            )
        }
    }
    .cueInPreferredColorScheme()
}
