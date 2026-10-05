#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// Daily for Mac: the same screens and data as the iPhone (synced through iCloud), in a sidebar
/// window, plus a menu bar item showing what's on now.
@main
struct DailyMacApp: App {
    @State private var nav = MacNavigation()
    @State private var menuBar = MenuBarModel()

    var body: some Scene {
        // One main window (re-opened from the menu bar), so the background work runs once.
        Window("Daily", id: MacWindow.main) {
            MacRootView(nav: nav)
                .frame(minWidth: 900, minHeight: 620)
        }
        .modelContainer(DataStore.shared)
        .commands { DailyCommands(nav: nav) }

        MenuBarExtra {
            MenuBarPanel(model: menuBar)
                .modelContainer(DataStore.shared)
        } label: {
            MenuBarLabel(model: menuBar)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .modelContainer(DataStore.shared)
                .frame(width: 560, height: 680)
        }
    }
}

/// Which section the window shows, and the New Event sheet. Shared by the window and the menus
/// (passed directly rather than through focused values, which rebuilt the menus on every redraw).
@Observable
@MainActor
final class MacNavigation {
    private static let key = "mac.section"

    var section: MacSection? = MacSection(rawValue: UserDefaults.standard.string(forKey: MacNavigation.key) ?? "") ?? .today {
        didSet { UserDefaults.standard.set((section ?? .today).rawValue, forKey: Self.key) }
    }
    var newEvent = false
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
    @Bindable var nav: MacNavigation

    var body: some View {
        NavigationSplitView {
            List(selection: $nav.section) {
                Section("Daily") {
                    ForEach(MacSection.allCases) { s in
                        Label(s.title, systemImage: s.symbol).tag(s)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 260)
            .safeAreaInset(edge: .bottom) { SidebarScore().padding(10) }
        } detail: {
            detail(for: nav.section ?? .today)
                .id(nav.section ?? .today)
        }
        .tint(Palette.commute)
        .modifier(AppLifecycle())
        .sheet(isPresented: $nav.newEvent) {
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

struct DailyCommands: Commands {
    let nav: MacNavigation

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Event") { nav.newEvent = true }
                .keyboardShortcut("n")
        }
        CommandMenu("Go") {
            ForEach(MacSection.allCases) { s in
                Button(s.title) { nav.section = s }
                    .keyboardShortcut(s.shortcut)
            }
        }
    }
}
#endif
