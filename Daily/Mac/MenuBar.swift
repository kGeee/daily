#if os(macOS)
import SwiftUI
import SwiftData
import AppKit

/// Shared by the menu bar label and panel: today's timeline items, straight from the database.
private struct NowSource {
    var overrides: [DayTypeOverride]
    var plans: [MealPlan]
    var checks: [BlockCheck]
    var events: [CustomEvent]
    var pattern: String

    func items(at date: Date) -> [SharedStore.Item] {
        WidgetSync.timelineItems(planner: DayPlanner(pattern: pattern, overrides: overrides), plans: plans,
                                 checks: checks, events: events, now: date, days: 2)
    }
}

/// What sits in the menu bar: an icon, plus what's on now and time left.
struct MenuBarLabel: View {
    var body: some View {
        MenuBarLabelContent()
            .modelContainer(DataStore.shared)
    }
}

private struct MenuBarLabelContent: View {
    @Query private var overrides: [DayTypeOverride]
    @Query private var plans: [MealPlan]
    @Query private var checks: [BlockCheck]
    @Query private var events: [CustomEvent]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let source = NowSource(overrides: overrides, plans: plans, checks: checks, events: events, pattern: pattern)
            let state = NowPlan.state(at: tl.date, items: source.items(at: tl.date))
            if let title = NowPlan.menuBarTitle(for: state, at: tl.date) {
                Label(title, systemImage: state.current?.symbol ?? state.next?.symbol ?? "clock")
            } else {
                Image(systemName: "clock")
            }
        }
    }
}

/// The panel that drops down from the menu bar.
struct MenuBarPanel: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query private var overrides: [DayTypeOverride]
    @Query private var plans: [MealPlan]
    @Query private var checks: [BlockCheck]
    @Query private var events: [CustomEvent]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { tl in
            let source = NowSource(overrides: overrides, plans: plans, checks: checks, events: events, pattern: pattern)
            let items = source.items(at: tl.date)
            let state = NowPlan.state(at: tl.date, items: items)
            VStack(alignment: .leading, spacing: 12) {
                if let current = state.current {
                    nowRow(current, at: tl.date)
                } else {
                    Text("Nothing on right now")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                }
                Divider()
                let upcoming = items.filter { $0.start > tl.date && !$0.done && Calendar.current.isDateInToday($0.start) }.prefix(4)
                if upcoming.isEmpty {
                    Text("Nothing else today")
                        .font(.subheadline)
                        .foregroundStyle(Palette.muted)
                } else {
                    ForEach(Array(upcoming)) { item in
                        upcomingRow(item)
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    panelButton("+8 oz water", symbol: "drop.fill", tint: Palette.water) {
                        context.insert(WaterEntry(date: Date(), ounces: 8))
                    }
                    panelButton("Open Daily", symbol: "macwindow", tint: Palette.commute) {
                        openWindow(id: MacWindow.main)
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                HStack {
                    Spacer()
                    Button("Quit Daily") { NSApp.terminate(nil) }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
            }
            .padding(14)
            .frame(width: 320)
        }
    }

    private func nowRow(_ item: SharedStore.Item, at date: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: item.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.commute)
                    .frame(width: 36, height: 36)
                    .background(Palette.circle, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text(NowPlan.leftLabel(minutes: NowPlan.minutesLeft(in: item, at: date)))
                        .font(.caption)
                        .foregroundStyle(Palette.muted)
                }
                Spacer()
                Button("Done") { markDone(item) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            ProgressView(value: NowPlan.progress(of: item, at: date))
                .tint(Palette.commute)
        }
    }

    private func upcomingRow(_ item: SharedStore.Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.symbol)
                .foregroundStyle(Palette.muted)
                .frame(width: 22)
            Text(item.title)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .lineLimit(1)
            Spacer()
            Text(item.start.formatted(date: .omitted, time: .shortened))
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
    }

    private func panelButton(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 30)
        }
        .buttonStyle(.bordered)
        .tint(tint)
    }

    private func markDone(_ item: SharedStore.Item) {
        guard !checks.contains(where: { $0.dayKey == item.dayKey && $0.blockID == item.blockID }) else { return }
        context.insert(BlockCheck(dayKey: item.dayKey, blockID: item.blockID))
    }
}
#endif
