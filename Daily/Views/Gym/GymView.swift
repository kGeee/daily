import SwiftUI
import SwiftData

struct GymView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var allSets: [SetLog]

    @State private var editing: WorkoutTemplate?
    @State private var showNewTemplate = false
    @State private var showCoach = false
    @State private var finished: WorkoutSession?

    private var active: WorkoutSession? { sessions.first { $0.finishedAt == nil } }
    private var upNext: String? { WorkoutTemplate.nextName(templates: templates, sessions: sessions) }

    var body: some View {
        Group {
            if let active {
                ActiveWorkoutView(session: active) { done in finished = done }
            } else {
                home
            }
        }
        .task { seedIfNeeded() }
        .sheet(item: $editing) { template in
            TemplateEditor(template: template)
        }
        .sheet(isPresented: $showNewTemplate) {
            TemplateEditor(template: nil)
        }
        .sheet(isPresented: $showCoach) {
            CoachSheet()
        }
        .sheet(item: $finished) { session in
            WorkoutSummarySheet(session: session)
        }
    }

    // MARK: Home

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom) {
                    ScreenHeader(eyebrow: upNext.map { "Up next · \($0)" } ?? "Gym", title: "Gym")
                    Spacer()
                    Button {
                        showCoach = true
                    } label: {
                        Label("Ask coach", systemImage: "bubble.left.and.text.bubble.right.fill")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Palette.gymText)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Palette.gymTint, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                weekCard
                if let next = templates.first(where: { $0.name == upNext }) {
                    coachCard(next)
                }

                SectionLabel(text: "Start a workout")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(templates) { template in
                        templateCard(template)
                    }
                    Button {
                        showNewTemplate = true
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("+ New template")
                                .font(.subheadline.weight(.heavy))
                                .foregroundStyle(Palette.ink)
                            Text("Your own split")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .strokeBorder(Palette.faint, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        )
                    }
                    .buttonStyle(.plain)
                }
                Text("Long-press a workout to edit its exercises.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)

                history
            }
            .padding(16)
        }
        .background(Palette.bg.ignoresSafeArea())
    }

    private func templateCard(_ template: WorkoutTemplate) -> some View {
        let isNext = template.name == upNext
        let last = sessions.first { $0.templateName == template.name && $0.finishedAt != nil }

        return Button {
            start(template)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(template.name)
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(Palette.ink)
                    Spacer()
                    if isNext {
                        Text("NEXT")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(Palette.gymText)
                    }
                }
                Text(template.isCardio ? "Cardio" : "\(template.exercises.count) exercises")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Text(last.map { "Last: " + $0.date.formatted(.dateTime.month(.abbreviated).day()) } ?? "Not done yet")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Palette.faint)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(14)
            .background(isNext ? Palette.gymTint : Palette.card,
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isNext ? Palette.gym : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit exercises") { editing = template }
            Button("Delete", role: .destructive) { context.delete(template) }
        }
    }

    private var history: some View {
        let finished = Array(sessions.filter { $0.finishedAt != nil }.prefix(10))

        return VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "Recent workouts")
                .padding(.bottom, 6)
            if finished.isEmpty {
                Text("Finished workouts show up here.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.faint)
                    .padding(.vertical, 8)
            }
            ForEach(finished) { session in
                let doneSets = session.allSets.filter { $0.isDone }.count
                let minutes = Int((session.finishedAt ?? session.date).timeIntervalSince(session.date) / 60)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.templateName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(Palette.ink)
                        Text(session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(doneSets) sets")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Palette.ink)
                        Text("\(minutes) min · \(Burn.calories(for: session)) cal")
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                    }
                }
                .padding(.vertical, 10)
                .contextMenu {
                    Button("Delete", role: .destructive) { context.delete(session) }
                }
                if session.persistentModelID != finished.last?.persistentModelID {
                    Divider().overlay(Palette.line)
                }
            }
        }
        .card()
    }

    // MARK: Week and coach

    private var weekCard: some View {
        let week = GymWeek.make(sessions: sessions, now: Date())
        let maxCalories = max(week.daily.map(\.calories).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                weekStat("\(week.workouts)", "workouts", color: Palette.ink)
                weekStat(week.calories.formatted(), "cal burned", color: Palette.gymText, symbol: "flame.fill")
                weekStat(week.volume >= 1000 ? String(format: "%.1fk", week.volume / 1000) : "\(Int(week.volume))",
                         "lb moved", color: Palette.ink)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week.daily, id: \.day) { entry in
                    VStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(entry.calories > 0 ? Palette.gym : Palette.idle)
                            .frame(width: 24, height: max(4, 70 * CGFloat(entry.calories) / CGFloat(maxCalories)))
                        Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                            .font(.caption2)
                            .foregroundStyle(Calendar.current.isDateInToday(entry.day) ? Palette.gymText : Palette.muted)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
            if !Burn.hasBodyWeight {
                Text("Calories assume 170 lb. Set your weight in Settings → Goals for better numbers.")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
        }
        .card()
    }

    private func weekStat(_ value: String, _ label: String, color: Color, symbol: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Palette.gym) }
                Text(value)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(color)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func coachCard(_ template: WorkoutTemplate) -> some View {
        if !template.isCardio && !template.exercises.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Coach · today's \(template.name.lowercased())", systemImage: "bolt.fill")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(Palette.gymText)
                    .textCase(.uppercase)
                ForEach(template.exercises.prefix(4), id: \.self) { exercise in
                    let last = GymHistory.lastSets(for: exercise, excluding: nil, in: allSets)
                    let target = Coach.target(lastSets: last)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exercise).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                            Text(GymHistory.summary(last) ?? "First time: pick a weight you can do 10 times")
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer(minLength: 6)
                        if let target {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text("\(Coach.format(target.weight)) × \(target.reps)")
                                    .font(.subheadline.weight(.heavy))
                                    .foregroundStyle(Palette.gymText)
                                Text(target.reason)
                                    .font(.caption2)
                                    .foregroundStyle(Palette.muted)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Button {
                    start(template)
                } label: {
                    Label("Start \(template.name)", systemImage: "play.fill")
                        .font(.headline)
                        .foregroundStyle(Palette.onAccent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(Palette.gym, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
            .card(fill: Palette.gymTint)
        }
    }

    // MARK: Actions

    private func seedIfNeeded() {
        guard templates.isEmpty else { return }
        for (i, starter) in WorkoutTemplate.starters.enumerated() {
            context.insert(WorkoutTemplate(name: starter.name, order: i,
                                           exercises: starter.exercises, isCardio: starter.isCardio))
        }
    }

    private func start(_ template: WorkoutTemplate) {
        let session = WorkoutSession(templateName: template.name, exercises: template.exercises)
        context.insert(session)
        for exercise in template.exercises {
            let last = GymHistory.lastSets(for: exercise, excluding: nil, in: allSets)
            let plan: [(Double, Int)]
            if let target = Coach.target(lastSets: last) {
                plan = Array(repeating: (target.weight, target.reps), count: max(last.count, 3))
            } else if !last.isEmpty {
                plan = last.map { ($0.weight, $0.reps) }
            } else {
                plan = [(0, 10), (0, 10), (0, 10)]
            }
            for (index, entry) in plan.enumerated() {
                let log = SetLog(exercise: exercise, index: index, weight: entry.0, reps: entry.1)
                context.insert(log)
                log.session = session
            }
        }
    }
}

// MARK: - Template editor

struct TemplateEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var templates: [WorkoutTemplate]

    let template: WorkoutTemplate?

    @State private var name: String
    @State private var exercises: [String]
    @State private var isCardio: Bool
    @State private var newExercise = ""

    init(template: WorkoutTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _exercises = State(initialValue: template?.exercises ?? [])
        _isCardio = State(initialValue: template?.isCardio ?? false)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Back)", text: $name)
                    Toggle("Cardio only", isOn: $isCardio)
                }
                if !isCardio {
                    Section {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { _, exercise in
                            Text(exercise)
                        }
                        .onDelete { exercises.remove(atOffsets: $0) }
                        HStack {
                            TextField("Add exercise", text: $newExercise)
                                .onSubmit(addExercise)
                            Button("Add", action: addExercise)
                                .disabled(newExercise.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    } header: {
                        Text("Exercises")
                    } footer: {
                        Text("Swipe left on an exercise to remove it.")
                    }
                }
            }
            .navigationTitle(template == nil ? "New workout" : "Edit workout")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addExercise() {
        let trimmed = newExercise.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        exercises.append(trimmed)
        newExercise = ""
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let list = isCardio ? [] : exercises
        if let template {
            template.name = trimmedName
            template.exercises = list
            template.isCardio = isCardio
        } else {
            let nextOrder = (templates.map { $0.order }.max() ?? -1) + 1
            context.insert(WorkoutTemplate(name: trimmedName, order: nextOrder, exercises: list, isCardio: isCardio))
        }
        dismiss()
    }
}
