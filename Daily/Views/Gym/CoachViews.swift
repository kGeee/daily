import SwiftUI
import SwiftData

/// What the AI coach answers with: advice, and optionally a workout you can start.
struct CoachReply: Decodable {
    struct Exercise: Decodable, Hashable {
        var name: String
        var sets: Int
        var reps: Int
        var weight: Double?
        var note: String?
    }
    struct Workout: Decodable, Hashable {
        var name: String
        var exercises: [Exercise]
    }
    var answer: String
    var workout: Workout?
}

enum CoachAI {
    static func ask(_ question: String, history: [(question: String, answer: String)], context: String,
                    now: Date = Date()) async throws -> CoachReply {
        var lines = [
            "You're a friendly, practical personal trainer inside a fitness app. Be brief (under 120 words), specific and safe.",
            "Use their history to pick weights (progressive overload: add 5 lb once they hit the top of their rep range).",
            "If they ask for a workout, or one clearly helps, include `workout` with 3–6 exercises, sets, reps and a weight in lb when you can guess it from their history (omit weight for bodyweight moves). Otherwise leave workout out.",
            "If something sounds like an injury, suggest easing off and seeing a professional rather than training through pain.",
            "It's \(now.formatted(.dateTime.weekday(.wide).hour().minute())).",
            "",
            context
        ]
        if !history.isEmpty {
            lines.append("")
            lines.append("Conversation so far:")
            for turn in history.suffix(4) {
                lines.append("Them: " + turn.question)
                lines.append("You: " + turn.answer)
            }
        }
        lines.append("")
        lines.append("Them: " + question)

        let exercise: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
                "sets": ["type": "integer"],
                "reps": ["type": "integer"],
                "weight": ["type": "number", "description": "pounds"],
                "note": ["type": "string"]
            ] as [String: Any],
            "required": ["name", "sets", "reps"]
        ]
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "answer": ["type": "string"],
                "workout": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string", "description": "Short, e.g. '45-min legs'"],
                        "exercises": ["type": "array", "items": exercise] as [String: Any]
                    ] as [String: Any],
                    "required": ["name", "exercises"]
                ] as [String: Any]
            ] as [String: Any],
            "required": ["answer"]
        ]
        return try await AIClient.structured(prompt: lines.joined(separator: "\n"), toolName: "coach_reply",
                                             toolDescription: "Your reply to them", schema: schema,
                                             as: CoachReply.self, maxTokens: 1500)
    }
}

