import SwiftUI
import SwiftData
import Charts

/// A look back at one week: eating out, nutrition, gym, water and commute check-offs,
/// plus a 6-week trend.
struct WeekReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var food: [FoodEntry]
    @Query private var water: [WaterEntry]
    @Query private var sessions: [WorkoutSession]
    @Query private var checks: [BlockCheck]
    @Query private var overrides: [DayTypeOverride]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern

    @State private var weeksBack: Int

    init(startOnLastWeek: Bool = false) {
        _weeksBack = State(initialValue: startOnLastWeek ? 1 : 0)
    }

    private let cal = Calendar.current

    private func interval(weeksBack: Int) -> DateInterval? {
        guard let current = cal.dateInterval(of: .weekOfYear, for: Date()),
              let start = cal.date(byAdding: .weekOfYear, value: -weeksBack, to: current.start),
              let end = cal.date(byAdding: .day, value: 7, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    private struct Stats {
        var home = 0
        var out = 0
        var loggedDays = 0
        var avgCalories = 0
        var avgProtein = 0
        var proteinDays = 0
        var gymPlanned = 0
        var gymDone = 0
        var setsDone = 0
        var cardioMinutes = 0
        var avgWater = 0
        var waterDays = 0
        var departuresPlanned = 0
        var departuresDone = 0
    }

    private func stats(for week: DateInterval) -> Stats {
        var s = Stats()
        let meals = food.filter { week.contains($0.date) }
        s.home = meals.filter { $0.source.isHome }.count
        s.out = meals.count - s.home

        let byDay = Dictionary(grouping: meals) { cal.startOfDay(for: $0.date) }
        s.loggedDays = byDay.count
        let dayCalories = byDay.values.map { $0.compactMap { $0.calories }.reduce(0, +) }.filter { $0 > 0 }
        let dayProtein = byDay.values.map { $0.compactMap { $0.protein }.reduce(0, +) }.filter { $0 > 0 }
        s.avgCalories = dayCalories.isEmpty ? 0 : dayCalories.reduce(0, +) / dayCalories.count
        s.avgProtein = dayProtein.isEmpty ? 0 : dayProtein.reduce(0, +) / dayProtein.count
        s.proteinDays = dayProtein.filter { $0 >= MySchedule.proteinGoal }.count

        let planner = DayPlanner(pattern: pattern, overrides: overrides)
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
            .filter { $0 <= Date() }
        s.gymPlanned = days.filter { planner.type(for: $0) == .gym }.count
        let weekSessions = sessions.filter { week.contains($0.date) && $0.finishedAt != nil }
        s.gymDone = weekSessions.count
        s.setsDone = weekSessions.reduce(0) { $0 + $1.allSets.filter { $0.isDone }.count }
        s.cardioMinutes = weekSessions.reduce(0) { $0 + $1.cardioMinutes }

        let waterByDay = Dictionary(grouping: water.filter { week.contains($0.date) }) { cal.startOfDay(for: $0.date) }
            .mapValues { $0.reduce(0) { $0 + $1.ounces } }
        s.avgWater = waterByDay.isEmpty ? 0 : waterByDay.values.reduce(0, +) / waterByDay.count
        s.waterDays = waterByDay.values.filter { $0 >= MySchedule.waterGoalOz }.count

        for day in days {
            let ids = planner.blocks(for: day, lunchNote: nil, dinnerNote: nil).filter { $0.isDeparture }.map { $0.id }
            s.departuresPlanned += ids.count
            let key = DayKey.of(day)
            s.departuresDone += checks.filter { $0.dayKey == key && ids.contains($0.blockID) }.count
        }
        return s
    }

    private struct TrendPoint: Identifiable {
        let id: Int
        let label: String
        let out: Int
        let protein: Int
    }

    private var trend: [TrendPoint] {
        (0..<6).reversed().compactMap { back in
            guard let week = interval(weeksBack: back) else { return nil }
            let s = stats(for: week)
            return TrendPoint(id: back, label: week.start.formatted(.dateTime.month(.abbreviated).day()),
                              out: s.out, protein: s.avgProtein)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PillSegment([0, 1], selection: $weeksBack) { $0 == 0 ? "This week" : "Last week" }

                    if let week = interval(weeksBack: weeksBack) {
                        let s = stats(for: week)
                        headline(s)
                        eatingCard(s)
                        gymCard(s)
                        habitsCard(s)
                    }
                    trendCard
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("Week in review")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func headline(_ s: Stats) -> some View {
        let wins = [
            s.out <= MySchedule.eatOutGoalPerWeek ? "Ate out \(s.out)× (goal ≤\(MySchedule.eatOutGoalPerWeek))" : nil,
            s.gymPlanned > 0 && s.gymDone >= s.gymPlanned ? "Hit every gym day" : nil,
            s.proteinDays >= 4 ? "Protein goal on \(s.proteinDays) days" : nil,
            s.waterDays >= 4 ? "Water goal on \(s.waterDays) days" : nil
        ].compactMap { $0 }
        let focus = [
            s.out > MySchedule.eatOutGoalPerWeek ? "Ate out \(s.out)×, \(s.out - MySchedule.eatOutGoalPerWeek) over goal. Plan a few more prepped lunches." : nil,
            s.gymPlanned > s.gymDone ? "\(s.gymPlanned - s.gymDone) gym day\(s.gymPlanned - s.gymDone == 1 ? "" : "s") missed." : nil,
            s.loggedDays < 4 ? "Only \(s.loggedDays) day\(s.loggedDays == 1 ? "" : "s") of meals logged. Totals are partial." : nil
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 8) {
            if !wins.isEmpty {
                SectionLabel(text: "Going well", color: Palette.foodText)
                ForEach(wins, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                }
            }
            if !focus.isEmpty {
                SectionLabel(text: "To work on", color: Palette.gymText)
                    .padding(.top, wins.isEmpty ? 0 : 6)
                ForEach(focus, id: \.self) { line in
                    Label(line, systemImage: "arrow.right.circle")
                        .font(.subheadline)
                        .foregroundStyle(Palette.ink)
                }
            }
            if wins.isEmpty && focus.isEmpty {
                Text("Not much logged yet this week.")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            }
        }
        .card()
    }

    private func stat(_ value: String, _ label: String, _ color: Color = Palette.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.heavy)).foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eatingCard(_ s: Stats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Eating")
            HStack {
                stat("\(s.home)", "meals at home", Palette.food)
                stat("\(s.out)", "eaten out", s.out > MySchedule.eatOutGoalPerWeek ? Palette.gym : Palette.ink)
            }
            HStack {
                stat(s.avgCalories > 0 ? s.avgCalories.formatted() : "—", "avg cal / day (goal \(MySchedule.calorieGoal.formatted()))")
                stat(s.avgProtein > 0 ? "\(s.avgProtein)g" : "—", "avg protein (goal \(MySchedule.proteinGoal)g)")
            }
        }
        .card()
    }

    private func gymCard(_ s: Stats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Gym")
            HStack {
                stat("\(s.gymDone)/\(max(s.gymPlanned, s.gymDone))", "workouts", Palette.gymText)
                stat("\(s.setsDone)", "sets")
                stat("\(s.cardioMinutes)", "cardio min")
            }
        }
        .card()
    }

    private func habitsCard(_ s: Stats) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Habits")
            HStack {
                stat(s.avgWater > 0 ? "\(s.avgWater) oz" : "—", "avg water / day", Palette.waterText)
                stat("\(s.departuresDone)/\(s.departuresPlanned)", "departures checked off", Palette.commuteText)
            }
        }
        .card()
    }

    private var trendCard: some View {
        let points = trend
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Eating out · last 6 weeks")
            Chart(points) { point in
                BarMark(x: .value("Week", point.label), y: .value("Meals out", point.out))
                    .foregroundStyle(point.out > MySchedule.eatOutGoalPerWeek ? Palette.gym : Palette.food)
                    .cornerRadius(4)
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 140)
            Text("Green weeks are at or under your goal of \(MySchedule.eatOutGoalPerWeek).")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .card()
    }
}
