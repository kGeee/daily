import Foundation

/// Turns the app's data into day scores, streaks and the weekly recap.
@MainActor
struct ScoreBuilder {
    var planner: DayPlanner
    var food: [FoodEntry]
    var water: [WaterEntry]
    var checks: [BlockCheck]
    var events: [CustomEvent]
    var sessions: [WorkoutSession]
    var journal: [JournalEntry]

    private var cal: Calendar { Calendar.current }

    /// Timeline blocks that count toward the Day ring (meals count in Fuel, waking and winding down don't count).
    static let skippedBlocks: Set<String> = ["wake", "wind", "lunch", "dinner"]

    func inputs(for day: Date) -> ScoreInputs {
        let d = cal.startOfDay(for: day)
        let key = DayKey.of(d)
        let blocks = planner.blocks(for: d, lunchNote: nil, dinnerNote: nil, events: events)
        let countable = blocks.filter { !Self.skippedBlocks.contains($0.id) }
        let doneIDs = Set(checks.filter { $0.dayKey == key }.map(\.blockID))
        let meals = food.filter { cal.isDate($0.date, inSameDayAs: d) }
        let mainSlots = Set(meals.map(\.slot)).intersection([.breakfast, .lunch, .dinner])
        let recentCheckIns = journal.contains { $0.date > d.addingTimeInterval(-14 * 86400) && $0.date < d.addingTimeInterval(86400) }

        var inputs = ScoreInputs()
        inputs.waterOz = water.filter { cal.isDate($0.date, inSameDayAs: d) }.reduce(0) { $0 + $1.ounces }
        inputs.waterGoal = MySchedule.waterGoalOz
        inputs.workoutDone = sessions.contains { $0.finishedAt != nil && cal.isDate($0.date, inSameDayAs: d) }
        inputs.gymPlanned = blocks.contains { $0.category == .gym }
        inputs.mainMealsLogged = mainSlots.count
        inputs.protein = meals.compactMap(\.protein).reduce(0, +)
        inputs.proteinGoal = MySchedule.proteinGoal
        inputs.timelineTotal = countable.count
        inputs.timelineDone = countable.filter { doneIDs.contains($0.id) }.count
        inputs.checkedIn = journal.contains { cal.isDate($0.date, inSameDayAs: d) }
        inputs.checkInExpected = CheckIn.isOn || recentCheckIns
        return inputs
    }

    func score(for day: Date) -> DayScore { DayScore(inputs(for: day)) }

    // MARK: Streaks

    struct StreakSummary: Identifiable {
        var id: String
        var title: String
        var symbol: String
        /// "days" or "weeks"
        var unit: String
        var current: Int
        var best: Int
        var freezes: Int
        var frozen: Set<Date>
        var active: Set<Date>
    }

    static let lookbackDays = 120

    func streaks(today: Date = Date()) -> [StreakSummary] {
        let start = cal.date(byAdding: .day, value: -Self.lookbackDays, to: cal.startOfDay(for: today)) ?? today
        let days = { (dates: [Date]) in Set(dates.map { cal.startOfDay(for: $0) }) }

        let logged = days(food.map(\.date))
        let outDays = days(food.filter { $0.source == .out }.map(\.date))
        let home = days(food.filter { $0.source.isHome }.map(\.date)).subtracting(outDays)
        let checkIns = days(journal.map(\.date))
        var closed = Set<Date>()
        var d = cal.startOfDay(for: today)
        for _ in 0..<42 {
            if score(for: d).isClosed { closed.insert(d) }
            guard let prev = cal.date(byAdding: .day, value: -1, to: d) else { break }
            d = prev
        }

        func make(_ id: String, _ title: String, _ symbol: String, _ active: Set<Date>, target: Int) -> StreakSummary {
            let r = Streaks.daily(active: active, today: today, since: start, weeklyTarget: target)
            return StreakSummary(id: id, title: title, symbol: symbol, unit: "days", current: r.current, best: r.best,
                                 freezes: r.freezes, frozen: r.frozen, active: active)
        }

        var list = [
            make("log", "Log something every day", "flame.fill", logged, target: 5),
            make("home", "Eat at home", "house.fill", home, target: 5),
            make("closed", "Close all three rings", "circle.circle.fill", closed, target: 3)
        ]
        let perWeek = max(UserDefaults.standard.integer(forKey: "pref.gymPerWeek"), 0) == 0
            ? 3 : UserDefaults.standard.integer(forKey: "pref.gymPerWeek")
        let workouts = sessions.filter { $0.finishedAt != nil }.map(\.date)
        let weekly = Streaks.weekly(dates: workouts, perWeek: perWeek, today: today)
        list.insert(StreakSummary(id: "gym", title: "Gym \(perWeek)× a week", symbol: "dumbbell.fill", unit: "weeks",
                                  current: weekly.current, best: weekly.best, freezes: 0, frozen: [],
                                  active: days(workouts)), at: 2)
        if !checkIns.isEmpty || CheckIn.isOn {
            list.append(make("checkin", "Midday check-in", "camera.fill", checkIns, target: 4))
        }
        return list
    }
}
