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
            MealPlan.self,
            WorkoutTemplate.self,
            WorkoutSession.self,
            SetLog.self
        ])
    }
}

struct RootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @Query private var events: [CustomEvent]
    @Query private var food: [FoodEntry]
    @Query private var water: [WaterEntry]
    @Query private var plans: [MealPlan]
    @Query private var checks: [BlockCheck]
    @State private var pendingImport: SharedStore.PendingImport?
    @State private var addingEvent = false
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage(Pref.revision) private var revision = 0

    /// Changes whenever anything that affects reminders changes.
    private var reminderKey: String {
        let o = overrides.map { $0.dayKey + $0.typeRaw }.sorted().joined(separator: ",")
        let e = events.map { "\($0.id)\($0.start.timeIntervalSince1970)\($0.repeatRaw)\($0.remind)\($0.title)" }
            .sorted().joined(separator: ",")
        return "\(remindersOn)|\(revision)|\(pattern)|\(o)|\(e)"
    }

    /// Changes whenever anything the widgets show changes.
    private var widgetKey: String {
        let w = water.reduce(0) { $0 + $1.ounces }
        let f = food.count
        let c = food.compactMap { $0.calories }.reduce(0, +)
        let k = checks.count
        return "\(reminderKey)|\(w)|\(f)|\(c)|\(plans.count)|\(k)"
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
        .task {
            appBecameActive()
            await refreshReminders()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                appBecameActive()
                Task { await refreshReminders() }
            } else if phase == .background {
                refreshWidgets()
            }
        }
        .onChange(of: reminderKey) { _, _ in
            Task { await refreshReminders() }
        }
        .onChange(of: widgetKey) { _, _ in
            refreshWidgets()
        }
        .sheet(item: $pendingImport) { item in
            ImportRecipeView(link: item.link, text: item.text, autoRun: true)
        }
        .sheet(isPresented: $addingEvent) {
            EventEditor(event: nil, defaultDay: Date())
        }
    }

    private func appBecameActive() {
        WidgetSync.mergePendingWater(into: context)
        WidgetSync.mergePendingChecks(into: context, existing: checks)
        if SharedStore.takeAddEventRequest() { addingEvent = true }
        if pendingImport == nil, let next = SharedStore.takePendingImports().last {
            pendingImport = next
        }
        refreshWidgets()
        Task { await WidgetSync.endFinishedCountdowns() }
    }

    private func refreshWidgets() {
        WidgetSync.update(planner: DayPlanner(pattern: pattern, overrides: overrides),
                          food: food, water: water, plans: plans, checks: checks, events: events)
    }

    private func refreshReminders() async {
        await Reminders.reschedule(enabled: remindersOn,
                                   planner: DayPlanner(pattern: pattern, overrides: overrides),
                                   events: events)
    }
}
