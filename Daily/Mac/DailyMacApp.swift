#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// Daily for Mac: the same screens and data as the iPhone (synced through iCloud), in a sidebar
/// window, plus a menu bar item showing what's on now.
@main
struct DailyMacApp: App {
    var body: some Scene {
        WindowGroup("Daily", id: MacWindow.main) {
            MacRootView()
                .frame(minWidth: 900, minHeight: 620)
        }
        .modelContainer(DataStore.shared)
        .commands { DailyCommands() }

        MenuBarExtra {
            MenuBarPanel()
                .modelContainer(DataStore.shared)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(DataStore.shared)
                .frame(width: 560, height: 680)
        }
    }
}

enum MacWindow {
    static let main = "main"
}

/// Sections in the sidebar.
enum MacSection: String, CaseIterable, Identifiable {
    case today, month, commute, gym, food, journal, focus
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .month: return "Month"
        case .commute: return "Commute"
        case .gym: return "Gym"
        case .food: return "Food"
        case .journal: return "Journal"
        case .focus: return "Focus"
        }
    }

    var symbol: String {
        switch self {
        case .today: return "clock"
        case .month: return "calendar"
        case .commute: return "bus"
        case .gym: return "dumbbell"
        case .food: return "fork.knife"
        case .journal: return "book.pages"
        case .focus: return "timer"
        }
    }

    /// ⌘1…⌘7
    var shortcut: KeyEquivalent { KeyEquivalent(Character(String((MacSection.allCases.firstIndex(of: self) ?? 0) + 1))) }
}

struct MacRootView: View {
    @SceneStorage("mac.section") private var sectionRaw = MacSection.today.rawValue
    @State private var newEvent = false

    private var section: Binding<MacSection?> {
        Binding(get: { MacSection(rawValue: sectionRaw) ?? .today },
                set: { sectionRaw = ($0 ?? .today).rawValue })
    }

    var body: some View {
        NavigationSplitView {
            List(selection: section) {
                Section("Daily") {
                    ForEach(MacSection.allCases) { s in
                        Label(s.title, systemImage: s.symbol).tag(s)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarScore().padding(10) }
        } detail: {
            detail(for: section.wrappedValue ?? .today)
                .id(sectionRaw)
        }
        .tint(Palette.commute)
        .modifier(AppLifecycle())
        .focusedSceneValue(\.macSection, section)
        .focusedSceneValue(\.macNewEvent, $newEvent)
        .sheet(isPresented: $newEvent) {
            EventEditor(event: nil, defaultDay: Date())
                .frame(minWidth: 460, minHeight: 640)
        }
    }

    @ViewBuilder
    private func detail(for section: MacSection) -> some View {
        switch section {
        case .today: TodayView()
        case .month: MonthView()
        case .commute: CommuteView()
        case .gym: GymView()
        case .food: FoodView()
        case .journal: JournalView()
        case .focus: FocusView()
        }
    }
}

/// Today's score at the bottom of the sidebar.
private struct SidebarScore: View {
    @Query private var overrides: [DayTypeOverride]
    @Query private var food: [FoodEntry]
    @Query private var water: [WaterEntry]
    @Query private var checks: [BlockCheck]
    @Query private var events: [CustomEvent]
    @Query private var sessions: [WorkoutSession]
    @Query private var journal: [JournalEntry]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern

    var body: some View {
        let score = ScoreBuilder(planner: DayPlanner(pattern: pattern, overrides: overrides), food: food, water: water,
                                 checks: checks, events: events, sessions: sessions, journal: journal)
            .score(for: .now)
        HStack(spacing: 10) {
            ScoreRings(score: score, size: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(score.score) today")
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(Palette.ink)
                Text(score.hint ?? "Day closed")
                    .font(.caption2)
                    .foregroundStyle(Palette.muted)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Menu commands

struct MacSectionKey: FocusedValueKey { typealias Value = Binding<MacSection?> }
struct MacNewEventKey: FocusedValueKey { typealias Value = Binding<Bool> }

extension FocusedValues {
    var macSection: Binding<MacSection?>? {
        get { self[MacSectionKey.self] }
        set { self[MacSectionKey.self] = newValue }
    }
    var macNewEvent: Binding<Bool>? {
        get { self[MacNewEventKey.self] }
        set { self[MacNewEventKey.self] = newValue }
    }
}

struct DailyCommands: Commands {
    @FocusedValue(\.macSection) private var section
    @FocusedValue(\.macNewEvent) private var newEvent

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Event") { newEvent?.wrappedValue = true }
                .keyboardShortcut("n")
                .disabled(newEvent == nil)
        }
        CommandMenu("Go") {
            ForEach(MacSection.allCases) { s in
                Button(s.title) { section?.wrappedValue = s }
                    .keyboardShortcut(s.shortcut)
                    .disabled(section == nil)
            }
        }
    }
}
#endif
