import Foundation

/// The three rings on Today.
enum ScoreRing: String, CaseIterable, Identifiable {
    case move, fuel, day
    var id: String { rawValue }

    var title: String {
        switch self {
        case .move: return "Move"
        case .fuel: return "Fuel"
        case .day: return "Day"
        }
    }
}

/// One thing that fills a ring (partly done things count partly).
struct ScoreItem: Identifiable, Equatable {
    var ring: ScoreRing
    var title: String
    /// 0…1
    var progress: Double
    var id: String { ring.rawValue + title }
    var isDone: Bool { progress >= 0.999 }
}

/// Everything a day's score is worked out from.
struct ScoreInputs: Equatable {
    var waterOz = 0
    var waterGoal = 100
    var workoutDone = false
    var gymPlanned = false
    /// How many of breakfast, lunch and dinner have something logged.
    var mainMealsLogged = 0
    var protein = 0
    var proteinGoal = 140
    var timelineDone = 0
    var timelineTotal = 0
    var checkedIn = false
    var checkInExpected = false
}

struct DayScore: Equatable {
    var items: [ScoreItem]

    init(_ inputs: ScoreInputs) {
        var items: [ScoreItem] = []
        func fraction(_ value: Int, _ goal: Int) -> Double { goal > 0 ? min(Double(value) / Double(goal), 1) : 1 }

        items.append(ScoreItem(ring: .move, title: "Drink \(inputs.waterGoal) oz of water",
                               progress: fraction(inputs.waterOz, inputs.waterGoal)))
        if inputs.gymPlanned || inputs.workoutDone {
            items.append(ScoreItem(ring: .move, title: "Finish a workout", progress: inputs.workoutDone ? 1 : 0))
        }
        items.append(ScoreItem(ring: .fuel, title: "Log breakfast, lunch and dinner",
                               progress: fraction(inputs.mainMealsLogged, 3)))
        items.append(ScoreItem(ring: .fuel, title: "Reach \(inputs.proteinGoal)g protein",
                               progress: fraction(inputs.protein, inputs.proteinGoal)))
        if inputs.timelineTotal > 0 {
            items.append(ScoreItem(ring: .day, title: "Check off your timeline",
                                   progress: fraction(inputs.timelineDone, inputs.timelineTotal)))
        }
        if inputs.checkInExpected || inputs.checkedIn {
            items.append(ScoreItem(ring: .day, title: "Midday check-in", progress: inputs.checkedIn ? 1 : 0))
        }
        self.items = items
    }

    func items(in ring: ScoreRing) -> [ScoreItem] { items.filter { $0.ring == ring } }

    /// 0…1 for one ring (a ring with nothing in it counts as full).
    func value(_ ring: ScoreRing) -> Double {
        let list = items(in: ring)
        guard !list.isEmpty else { return 1 }
        return list.reduce(0) { $0 + $1.progress } / Double(list.count)
    }

    /// 0…100.
    var score: Int {
        let total = ScoreRing.allCases.reduce(0) { $0 + value($1) } / Double(ScoreRing.allCases.count)
        return Int((total * 100).rounded())
    }

    var isClosed: Bool { ScoreRing.allCases.allSatisfy { value($0) >= 0.999 } }

    /// The most useful next thing to do, for a nudge under the rings.
    var hint: String? {
        guard let ring = ScoreRing.allCases.min(by: { value($0) < value($1) }), value(ring) < 0.999,
              let item = items(in: ring).filter({ !$0.isDone }).min(by: { $0.progress < $1.progress }) else { return nil }
        return item.title + " to close " + ring.title
    }
}

/// Streaks that forgive a missed day now and then.
enum Streaks {
    struct Result: Equatable {
        var current: Int
        var best: Int
        var freezes: Int
        /// Days a freeze covered (so the calendar can show them).
        var frozen: Set<Date>
    }

    static let maxFreezes = 2

    /// Daily streak over `active` days (start-of-day dates). You earn a freeze each week (Mon–Sun, or the
    /// calendar's week) with at least `weeklyTarget` active days; a missed day spends one instead of breaking
    /// the streak. Today not being done yet never breaks it.
    static func daily(active: Set<Date>, today: Date, since start: Date, weeklyTarget: Int = 5,
                      calendar cal: Calendar = .current) -> Result {
        let todayStart = cal.startOfDay(for: today)
        var day = cal.startOfDay(for: start)
        var current = 0, best = 0, freezes = 0
        var frozen = Set<Date>()
        var weekActive = 0

        while day <= todayStart {
            let isActive = active.contains(day)
            if isActive {
                current += 1
                weekActive += 1
            } else if day == todayStart {
                // Still time today.
            } else if current > 0 && freezes > 0 {
                freezes -= 1
                frozen.insert(day)
            } else {
                current = 0
            }
            best = max(best, current)

            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            if cal.component(.weekday, from: next) == cal.firstWeekday {
                if weekActive >= weeklyTarget { freezes = min(freezes + 1, maxFreezes) }
                weekActive = 0
            }
            day = next
        }
        return Result(current: current, best: best, freezes: freezes, frozen: frozen)
    }

    /// Weeks in a row with at least `perWeek` workouts (this week counts once it's reached, and doesn't break it before).
    static func weekly(dates: [Date], perWeek: Int, today: Date, calendar cal: Calendar = .current) -> (current: Int, best: Int) {
        guard let thisWeek = cal.dateInterval(of: .weekOfYear, for: today) else { return (0, 0) }
        var counts: [Date: Int] = [:]
        for d in dates {
            if let w = cal.dateInterval(of: .weekOfYear, for: d)?.start { counts[w, default: 0] += 1 }
        }
        guard let earliest = counts.keys.min() else { return (0, 0) }
        var week = earliest
        var current = 0, best = 0
        while week <= thisWeek.start {
            let hit = (counts[week] ?? 0) >= perWeek
            if hit {
                current += 1
            } else if week != thisWeek.start {
                current = 0
            }
            best = max(best, current)
            guard let next = cal.date(byAdding: .weekOfYear, value: 1, to: week) else { break }
            week = next
        }
        return (current, best)
    }
}

/// Goals you can pick at the end of the Sunday recap.
enum WeekGoal: String, CaseIterable, Identifiable {
    case eatOutLess, moreWorkouts, water, closeDays
    var id: String { rawValue }
    static let key = "pref.weekGoal"

    var symbol: String {
        switch self {
        case .eatOutLess: return "house.fill"
        case .moreWorkouts: return "dumbbell.fill"
        case .water: return "drop.fill"
        case .closeDays: return "circle.circle.fill"
        }
    }
}
