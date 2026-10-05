import SwiftUI
import SwiftData
import Charts

/// Pomodoro timer and focus history.
struct FocusView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \FocusSession.start, order: .reverse) private var sessions: [FocusSession]

    @AppStorage(Pomodoro.Settings.focusKey, store: SharedStore.defaults) private var focusMinutes = 25
    @AppStorage(Pomodoro.Settings.shortKey, store: SharedStore.defaults) private var shortMinutes = 5
    @AppStorage(Pomodoro.Settings.longKey, store: SharedStore.defaults) private var longMinutes = 15
    @AppStorage(Pomodoro.Settings.roundsKey, store: SharedStore.defaults) private var roundsPerSet = 4
    @AppStorage("pomo.label") private var label = ""

    @State private var now = Date()
    @State private var active: Pomodoro.Active? = SharedStore.activeFocus
    @State private var nextUp = FocusController.nextUp
    @State private var showSettings = false
    @FocusState private var labelFocused: Bool

    init() {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    ScreenHeader(eyebrow: "Pomodoro", title: "Focus")
                    Spacer()
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                            .frame(width: 36, height: 36)
                            .background(Palette.card, in: Circle())
                    }
                    .accessibilityLabel("Timer settings")
                }
                timerCard
                statsRow
                weekCard
                historyCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 90)
        }
        .background(Palette.bg.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .task {
            // Tick once a second; log the round when the timer runs out.
            while !Task.isCancelled {
                tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .sheet(isPresented: $showSettings) {
            settingsSheet
        }
    }

    private func tick() {
        now = Date()
        if FocusController.settle(context: context, at: now) {
            nextUp = FocusController.nextUp
        }
        active = SharedStore.activeFocus
    }

    // MARK: Timer

    private var phase: Pomodoro.Phase { active?.phase ?? nextUp.phase }
    private var round: Int { active?.round ?? nextUp.round }
    private var color: Color { phase == .focus ? Palette.focus : Palette.water }

    private var remaining: TimeInterval {
        if let active { return Pomodoro.remaining(active, at: now) }
        return TimeInterval(Pomodoro.Settings.load().minutes(for: phase) * 60)
    }

    private var progress: Double {
        guard let active else { return 0 }
        return Pomodoro.progress(active, at: now)
    }

    private var timerCard: some View {
        VStack(spacing: 18) {
            HStack {
                Label(phase.title, systemImage: phase.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(color)
                Spacer()
                roundDots
            }

            ZStack {
                Circle()
                    .stroke(Palette.circle, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(color, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                VStack(spacing: 4) {
                    Text(Pomodoro.clock(remaining))
                        .font(.system(size: 54, weight: .heavy).monospacedDigit())
                        .foregroundStyle(Palette.ink)
                        .contentTransition(.numericText())
                    Text(statusLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
            }
            .frame(width: 230, height: 230)
            .frame(maxWidth: .infinity)

            if phase == .focus {
                if active == nil {
                    TextField("What are you working on?", text: $label)
                        .font(.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .focused($labelFocused)
                        .submitLabel(.done)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .background(Palette.card2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else if let active, !active.label.isEmpty {
                    Text(active.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
            }

            controls
        }
        .card(padding: 18)
    }

    private var statusLine: String {
        guard let active else {
            return phase == .focus ? "\(Pomodoro.Settings.load().focusMinutes)-minute focus" : "Break ready"
        }
        if active.isPaused { return "Paused" }
        return "Ends " + active.end.formatted(date: .omitted, time: .shortened)
    }

    private var roundDots: some View {
        let total = max(Pomodoro.Settings.load().roundsPerSet, 1)
        // Rounds finished in this set: the ones before the current round, plus this one once its break starts.
        let done = phase == .focus ? round - 1 : round
        return HStack(spacing: 5) {
            ForEach(1...total, id: \.self) { index in
                Circle()
                    .fill(index <= done ? Palette.focus : Palette.circle)
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityLabel("Round \(min(round, total)) of \(total)")
    }

    @ViewBuilder
    private var controls: some View {
        if let active {
            HStack(spacing: 10) {
                bigButton(active.isPaused ? "Resume" : "Pause",
                          symbol: active.isPaused ? "play.fill" : "pause.fill",
                          fill: color, text: Palette.onAccent) {
                    if active.isPaused { FocusController.resume() } else { FocusController.pause() }
                    tick()
                }
                bigButton(active.phase == .focus ? "Stop" : "Skip",
                          symbol: active.phase == .focus ? "stop.fill" : "forward.fill",
                          fill: Palette.card2, text: Palette.ink) {
                    if active.phase == .focus {
                        FocusController.stop(context: context)
                    } else {
                        FocusController.skip(context: context)
                    }
                    nextUp = FocusController.nextUp
                    tick()
                }
            }
        } else {
            HStack(spacing: 10) {
                bigButton("Start " + (phase == .focus ? "focus" : phase.title.lowercased()),
                          symbol: "play.fill", fill: color, text: Palette.onAccent) {
                    labelFocused = false
                    FocusController.start(phase, label: phase == .focus ? label : "", round: round)
                    tick()
                }
                if phase != .focus || round > 1 {
                    Menu {
                        if phase != .focus {
                            Button("Skip break", systemImage: "forward.fill") {
                                FocusController.skip(context: context)
                                nextUp = FocusController.nextUp
                            }
                        }
                        Button("Start a new set", systemImage: "arrow.counterclockwise") {
                            FocusController.setNextUp(.focus, round: 1)
                            nextUp = FocusController.nextUp
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                            .frame(width: 52, height: 50)
                            .background(Palette.card2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .accessibilityLabel("More")
                }
            }
        }
    }

    private func bigButton(_ title: String, symbol: String, fill: Color, text: Color,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .foregroundStyle(text)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(fill, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Stats

    private var statsRow: some View {
        let today = Date()
        return HStack(spacing: 10) {
            stat("\(FocusStats.rounds(on: today, in: sessions))", "rounds today", color: Palette.focusText)
            stat(minutesLabel(FocusStats.minutes(on: today, in: sessions)), "focused today", color: Palette.ink)
            stat("\(FocusStats.streak(endingOn: today, in: sessions))", "day streak", color: Palette.foodText)
        }
    }

    private func stat(_ value: String, _ caption: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(color)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(caption)
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .card(padding: 14)
    }

    private func minutesLabel(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    private var weekCard: some View {
        let week = FocusStats.daily(days: 7, endingOn: Date(), in: sessions)
        let total = week.reduce(0) { $0 + $1.minutes }
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(text: "Last 7 days")
                Spacer()
                Text(minutesLabel(total))
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
            }
            Chart(week) { entry in
                BarMark(x: .value("Day", entry.day, unit: .day),
                        y: .value("Minutes", entry.minutes))
                    .foregroundStyle(Calendar.current.isDateInToday(entry.day) ? Palette.focus : Palette.focus.opacity(0.45))
                    .cornerRadius(5)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Palette.line)
                    AxisValueLabel()
                }
            }
            .frame(height: 130)
        }
        .card()
    }

    private var historyCard: some View {
        let today = FocusStats.sessions(on: Date(), in: sessions)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Today's focus")
            if today.isEmpty {
                Text("No focus rounds yet today")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            } else {
                ForEach(today) { session in
                    HStack(spacing: 12) {
                        Image(systemName: session.completed ? "checkmark" : "stop.fill")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(session.completed ? Palette.focus : Palette.faint)
                            .frame(width: 32, height: 32)
                            .background(Palette.circle, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.label.isEmpty ? "Focus" : session.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Palette.ink)
                                .lineLimit(1)
                            Text(session.start.formatted(date: .omitted, time: .shortened) + " – "
                                 + session.end.formatted(date: .omitted, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        Text("\(session.minutes) min")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.ink)
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            context.delete(session)
                        }
                    }
                }
            }
        }
        .card()
    }

    // MARK: Settings

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Lengths") {
                    Stepper("Focus: \(focusMinutes) min", value: $focusMinutes, in: 5...120, step: 5)
                    Stepper("Short break: \(shortMinutes) min", value: $shortMinutes, in: 1...30)
                    Stepper("Long break: \(longMinutes) min", value: $longMinutes, in: 5...60, step: 5)
                    Stepper("Long break after \(roundsPerSet) rounds", value: $roundsPerSet, in: 2...8)
                }
                Section {
                    Button("Classic (25 / 5 / 15)") { setLengths(25, 5, 15) }
                    Button("Deep work (50 / 10 / 20)") { setLengths(50, 10, 20) }
                } header: {
                    Text("Presets")
                } footer: {
                    Text("Changes apply to the next timer you start. The running timer shows on your Lock Screen when “Lock Screen” is on in Today’s Now card.")
                }
            }
            .navigationTitle("Timer")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func setLengths(_ focus: Int, _ short: Int, _ long: Int) {
        focusMinutes = focus
        shortMinutes = short
        longMinutes = long
    }
}
