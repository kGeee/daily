import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Bindable var session: WorkoutSession
    @Query private var allSets: [SetLog]
    @Query private var overrides: [DayTypeOverride]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @State private var confirmDiscard = false

    private var isGymDay: Bool {
        DayPlanner(pattern: pattern, overrides: overrides).type(for: session.date) == .gym
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if isGymDay { trainBanner }
                ForEach(session.exercises, id: \.self) { exercise in
                    ExerciseCard(session: session, exercise: exercise, allSets: allSets)
                }
                cardioCard
                Button {
                    session.finishedAt = .now
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

    private var trainBanner: some View {
        let pick = MySchedule.caltrainAfterGym
        let train = pick.time.on(session.date)
        let wrapUp = train.addingTimeInterval(-Double(MySchedule.gymToStationMinutes * 60))
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Caltrain home · " + (pick.isEstimate ? "~" : "") + train.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.bold))
                Text("Wrap up by " + wrapUp.formatted(date: .omitted, time: .shortened) + " to make it")
                    .font(.caption)
                    .opacity(0.75)
            }
            Spacer()
        }
        .foregroundStyle(Palette.bg)
        .card(padding: 14, fill: Palette.ink)
    }

    private var cardioCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Cardio")
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

    private var sets: [SetLog] {
        session.sets.filter { $0.exercise == exercise }.sorted { $0.index < $1.index }
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

            ForEach(sets) { entry in
                SetRow(entry: entry)
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

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.index + 1)")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(Palette.ink)
                .frame(width: 34, alignment: .leading)
            TextField("0", value: $entry.weight, format: .number)
                .keyboardType(.decimalPad)
                .font(.body.weight(.bold))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            TextField("0", value: $entry.reps, format: .number)
                .keyboardType(.numberPad)
                .font(.body.weight(.bold))
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(Palette.card2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                entry.isDone.toggle()
                if entry.isDone { entry.date = .now }
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
