import SwiftUI

extension ScoreRing {
    var color: Color {
        switch self {
        case .move: return Palette.gym
        case .fuel: return Palette.food
        case .day: return Palette.commute
        }
    }
}

/// Ring thickness and spacing for a given size: thin enough that all three fit and the middle has room.
struct RingMetrics: Equatable {
    var stroke: CGFloat
    var gap: CGFloat
    /// Width of the open space inside the innermost ring.
    var inner: CGFloat

    init(size: CGFloat) {
        stroke = max(2.5, size / 13)
        gap = max(1.5, stroke / 4)
        let rings = CGFloat(ScoreRing.allCases.count)
        inner = max(0, size - 2 * (rings * stroke + (rings - 1) * gap))
    }
}

/// Three nested rings (Move outside, Fuel, Day inside).
struct ScoreRings<Center: View>: View {
    let score: DayScore
    var size: CGFloat = 122
    @ViewBuilder var center: () -> Center

    var body: some View {
        let m = RingMetrics(size: size)
        let stroke = m.stroke
        let gap = m.gap
        ZStack {
            ForEach(Array(ScoreRing.allCases.enumerated()), id: \.offset) { index, ring in
                let inset = CGFloat(index) * (stroke + gap)
                Circle()
                    .stroke(ring.color.opacity(0.16), lineWidth: stroke)
                    .padding(inset + stroke / 2)
                Circle()
                    .trim(from: 0, to: score.value(ring))
                    .stroke(ring.color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset + stroke / 2)
                    .animation(.snappy(duration: 0.6), value: score.value(ring))
            }
            // Whatever goes in the middle is kept inside the innermost ring.
            center()
                .frame(maxWidth: m.inner * 0.86, maxHeight: m.inner * 0.86)
        }
        .frame(width: size, height: size)
    }
}

extension ScoreRings where Center == EmptyView {
    init(score: DayScore, size: CGFloat = 122) {
        self.init(score: score, size: size) { EmptyView() }
    }
}

/// Today's score card: rings, what fills them, and a nudge.
struct DayScoreCard: View {
    let score: DayScore
    let streaks: [ScoreBuilder.StreakSummary]
    var onOpenScore: () -> Void
    var onOpenStreaks: () -> Void

    init(score: DayScore, streaks: [ScoreBuilder.StreakSummary],
         onOpenScore: @escaping () -> Void, onOpenStreaks: @escaping () -> Void) {
        self.score = score
        self.streaks = streaks
        self.onOpenScore = onOpenScore
        self.onOpenStreaks = onOpenStreaks
    }

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onOpenScore) {
                HStack(spacing: 16) {
                    VStack(spacing: 6) {
                        ScoreRings(score: score, size: 118) {
                            Text("\(score.score)")
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .contentTransition(.numericText())
                        }
                        Text("DAY SCORE")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.muted)
                            .fixedSize()
                    }
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(ScoreRing.allCases) { ring in
                            ringRow(ring)
                        }
                        if let hint = score.hint {
                            Text(hint)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Palette.commuteText)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        } else {
                            Label("Day closed", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Palette.foodText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .card()
            }
            .buttonStyle(.plain)

            Button(action: onOpenStreaks) {
                HStack(spacing: 8) {
                    ForEach(streaks.prefix(3)) { s in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                Image(systemName: s.symbol)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(s.current > 0 ? Palette.gym : Palette.faint)
                                Text("\(s.current)")
                                    .font(.system(size: 19, weight: .heavy))
                                    .foregroundStyle(Palette.ink)
                                    .contentTransition(.numericText())
                            }
                            Text(s.unit == "weeks" ? "gym weeks" : shortLabel(s))
                                .font(.caption2)
                                .foregroundStyle(Palette.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Streaks")
        }
    }

    private func shortLabel(_ s: ScoreBuilder.StreakSummary) -> String {
        switch s.id {
        case "log": return "days logging"
        case "home": return "home-meal days"
        case "closed": return "closed days"
        case "checkin": return "check-ins"
        default: return s.unit
        }
    }

    private func ringRow(_ ring: ScoreRing) -> some View {
        let items = score.items(in: ring)
        let done = items.filter(\.isDone).count
        return HStack(spacing: 8) {
            Circle().fill(ring.color).frame(width: 9, height: 9)
            Text(ring.title)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Palette.ink)
                .frame(width: 40, alignment: .leading)
            ProgressView(value: score.value(ring))
                .tint(ring.color)
            Text("\(done)/\(items.count)")
                .font(.caption.weight(.heavy).monospacedDigit())
                .foregroundStyle(Palette.ink)
        }
    }
}

/// What fills each ring today.
struct ScoreDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let score: DayScore
    let bestThisWeek: (day: Date, score: Int)?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                ScoreRings(score: score, size: 170) {
                    VStack(spacing: 0) {
                        Text("\(score.score)")
                            .font(.system(size: 34, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        Text("OF 100")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(Palette.muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .padding(.top, 24)
                if let best = bestThisWeek {
                    Text("Best this week: \(best.score) on \(best.day.formatted(.dateTime.weekday(.wide)))")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                ForEach(ScoreRing.allCases) { ring in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Circle().fill(ring.color).frame(width: 10, height: 10)
                            Text(ring.title).font(.headline).foregroundStyle(Palette.ink)
                            Spacer()
                            Text("\(Int((score.value(ring) * 100).rounded()))%")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(ring.color)
                        }
                        ForEach(score.items(in: ring)) { item in
                            HStack(spacing: 10) {
                                ZStack {
                                    Circle()
                                        .strokeBorder(item.isDone ? Color.clear : Palette.idle, lineWidth: 2)
                                        .background(Circle().fill(item.isDone ? ring.color : Color.clear))
                                    if item.isDone {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 11, weight: .heavy))
                                            .foregroundStyle(Palette.onAccent)
                                    }
                                }
                                .frame(width: 22, height: 22)
                                Text(item.title)
                                    .font(.subheadline)
                                    .foregroundStyle(item.isDone ? Palette.ink : Palette.muted)
                                Spacer()
                                if !item.isDone && item.progress > 0 {
                                    Text("\(Int((item.progress * 100).rounded()))%")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Palette.faint)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Palette.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }
}
