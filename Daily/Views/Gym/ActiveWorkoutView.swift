import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: WorkoutSession
    @Query private var allSets: [SetLog]
    @Query private var overrides: [DayTypeOverride]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @AppStorage("pref.restSeconds") private var restSeconds = 90
    @State private var confirmDiscard = false
    @State private var restEnd: Date?
    @State private var restFinished = 0

    var onFinish: (WorkoutSession) -> Void = { _ in }

    private var isGymDay: Bool {
        DayPlanner(pattern: pattern, overrides: overrides).type(for: session.date) == .gym
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statusBar
                if isGymDay { trainBanner }
                ForEach(session.exercises, id: \.self) { exercise in
                    ExerciseCard(session: session, exercise: exercise, allSets: allSets) {
                        startRest()
                    }
                }
                cardioCard
                Button {
                    let now = Date()
                    session.caloriesBurned = Burn.estimate(for: session, until: now)
                    session.finishedAt = now
                    onFinish(session)
                } label: {
                    Text("Finish workout")
                        .font(.headline)
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(Palette.gym, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Palette.bg.ignoresSafeArea())
        .sensoryFeedback(.success, trigger: restFinished)
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { context.delete(session) }
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: "Gym · started " + session.date.formatted(date: .omitted, time: .shortened))
                Text("\(session.templateName) day")
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                SectionLabel(text: "Elapsed")
                Text(session.date, style: .timer)
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(Palette.gymText)
            }
            Menu {
                Button("Discard workout", role: .destructive) { confirmDiscard = true }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.top, 8)
    }

    // MARK: Rest timer and calories

    private func startRest() {
        let end = Date().addingTimeInterval(Double(restSeconds))
        restEnd = end
        Task {
            try? await Task.sleep(for: .seconds(Double(restSeconds)))
            if restEnd == end {
                restEnd = nil
                restFinished += 1
            }
        }
    }

    private var statusBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { tl in
            HStack(spacing: 12) {
                if let restEnd, restEnd > tl.date {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("REST").font(.caption2.weight(.heavy)).opacity(0.7)
                        Text(Pomodoro.clock(restEnd.timeIntervalSince(tl.date)))
                            .font(.system(size: 26, weight: .heavy).monospacedDigit())
                    }
                    Spacer()
                    Button("+30s") {
                        let end = restEnd.addingTimeInterval(30)
                        self.restEnd = end
                        Task {
                            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
                            if self.restEnd == end {
                                self.restEnd = nil
                                restFinished += 1
                            }
                        }
                    }
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .frame(height: 34)
                    .background(Palette.bg.opacity(0.15), in: Capsule())
                    Button("Skip") { self.restEnd = nil }
                        .font(.subheadline.weight(.bold))
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(Palette.bg.opacity(0.15), in: Capsule())
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("BURNED SO FAR").font(.caption2.weight(.heavy)).opacity(0.7)
                        HStack(spacing: 4) {
                            Image(systemName: "flame.fill").foregroundStyle(Palette.gym)
                            Text("\(Burn.estimate(for: session, until: tl.date)) cal")
                                .font(.system(size: 22, weight: .heavy).monospacedDigit())
                        }
                    }
                    Spacer()
                    Text("Check off a set to start a \(restSeconds)s rest")
                        .font(.caption)
                        .opacity(0.7)
                        .multilineTextAlignment(.trailing)
                }
            }
            .foregroundStyle(Palette.bg)
            .card(padding: 14, fill: Palette.ink)
            .buttonStyle(.plain)
        }
    }

    /// Your next way home today, from the gym-day routine.
    private var nextDeparture: TimelineBlock? {
        DayPlanner(pattern: pattern, overrides: overrides)
            .blocks(for: session.date, lunchNote: nil, dinnerNote: nil)
            .first { $0.isDeparture && $0.start > Date() && $0.category != .gym }
    }

    @ViewBuilder
    private var trainBanner: some View {
        if let next = nextDeparture {
            let leaveBy = next.leaveBy ?? next.start
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(next.title + " · " + (next.isEstimate ? "~" : "") + next.start.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.bold))
                    Text("Wrap up by " + leaveBy.formatted(date: .omitted, time: .shortened) + " to make it")
                        .font(.caption)
                        .opacity(0.75)
                }
                Spacer()
            }
            .foregroundStyle(Palette.bg)
            .card(padding: 14, fill: Palette.ink)
        }
    }

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Cardio")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CardioKind.allCases) { kind in
                        ChoiceChip(title: kind.title, isOn: session.cardioKindRaw == kind.rawValue, tint: Palette.gym) {
                            session.cardioKindRaw = session.cardioKindRaw == kind.rawValue ? "" : kind.rawValue
                        }
                    }
                }
            }
            Stepper(value: $session.cardioMinutes, in: 0...180, step: 5) {
                Text(session.cardioMinutes == 0 ? "None" : "\(session.cardioMinutes) min")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
            }
            TextField("e.g. Incline walk, 12%, 3.0 mph", text: $session.cardioNote)
                .font(.subheadline)
                .padding(10)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .card()
    }
}

