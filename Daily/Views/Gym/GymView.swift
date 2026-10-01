import SwiftUI
import SwiftData

struct GymView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var allSets: [SetLog]

    @State private var editing: WorkoutTemplate?
    @State private var showNewTemplate = false

    private var active: WorkoutSession? { sessions.first { $0.finishedAt == nil } }
    private var upNext: String? { WorkoutTemplate.nextName(templates: templates, sessions: sessions) }

    var body: some View {
        Group {
            if let active {
                ActiveWorkoutView(session: active)
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
    }

    // MARK: Home

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(eyebrow: upNext.map { "Up next · \($0)" } ?? "Gym", title: "Gym")

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
                let doneSets = session.sets.filter { $0.isDone }.count
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
                        Text(session.cardioMinutes > 0 ? "\(minutes) min · \(session.cardioMinutes) cardio" : "\(minutes) min")
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
            let plan: [(Double, Int)] = last.isEmpty
                ? [(0, 10), (0, 10), (0, 10)]
                : last.map { ($0.weight, $0.reps) }
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
            .navigationBarTitleDisplayMode(.inline)
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
