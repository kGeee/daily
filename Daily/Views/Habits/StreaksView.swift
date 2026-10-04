import SwiftUI

/// All your streaks, with a calendar and the freezes you've saved up.
struct StreaksView: View {
    @Environment(\.dismiss) private var dismiss
    let streaks: [ScoreBuilder.StreakSummary]

    @State private var selected: String

    init(streaks: [ScoreBuilder.StreakSummary]) {
        self.streaks = streaks
        _selected = State(initialValue: streaks.first?.id ?? "log")
    }

    private var current: ScoreBuilder.StreakSummary? { streaks.first { $0.id == selected } ?? streaks.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel(text: "Keep it going", color: Palette.gymText)
                        Text("Streaks")
                            .font(.system(size: 30, weight: .heavy))
                            .foregroundStyle(Palette.ink)
                    }
                    if let s = current, s.unit == "days" {
                        calendarCard(s)
                    }
                    VStack(spacing: 0) {
                        ForEach(streaks) { s in
                            Button { withAnimation(.snappy) { selected = s.id } } label: { row(s) }
                                .buttonStyle(.plain)
                            if s.id != streaks.last?.id {
                                Rectangle().fill(Palette.line).frame(height: 1).padding(.leading, 54)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                    HStack(spacing: 10) {
                        Image(systemName: "snowflake")
                            .foregroundStyle(Palette.waterText)
                        Text("Each week you hit a streak's goal most days, you earn a freeze (up to 2). A missed day uses one instead of breaking the streak.")
                            .font(.footnote)
                            .foregroundStyle(Palette.waterText)
                    }
                    .padding(14)
                    .background(Palette.waterTint, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func row(_ s: ScoreBuilder.StreakSummary) -> some View {
        HStack(spacing: 12) {
            Image(systemName: s.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(s.current > 0 ? Palette.gym : Palette.faint)
                .frame(width: 42, height: 42)
                .background(Palette.circle, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                Text("Best \(s.best) \(s.unit)").font(.caption).foregroundStyle(Palette.muted)
            }
            Spacer()
            if s.unit == "days" {
                HStack(spacing: 3) {
                    ForEach(0..<Streaks.maxFreezes, id: \.self) { i in
                        Image(systemName: "snowflake")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(i < s.freezes ? Palette.waterText : Palette.faint)
                            .frame(width: 22, height: 22)
                            .background(i < s.freezes ? Palette.waterTint : Palette.circle, in: Circle())
                    }
                }
                .accessibilityLabel("\(s.freezes) freezes saved")
            }
            Text("\(s.current)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(Palette.ink)
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .background(selected == s.id ? Palette.card2.opacity(0.6) : Color.clear)
        .contentShape(Rectangle())
    }

    /// The last six weeks for one streak.
    private func calendarCard(_ s: ScoreBuilder.StreakSummary) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let start = cal.date(byAdding: .day, value: -41, to: today) ?? today
        let days = (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.title).font(.headline).foregroundStyle(Palette.ink)
                Spacer()
                Label("\(s.current)", systemImage: "flame.fill")
                    .font(.title2.weight(.heavy))
                    .foregroundStyle(Palette.gymText)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 14), spacing: 4) {
                ForEach(days, id: \.self) { day in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(color(for: day, in: s, today: today))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if cal.isDate(day, inSameDayAs: today) {
                                RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Palette.ink, lineWidth: 1.5)
                            }
                        }
                }
            }
            HStack(spacing: 14) {
                legend(Palette.food, "Done")
                legend(Palette.water.opacity(0.5), "Freeze used")
                legend(Palette.circle, "Missed")
            }
        }
        .card()
    }

    private func color(for day: Date, in s: ScoreBuilder.StreakSummary, today: Date) -> Color {
        if s.active.contains(day) { return Palette.food }
        if s.frozen.contains(day) { return Palette.water.opacity(0.5) }
        return Palette.circle
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(Palette.muted)
        }
    }
}

// MARK: - Celebration

/// Confetti that falls once (skipped when Reduce Motion is on).
struct ConfettiView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    private struct Piece {
        let x: Double, delay: Double, speed: Double, spin: Double, size: CGSize, color: Color
    }

    private static let colors: [Color] = [Palette.gym, Palette.food, Palette.commute, Palette.general, Palette.water]
    private let pieces: [Piece] = (0..<70).map { i in
        var rng = SeededRandom(seed: UInt64(i + 1))
        return Piece(x: rng.next(), delay: rng.next() * 0.6, speed: 0.55 + rng.next() * 0.6,
                     spin: (rng.next() - 0.5) * 12,
                     size: CGSize(width: 6 + rng.next() * 6, height: 9 + rng.next() * 8),
                     color: ConfettiView.colors[i % ConfettiView.colors.count])
    }

    var body: some View {
        if reduceMotion {
            Color.clear
        } else {
            TimelineView(.animation) { tl in
                Canvas { context, size in
                    let t = tl.date.timeIntervalSince(start)
                    for p in pieces {
                        let age = t - p.delay
                        guard age > 0 else { continue }
                        let y = -20 + age * p.speed * size.height
                        guard y < size.height + 20 else { continue }
                        let x = p.x * size.width + sin(age * 3 + p.spin) * 18
                        var piece = context
                        piece.translateBy(x: x, y: y)
                        piece.rotate(by: .radians(age * p.spin))
                        piece.fill(Path(roundedRect: CGRect(origin: CGPoint(x: -p.size.width / 2, y: -p.size.height / 2), size: p.size),
                                        cornerRadius: 2), with: .color(p.color))
                    }
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Tiny deterministic random numbers so confetti looks the same every time it's built.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 33) % 10_000) / 10_000
    }
}

/// "Day closed" card over confetti.
struct DayClosedOverlay: View {
    let score: DayScore
    let closedThisWeek: Int
    let streak: Int
    var onDismiss: () -> Void
    @State private var appeared = false

    init(score: DayScore, closedThisWeek: Int, streak: Int, onDismiss: @escaping () -> Void) {
        self.score = score
        self.closedThisWeek = closedThisWeek
        self.streak = streak
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            Palette.ink.opacity(0.45).ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            ConfettiView().ignoresSafeArea()
            VStack(spacing: 12) {
                ScoreRings(score: score, size: 150) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                }
                Text("Day closed")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Palette.ink)
                Text(closedThisWeek > 1
                     ? "All three rings. That's \(closedThisWeek) closed days this week."
                     : "All three rings. Nice work today.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
                if streak > 1 {
                    Label("\(streak)-day streak", systemImage: "flame.fill")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(Palette.gymText)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Palette.gymTint, in: Capsule())
                }
                DetailPrimaryButton(title: "Nice", fill: Palette.ink, action: onDismiss)
                    .padding(.top, 6)
            }
            .padding(22)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .padding(24)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
        .sensoryFeedback(.success, trigger: appeared)
        .onAppear { appeared = true }
    }
}
