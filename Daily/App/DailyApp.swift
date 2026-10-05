import SwiftUI
import SwiftData

#if os(iOS)
@main
struct DailyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(DataStore.shared)
    }
}
#endif

/// The iPhone app: tabs, plus everything that runs in the background.
struct RootView: View {
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
            FocusView()
                .tabItem { Label("Focus", systemImage: "timer") }
        }
        .tint(Palette.commute)
        .modifier(AppLifecycle())
    }
}

/// Work shared by the iPhone and Mac windows: merging widget taps, keeping widgets, reminders and the
/// Lock Screen up to date, cleaning sync duplicates, shared imports, and first-run setup.
struct AppLifecycle: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @Query private var events: [CustomEvent]
    @Query private var food: [FoodEntry]
    @Query private var water: [WaterEntry]
    @Query private var plans: [MealPlan]
    @Query private var checks: [BlockCheck]
    @State private var pendingImport: SharedStore.PendingImport?
    @State private var pendingInvite: EventEditor.ImportLink?
    @State private var addingEvent = false
    @State private var showSetup = Setup.needsSetup()
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

    func body(content: Content) -> some View {
        content
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
        .sheet(item: $pendingInvite) { item in
            ImportEventSheet(link: item.url, text: item.text)
        }
        .sheet(isPresented: $addingEvent) {
            EventEditor(event: nil, defaultDay: Date())
        }
        .fullScreenSheet(isPresented: $showSetup) {
            SetupView {
                UserDefaults.standard.set(true, forKey: Setup.doneKey)
                showSetup = false
            }
        }
    }

    private func appBecameActive() {
        WidgetSync.mergePendingWater(into: context)
        WidgetSync.mergePendingChecks(into: context, existing: checks)
        FocusController.settle(context: context)
        Dedupe.run(in: context)
        if SharedStore.takeAddEventRequest() { addingEvent = true }
        if pendingImport == nil, pendingInvite == nil, let next = SharedStore.takePendingImports().last {
            // Invites (Partiful, Luma…) become events; anything else goes to the recipe importer.
            let link = next.link.isEmpty ? EventImporter.firstLink(in: next.text) ?? "" : next.link
            if EventImporter.isEventLink(link) {
                pendingInvite = EventEditor.ImportLink(url: link, text: next.text)
            } else {
                pendingImport = next
            }
        }
        refreshWidgets()
        Task { await WidgetSync.endFinishedCountdowns() }
        Task { await CheckIn.updateReminder() }
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
