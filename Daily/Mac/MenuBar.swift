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

    @MainActor
    func items(at date: Date) -> [SharedStore.Item] {
        WidgetSync.timelineItems(planner: DayPlanner(pattern: pattern, overrides: overrides), plans: plans,
                                 checks: checks, events: events, now: date, days: 2)
    }
}

/// What the menu bar shows. Worked out every 30 seconds from the timeline snapshot the app keeps
/// for widgets, so the status item itself never runs database queries.
@Observable
@MainActor
final class MenuBarModel {
    private(set) var title: String?
    private(set) var symbol = "clock"
    @ObservationIgnored private var timer: Timer?

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh(at date: Date = Date()) {
        let state = NowPlan.state(at: date, items: SharedStore.currentItems())
        let newTitle = NowPlan.menuBarTitle(for: state, at: date)
        let newSymbol = state.current?.symbol ?? state.next?.symbol ?? "clock"
        // Only touch the properties when something changed, so the status item isn't redrawn for nothing.
        if newTitle != title { title = newTitle }
        if newSymbol != symbol { symbol = newSymbol }
    }
}

/// What sits in the menu bar: an icon, plus what's on now and time left.
struct MenuBarLabel: View {
    let model: MenuBarModel

    var body: some View {
        if let title = model.title {
            Label(title, systemImage: model.symbol)
        } else {
            Image(systemName: "clock")
        }
    }
}

/// The panel that drops down from the menu bar.
struct MenuBarPanel: View {
    let model: MenuBarModel
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
        .onAppear { model.refresh() }
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
        model.refresh()
    }
}
#endif
