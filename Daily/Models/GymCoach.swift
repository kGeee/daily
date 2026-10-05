import Foundation

/// Kinds of cardio, with rough MET values (how hard they are compared with sitting still).
enum CardioKind: String, CaseIterable, Identifiable {
    case inclineWalk, run, bike, row, stairs, elliptical, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .inclineWalk: return "Incline walk"
        case .run: return "Run"
        case .bike: return "Bike"
        case .row: return "Row"
        case .stairs: return "Stairs"
        case .elliptical: return "Elliptical"
        case .other: return "Other"
        }
    }

    var met: Double {
        switch self {
        case .inclineWalk: return 6.0
        case .run: return 9.8
        case .bike: return 7.0
        case .row: return 7.0
        case .stairs: return 9.0
        case .elliptical: return 5.0
        case .other: return 6.0
        }
    }
}

/// Calories burned, estimated from time, effort and body weight.
enum Burn {
    static let weightKey = "pref.bodyWeight"
    /// Lifting weights, moderate to hard (with rests).
    static let strengthMET = 5.0
    static let fallbackWeightLb = 170.0

    static var bodyWeightLb: Double {
        let saved = UserDefaults.standard.double(forKey: weightKey)
        return saved > 0 ? saved : fallbackWeightLb
    }

    static var hasBodyWeight: Bool { UserDefaults.standard.double(forKey: weightKey) > 0 }

    /// kcal per minute = MET × 3.5 × kg / 200.
    static func estimate(totalMinutes: Int, cardioMinutes: Int, cardio: CardioKind?, weightLb: Double) -> Int {
        let kg = weightLb * 0.4536
        let cardioMin = Double(max(cardioMinutes, 0))
        let strengthMin = Double(max(totalMinutes - cardioMinutes, 0))
        let met = (cardio ?? .other).met
        let perMinute = { (m: Double) in m * 3.5 * kg / 200 }
        return Int((perMinute(strengthMET) * strengthMin + perMinute(met) * cardioMin).rounded())
    }

    static func estimate(for session: WorkoutSession, until end: Date? = nil, weightLb: Double = Burn.bodyWeightLb) -> Int {
        let stop = end ?? session.finishedAt ?? Date()
        let minutes = max(Int(stop.timeIntervalSince(session.date) / 60), session.cardioMinutes)
        return estimate(totalMinutes: minutes, cardioMinutes: session.cardioMinutes,
                        cardio: CardioKind(rawValue: session.cardioKindRaw), weightLb: weightLb)
    }

    /// Stored number if the workout is finished, otherwise a live estimate.
    static func calories(for session: WorkoutSession) -> Int {
        session.caloriesBurned ?? estimate(for: session)
    }
}

/// Simple progressive-overload rules for what to lift next time.
enum Coach {
    struct Target: Equatable {
        var weight: Double
        var reps: Int
        var reason: String
    }

    static let repRange = 8...10

    static func increment(for weight: Double) -> Double {
        weight < 50 ? 2.5 : 5
    }

    /// Based on the finished sets from last time.
    static func target(lastSets: [SetLog]) -> Target? {
        let done = lastSets.filter(\.isDone)
        guard let top = done.map(\.weight).max() else { return nil }
        let atTop = done.filter { $0.weight == top }
        let minReps = atTop.map(\.reps).min() ?? 0

        if top <= 0 {
            return Target(weight: 0, reps: minReps + 1, reason: "One more rep than last time")
        }
        if minReps >= repRange.upperBound {
            let next = top + increment(for: top)
            return Target(weight: next, reps: repRange.lowerBound,
                          reason: "+\(format(next - top)) lb, you hit all \(minReps)s")
        }
        if minReps >= repRange.lowerBound {
            return Target(weight: top, reps: min(minReps + 1, repRange.upperBound),
                          reason: "Same weight, aim for \(min(minReps + 1, repRange.upperBound))s")
        }
        return Target(weight: top, reps: repRange.lowerBound, reason: "Stay at \(format(top)) until you get \(repRange.lowerBound)s")
    }

