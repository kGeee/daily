import Foundation
import SwiftData

@Model
final class WorkoutTemplate {
    var name: String = ""
    var order: Int = 0
    var exercisesRaw: String = ""
    var isCardio: Bool = false

    init(name: String, order: Int, exercises: [String], isCardio: Bool = false) {
        self.name = name
        self.order = order
        self.exercisesRaw = exercises.joined(separator: "\n")
        self.isCardio = isCardio
    }

    var exercises: [String] {
        get { exercisesRaw.split(separator: "\n").map(String.init) }
        set { exercisesRaw = newValue.joined(separator: "\n") }
    }

    /// Templates created the first time the Gym tab opens. Edit them in the app.
    static let starters: [(name: String, exercises: [String], isCardio: Bool)] = [
        ("Back", ["Lat pulldown", "Seated cable row", "One-arm dumbbell row", "Face pull", "Bicep curl"], false),
        ("Chest", ["Bench press", "Incline dumbbell press", "Cable fly", "Tricep pushdown"], false),
        ("Legs", ["Squat", "Romanian deadlift", "Leg press", "Calf raise"], false),
        ("Cardio", [], true)
    ]

    /// The strength template after the last one you finished, so days rotate Back → Chest → Legs.
    static func nextName(templates: [WorkoutTemplate], sessions: [WorkoutSession]) -> String? {
        let strength = templates.filter { !$0.isCardio }.sorted { $0.order < $1.order }
        guard !strength.isEmpty else { return nil }
        let finished = sessions.filter { $0.finishedAt != nil }.sorted { $0.date > $1.date }
        if let last = finished.first,
           let index = strength.firstIndex(where: { $0.name == last.templateName }) {
            return strength[(index + 1) % strength.count].name
        }
        return strength.first?.name
    }
}

@Model
final class WorkoutSession {
    var date: Date = Date()
    var templateName: String = ""
    var exercisesRaw: String = ""
    var finishedAt: Date? = nil
    var cardioMinutes: Int = 0
    var cardioNote: String = ""
    var cardioKindRaw: String = ""
    /// Saved when you finish (and editable); nil while the workout is going.
    var caloriesBurned: Int? = nil
    /// Optional because iCloud sync requires it; read through `allSets`.
    @Relationship(deleteRule: .cascade, inverse: \SetLog.session) var sets: [SetLog]? = []

    init(templateName: String, exercises: [String]) {
        self.date = .now
        self.templateName = templateName
        self.exercisesRaw = exercises.joined(separator: "\n")
        self.finishedAt = nil
        self.cardioMinutes = 0
        self.cardioNote = ""
    }

    var exercises: [String] {
        exercisesRaw.split(separator: "\n").map(String.init)
    }

    var allSets: [SetLog] { sets ?? [] }
}

@Model
final class SetLog {
    var exercise: String = ""
    var index: Int = 0
    var weight: Double = 0
    var reps: Int = 0
    var isDone: Bool = false
    var date: Date = Date()
    var session: WorkoutSession?

    init(exercise: String, index: Int, weight: Double, reps: Int) {
        self.exercise = exercise
        self.index = index
        self.weight = weight
        self.reps = reps
        self.isDone = false
        self.date = .now
    }
}

enum GymHistory {
    /// The completed sets from the most recent earlier workout that included this exercise.
    static func lastSets(for exercise: String, excluding current: PersistentIdentifier?, in all: [SetLog]) -> [SetLog] {
        let prior = all.filter { set in
            guard set.exercise == exercise, set.isDone, let session = set.session else { return false }
            return session.persistentModelID != current
        }
        guard let latest = prior.max(by: { $0.date < $1.date }),
              let latestSession = latest.session else { return [] }
        return prior
            .filter { $0.session?.persistentModelID == latestSession.persistentModelID }
            .sorted { $0.index < $1.index }
    }

    static func summary(_ sets: [SetLog]) -> String? {
        guard let top = sets.max(by: { $0.weight < $1.weight }) else { return nil }
        return "Last: \(sets.count) sets · top \(top.weight.formatted()) lb × \(top.reps)"
    }
}