struct ExerciseCard: View {
    @Environment(\.modelContext) private var context
    let session: WorkoutSession
    let exercise: String
    let allSets: [SetLog]
    var onSetDone: () -> Void = {}

    private var sets: [SetLog] {
        session.allSets.filter { $0.exercise == exercise }.sorted { $0.index < $1.index }
    }

    var body: some View {
        let last = GymHistory.lastSets(for: exercise, excluding: session.persistentModelID, in: allSets)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(exercise)
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(GymHistory.summary(last) ?? "First time")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 8) {
                Text("SET").frame(width: 34, alignment: .leading)
                Text("LB").frame(maxWidth: .infinity, alignment: .leading)
                Text("REPS").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 44, height: 1)
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(Palette.muted)

            if let target = Coach.target(lastSets: last),
               sets.contains(where: { !$0.isDone && ($0.weight != target.weight || $0.reps != target.reps) }) {
                Button {
                    for set in sets where !set.isDone {
                        set.weight = target.weight
                        set.reps = target.reps
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.fill")
                        Text("Coach: \(Coach.format(target.weight)) × \(target.reps) · \(target.reason)")
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 4)
                        Text("Apply").font(.footnote.weight(.heavy))
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.gymText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Palette.gymTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            ForEach(sets) { entry in
                SetRow(entry: entry, onDone: onSetDone)
            }

            Button {
                addSet()
            } label: {
                Text("+ Add set")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.idle, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func addSet() {
        let previous = sets.last
        let entry = SetLog(exercise: exercise, index: sets.count,
                           weight: previous?.weight ?? 0, reps: previous?.reps ?? 10)
        context.insert(entry)
        entry.session = session
    }
}

struct SetRow: View {
    @Environment(\.modelContext) private var context
    @Bindable var entry: SetLog
    var onDone: () -> Void = {}

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.index + 1)")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, alignment: .leading)
            TextField("0", value: $entry.weight, format: .number)
                .platformKeyboard(.decimalPad)
                .font(.body.weight(.bold))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            TextField("0", value: $entry.reps, format: .number)
                .platformKeyboard(.numberPad)
                .font(.body.weight(.bold))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                entry.isDone.toggle()
                if entry.isDone {
                    entry.date = .now
                    onDone()
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(entry.isDone ? Palette.onAccent : Palette.gym)
                    .frame(width: 44, height: 40)
                    .background(entry.isDone ? Palette.gym : Color.clear,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Palette.gym, lineWidth: 2)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isDone ? "Mark set not done" : "Mark set done")
        }
        .padding(4)
        .background(entry.isDone ? Palette.gymTint : Color.clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button("Delete set", role: .destructive) { context.delete(entry) }
        }
    }
}