    static func format(_ weight: Double) -> String {
        weight == weight.rounded() ? String(Int(weight)) : String(format: "%.1f", weight)
    }

    /// Total weight moved (weight × reps of finished sets).
    static func volume(_ sets: [SetLog]) -> Double {
        sets.filter(\.isDone).reduce(0) { $0 + $1.weight * Double($1.reps) }
    }

    /// Exercises where this session's heaviest finished set beats every earlier session.
    static func newBests(in session: WorkoutSession, allSets: [SetLog]) -> [(exercise: String, weight: Double, reps: Int)] {
        var result: [(String, Double, Int)] = []
        let mine = session.allSets.filter(\.isDone)
        for exercise in Set(mine.map(\.exercise)).sorted() {
            guard let best = mine.filter({ $0.exercise == exercise }).max(by: { $0.weight < $1.weight }), best.weight > 0
            else { continue }
            let earlier = allSets.filter {
                $0.exercise == exercise && $0.isDone && $0.session?.persistentModelID != session.persistentModelID
                    && ($0.session?.date ?? .distantFuture) < session.date
            }
            guard !earlier.isEmpty else { continue }
            if best.weight > (earlier.map(\.weight).max() ?? 0) {
                result.append((exercise, best.weight, best.reps))
            }
        }
        return result.map { (exercise: $0.0, weight: $0.1, reps: $0.2) }
    }

    /// What the AI coach gets to see: your splits, recent workouts and body weight.
    static func context(templates: [WorkoutTemplate], sessions: [WorkoutSession], weightLb: Double?, now: Date) -> String {
        var lines: [String] = []
        if let weightLb { lines.append("Body weight: \(Int(weightLb)) lb") }
        let splits = templates.sorted { $0.order < $1.order }.map { t in
            t.isCardio ? "\(t.name) (cardio)" : "\(t.name): " + t.exercises.joined(separator: ", ")
        }
        if !splits.isEmpty { lines.append("Their workout splits: " + splits.joined(separator: " | ")) }
        let recent = sessions.filter { $0.finishedAt != nil }.sorted { $0.date > $1.date }.prefix(8)
        if !recent.isEmpty {
            lines.append("Recent workouts (newest first):")
            for s in recent {
                let days = Calendar.current.dateComponents([.day], from: s.date, to: now).day ?? 0
                var parts: [String] = []
                for exercise in s.exercises {
                    let sets = s.allSets.filter { $0.exercise == exercise && $0.isDone }.sorted { $0.index < $1.index }
                    guard !sets.isEmpty else { continue }
                    parts.append(exercise + " " + sets.map { "\(format($0.weight))×\($0.reps)" }.joined(separator: ", "))
                }
                if s.cardioMinutes > 0 { parts.append("cardio \(s.cardioMinutes) min") }
                lines.append("- \(days == 0 ? "today" : "\(days)d ago") \(s.templateName): " + parts.joined(separator: "; "))
            }
        }
        return lines.joined(separator: "\n")
    }
}

/// This week at the gym.
struct GymWeek {
    var workouts: Int
    var calories: Int
    var volume: Double
    /// Calories per day, Monday first (or the calendar's first weekday).
    var daily: [(day: Date, calories: Int)]

    static func make(sessions: [WorkoutSession], now: Date) -> GymWeek {
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: now) else {
            return GymWeek(workouts: 0, calories: 0, volume: 0, daily: [])
        }
        let inWeek = sessions.filter { $0.finishedAt != nil && week.contains($0.date) }
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
        let daily = days.map { day in
            (day: day, calories: inWeek.filter { cal.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + Burn.calories(for: $1) })
        }
        return GymWeek(workouts: inWeek.count,
                       calories: inWeek.reduce(0) { $0 + Burn.calories(for: $1) },
                       volume: inWeek.reduce(0) { $0 + Coach.volume($1.allSets) },
                       daily: daily)
    }
}
