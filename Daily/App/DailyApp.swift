import SwiftUI
import SwiftData

@main
struct DailyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            FoodEntry.self,
            GroceryItem.self,
            Recipe.self,
            WaterEntry.self,
            BlockCheck.self,
            DayTypeOverride.self,
            CustomEvent.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            SetLog.self
        ])
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query private var overrides: [DayTypeOverride]
    @Query private var events: [CustomEvent]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @AppStorage("remindersOn") private var remindersOn = false

    /// Changes whenever anything that affects reminders changes.
    private var reminderKey: String {
        let o = overrides.map { $0.dayKey + $0.typeRaw }.sorted().joined(separator: ",")
        let e = events.map { "\($0.id)\($0.start.timeIntervalSince1970)\($0.repeatRaw)\($0.remind)\($0.title)" }
            .sorted().joined(separator: ",")
        return "\(remindersOn)|\(pattern)|\(o)|\(e)"
    }

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "clock") }
            CommuteView()
                .tabItem { Label("Commute", systemImage: "bus") }
            GymView()
                .tabItem { Label("Gym", systemImage: "dumbbell") }
            FoodView()
                .tabItem { Label("Food", systemImage: "fork.knife") }
        }
        .tint(Palette.commute)
        .task { await refreshReminders() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refreshReminders() }
            }
        }
        .onChange(of: reminderKey) { _, _ in
            Task { await refreshReminders() }
        }
    }

    private func refreshReminders() async {
        await Reminders.reschedule(enabled: remindersOn,
                                   planner: DayPlanner(pattern: pattern, overrides: overrides),
                                   events: events)
    }
}
