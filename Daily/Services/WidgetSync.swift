import Foundation
import SwiftData
import WidgetKit
import ActivityKit

/// Keeps widgets and the lock-screen countdown in step with the app's data.
enum WidgetSync {
    @MainActor
    static func update(planner: DayPlanner, food: [FoodEntry], water: [WaterEntry], plans: [MealPlan]) {
        let cal = Calendar.current
        let now = Date()
        var snapshot = SharedStore.Snapshot()
        snapshot.dayKey = SharedStore.todayKey(now)
        snapshot.dayType = planner.type(for: now)?.title

        var departures: [SharedStore.Departure] = []
        for offset in 0..<3 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            for block in planner.blocks(for: day, lunchNote: nil, dinnerNote: nil) where block.isDeparture && block.start > now {
                let leaveBy = block.leaveBy ?? block.start
                departures.append(SharedStore.Departure(
                    title: block.title,
                    subtitle: "Leave by " + leaveBy.formatted(date: .omitted, time: .shortened),
                    start: block.start, leaveBy: leaveBy, isEstimate: block.isEstimate, symbol: block.symbol))
            }
        }
        snapshot.departures = departures

        let todaysFood = food.filter { cal.isDateInToday($0.date) }
        snapshot.calories = todaysFood.compactMap { $0.calories }.reduce(0, +)
        snapshot.protein = todaysFood.compactMap { $0.protein }.reduce(0, +)
        snapshot.calorieGoal = MySchedule.calorieGoal
        snapshot.proteinGoal = MySchedule.proteinGoal
        snapshot.waterOz = water.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.ounces }
        snapshot.waterGoal = MySchedule.waterGoalOz
        snapshot.meals = plans.filter { $0.dayKey == snapshot.dayKey }
            .sorted { $0.slotRaw < $1.slotRaw }
            .map { $0.slot.title + ": " + $0.title }

        SharedStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Adds water logged from the widget into the app's history.
    @MainActor
    static func mergePendingWater(into context: ModelContext) {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        for entry in SharedStore.takePendingWater() {
            let date: Date
            if entry.dayKey == SharedStore.todayKey() {
                date = Date()
            } else if let day = formatter.date(from: entry.dayKey) {
                date = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
            } else {
                date = Date()
            }
            context.insert(WaterEntry(date: date, ounces: entry.ounces))
        }
    }

    // MARK: Live Activity

    static var canShowLiveActivities: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    static func startCountdown(title: String, subtitle: String, departure: Date, leaveBy: Date, symbol: String) async {
        guard canShowLiveActivities else { return }
        for activity in Activity<DepartureAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        let state = DepartureAttributes.ContentState(title: title, subtitle: subtitle,
                                                     departure: departure, leaveBy: leaveBy, symbol: symbol)
        let content = ActivityContent(state: state, staleDate: departure.addingTimeInterval(10 * 60))
        _ = try? Activity.request(attributes: DepartureAttributes(), content: content, pushType: nil)
    }

    static func endFinishedCountdowns() async {
        for activity in Activity<DepartureAttributes>.activities
        where activity.content.state.departure < Date().addingTimeInterval(-5 * 60) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