/// Chat with an AI personal trainer that knows your workouts.
struct CoachSheet: View {
    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var reply: CoachReply?
        var error: String?
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]

    @StateObject private var speech = SpeechRecognizer()
    @State private var turns: [Turn] = []
    @State private var asking = false

    private let suggestions = [
        "What should I do today?",
        "I only have 40 minutes",
        "Make me a push day",
        "How do I break my bench plateau?"
    ]

    init() {}

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            SectionLabel(text: "AI coach", color: Palette.gymText)
                            Text("Ask your coach")
                                .font(.system(size: 26, weight: .heavy))
                                .foregroundStyle(Palette.ink)
                            Text("Knows your splits, recent lifts and weight.")
                                .font(.subheadline)
                                .foregroundStyle(Palette.muted)
                        }
                        if turns.isEmpty {
                            ForEach(suggestions, id: \.self) { s in
                                Button { send(s) } label: {
                                    Text(s)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Palette.ink)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 10)
                                        .background(Palette.card, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        ForEach(turns) { turn in
                            turnView(turn).id(turn.id)
                        }
                        if asking {
                            ProgressView().padding(.leading, 8)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: turns.count) { _, _ in
                    if let last = turns.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            .background(Palette.bg.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { inputBar }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { speech.stop(); dismiss() }
                }
            }
        }
    }

    private func turnView(_ turn: Turn) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer(minLength: 50)
                Text(turn.question)
                    .font(.subheadline)
                    .foregroundStyle(Palette.onAccent)
                    .padding(12)
                    .background(Palette.commute, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            if let reply = turn.reply {
                Text(reply.answer)
                    .font(.subheadline)
                    .foregroundStyle(Palette.ink)
                    .padding(14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.trailing, 30)
                if let workout = reply.workout, !workout.exercises.isEmpty {
                    workoutCard(workout)
                }
            } else if let error = turn.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Palette.gymText)
            }
        }
    }

    private func workoutCard(_ workout: CoachReply.Workout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(workout.name.uppercased())
                .font(.caption.weight(.heavy))
                .foregroundStyle(Palette.gymText)
            ForEach(workout.exercises, id: \.self) { ex in
                HStack(alignment: .firstTextBaseline) {
                    Text(ex.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink)
                    Spacer()
                    Text("\(ex.sets) × \(ex.reps)" + (ex.weight.map { " · \(Coach.format($0)) lb" } ?? ""))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.muted)
                }
            }
            Button {
                start(workout)
            } label: {
                Label("Start this workout", systemImage: "play.fill")
                    .font(.headline)
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(Palette.gym, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(16)
        .background(Palette.gymTint, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask anything…", text: $speech.transcript, axis: .vertical)
                .lineLimit(1...4)
                .submitLabel(.send)
                .onSubmit { send(speech.transcript) }
            Button {
                speech.toggle()
            } label: {
                Image(systemName: speech.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(speech.isListening ? Palette.onAccent : Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(speech.isListening ? Palette.danger : Palette.card2, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(speech.isListening ? "Stop listening" : "Speak")
            Button {
                send(speech.transcript)
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(Palette.onAccent)
                    .frame(width: 36, height: 36)
                    .background(Palette.gym, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(asking || speech.transcript.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.leading, 16)
        .padding(.trailing, 7)
        .padding(.vertical, 7)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .background(Palette.bg)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !asking else { return }
        speech.stop()
        speech.transcript = ""
        let history = turns.compactMap { t in t.reply.map { (question: t.question, answer: $0.answer) } }
        let weight: Double? = Burn.hasBodyWeight ? Burn.bodyWeightLb : nil
        let summary = Coach.context(templates: templates, sessions: sessions, weightLb: weight, now: Date())
        turns.append(Turn(question: question))
        let index = turns.count - 1
        asking = true
        Task {
            do {
                turns[index].reply = try await CoachAI.ask(question, history: history, context: summary)
            } catch {
                turns[index].error = error.localizedDescription
            }
            asking = false
        }
    }

    private func start(_ workout: CoachReply.Workout) {
        if let running = sessions.first(where: { $0.finishedAt == nil }) {
            context.delete(running)
        }
        let session = WorkoutSession(templateName: workout.name, exercises: workout.exercises.map(\.name))
        context.insert(session)
        for ex in workout.exercises {
            for index in 0..<max(ex.sets, 1) {
                let log = SetLog(exercise: ex.name, index: index, weight: ex.weight ?? 0, reps: max(ex.reps, 1))
                context.insert(log)
                log.session = session
            }
        }
        speech.stop()
        dismiss()
    }
}

/// Shown after you finish a workout.
struct WorkoutSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allSets: [SetLog]
    @Bindable var session: WorkoutSession

    var body: some View {
        let minutes = Int(((session.finishedAt ?? Date()).timeIntervalSince(session.date) / 60).rounded())
        let done = session.sets.filter(\.isDone)
        let bests = Coach.newBests(in: session, allSets: allSets)
        ScrollView {
            VStack(spacing: 14) {
                VStack(spacing: 8) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Palette.gym)
                        .frame(width: 72, height: 72)
                        .background(Palette.gymTint, in: Circle())
                    Text("\(session.templateName) done")
                        .font(.system(size: 26, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Text(timeRange)
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 24)

                HStack(spacing: 10) {
                    tile("\(minutes) min", "duration", Palette.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 2) {
                            TextField("0", value: Binding(
                                get: { session.caloriesBurned ?? 0 },
                                set: { session.caloriesBurned = $0 }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(Palette.gymText)
                            .fixedSize()
                            Image(systemName: "pencil").font(.caption).foregroundStyle(Palette.faint)
                        }
                        Text("cal burned").font(.caption).foregroundStyle(Palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                HStack(spacing: 10) {
                    tile("\(done.count)", "sets", Palette.ink)
                    tile("\(Int(Coach.volume(done)).formatted()) lb", "volume", Palette.ink)
                }
                if !bests.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel(text: "New bests")
                        ForEach(bests, id: \.exercise) { best in
                            HStack {
                                Image(systemName: "trophy.fill").foregroundStyle(Palette.gym)
                                Text(best.exercise).font(.subheadline.weight(.bold)).foregroundStyle(Palette.ink)
                                Spacer()
                                Text("\(Coach.format(best.weight)) lb × \(best.reps)")
                                    .font(.subheadline.weight(.bold))
                                    .foregroundStyle(Palette.gymText)
                            }
                        }
                    }
                    .card()
                }
                Text("Calories are an estimate from your weight (\(Int(Burn.bodyWeightLb)) lb) and time lifting vs. on cardio. Tap the number to change it.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()
                DetailPrimaryButton(title: "Done", fill: Palette.gym) { dismiss() }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Palette.bg.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private var timeRange: String {
        let day = session.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let start = session.date.formatted(date: .omitted, time: .shortened)
        let end = (session.finishedAt ?? Date()).formatted(date: .omitted, time: .shortened)
        return day + " · " + start + " – " + end
    }

    private func tile(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
