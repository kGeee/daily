import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// MARK: - Now widget (what you're doing and how much time is left)

struct NowEntry: TimelineEntry {
    let date: Date
    let state: NowPlan.State
    /// The next few things after the current one.
    let upcoming: [SharedStore.Item]
}

struct NowProvider: TimelineProvider {
    func placeholder(in context: Context) -> NowEntry {
        let now = Date()
        let work = SharedStore.Item(blockID: "work", dayKey: "", title: "Work", subtitle: "",
                                    start: now.addingTimeInterval(-3600), end: now.addingTimeInterval(5400),
                                    symbol: "briefcase.fill", category: "work", done: false)
        let gym = SharedStore.Item(blockID: "gym", dayKey: "", title: "Gym", subtitle: "Push day",
                                   start: now.addingTimeInterval(7200), end: now.addingTimeInterval(11000),
                                   symbol: "dumbbell.fill", category: "gym", done: false)
        return NowEntry(date: now, state: NowPlan.State(current: work, next: gym), upcoming: [gym])
    }

    func getSnapshot(in context: Context, completion: @escaping (NowEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : entry(at: Date(), items: SharedStore.currentItems()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowEntry>) -> Void) {
        let now = Date()
        let items = SharedStore.currentItems()
        // A new entry every time something starts or ends; the countdowns tick on their own in between.
        let dates = [now] + NowPlan.changeDates(after: now, items: items).prefix(30)
        let entries = dates.map { entry(at: $0, items: items) }
        let policy: TimelineReloadPolicy = dates.count > 1 ? .atEnd : .after(now.addingTimeInterval(3600))
        completion(Timeline(entries: entries, policy: policy))
    }

    private func entry(at date: Date, items: [SharedStore.Item]) -> NowEntry {
        let state = NowPlan.state(at: date, items: items)
        let upcoming = items.filter { !$0.done && $0.start > date }.sorted { $0.start < $1.start }
        return NowEntry(date: date, state: state, upcoming: Array(upcoming.prefix(3)))
    }
}

struct NowWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NowEntry

    var body: some View {
        switch family {
        case .accessoryRectangular:
            rectangular.containerBackground(.clear, for: .widget)
        case .accessoryCircular:
            circular.containerBackground(.clear, for: .widget)
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                main
                VStack(alignment: .leading, spacing: 8) {
                    Text("THEN")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white.opacity(0.5))
                    ForEach(laterItems.prefix(3), id: \.id) { item in
                        HStack(spacing: 8) {
                            Circle().fill(item.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(item.title).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                                Text(item.start.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2).foregroundStyle(.white.opacity(0.55))
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: 112, alignment: .leading)
            }
            .containerBackground(Color.widgetDark, for: .widget)
        default:
            main.containerBackground(Color.widgetDark, for: .widget)
        }
    }

    /// Items for the "Then" column (skips the one already shown as "up next").
    private var laterItems: [SharedStore.Item] {
        entry.state.current == nil ? Array(entry.upcoming.dropFirst()) : entry.upcoming
    }

    @ViewBuilder
    private var main: some View {
        if let current = entry.state.current {
            let end = NowPlan.end(of: current)
            VStack(alignment: .leading, spacing: 4) {
                header(current, label: "NOW")
                Spacer(minLength: 0)
                Text(current.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(timerInterval: current.start...end, countsDown: true)
                    .font(.system(size: 26, weight: .heavy).monospacedDigit())
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                ProgressView(timerInterval: current.start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(current.color)
                Text("until " + end.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else if let next = entry.state.next {
            VStack(alignment: .leading, spacing: 4) {
                header(next, label: "UP NEXT")
                Spacer(minLength: 0)
                Text(next.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if Calendar.current.isDate(next.start, inSameDayAs: entry.date) {
                    Text(timerInterval: entry.date...next.start, countsDown: true)
                        .font(.system(size: 26, weight: .heavy).monospacedDigit())
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                    Text("free until " + next.start.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    Text(next.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text("NOW")
                    .font(.caption2.weight(.heavy))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
                Text("All clear")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Open Daily to refresh")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func header(_ item: SharedStore.Item, label: String) -> some View {
        HStack {
            ZStack {
                Circle().fill(Color.widgetCircle)
                Image(systemName: item.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(item.color)
            }
            .frame(width: 30, height: 30)
            Spacer()
            Text(label)
                .font(.caption2.weight(.heavy))
                .foregroundStyle(item.color)
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let current = entry.state.current {
            let end = NowPlan.end(of: current)
            VStack(alignment: .leading, spacing: 2) {
                Label(current.title, systemImage: current.symbol)
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                ProgressView(timerInterval: current.start...end, countsDown: false) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                Text("\(Text(timerInterval: current.start...end, countsDown: true)) left")
                    .font(.caption)
                    .monospacedDigit()
            }
        } else if let next = entry.state.next {
            VStack(alignment: .leading, spacing: 2) {
                Text("Up next").font(.caption)
                Label(next.title, systemImage: next.symbol)
                    .font(.headline)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(next.start.formatted(date: .omitted, time: .shortened)).font(.caption)
            }
        } else {
            Text("All clear")
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let current = entry.state.current {
            ProgressView(timerInterval: current.start...NowPlan.end(of: current), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                Image(systemName: current.symbol)
            }
            .progressViewStyle(.circular)
            .widgetAccentable()
        } else if let next = entry.state.next {
            VStack(spacing: 0) {
                Image(systemName: next.symbol)
                Text(next.start.formatted(.dateTime.hour().minute()))
                    .font(.system(size: 10, weight: .semibold))
                    .minimumScaleFactor(0.6)
            }
        } else {
            Image(systemName: "checkmark")
        }
    }
}

struct NowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Now", provider: NowProvider()) { entry in
            NowWidgetView(entry: entry)
        }
        .configurationDisplayName("Now")
        .description("What you're doing right now and how much time is left.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

// MARK: - Now Live Activity (Lock Screen + Dynamic Island)

struct NowLockScreenView: View {
    let state: NowAttributes.ContentState
    let isStale: Bool

    private var color: Color { Color.category(state.category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isStale {
                staleView
            } else {
                HStack(spacing: 12) {
                    icon(state.symbol, color: color)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(state.isUpcoming ? "UP NEXT" : "NOW")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(color)
                        Text(state.title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text((state.isUpcoming ? "Starts " : "Until ") + state.end.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(timerInterval: state.start...state.end, countsDown: true)
                            .font(.system(size: 28, weight: .heavy).monospacedDigit())
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120, alignment: .trailing)
                        Text(state.isUpcoming ? "to go" : "left")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                if !state.isUpcoming {
                    ProgressView(timerInterval: state.start...state.end, countsDown: false) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(color)
                    HStack {
                        if let next = state.nextTitle, let at = state.nextStart {
                            Text("Then \(next) · \(at.formatted(date: .omitted, time: .shortened))")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        Spacer()
                        pill("Done", symbol: "checkmark", intent: NowDoneIntent(itemID: state.itemID))
                    }
                }
            }
        }
        .padding(16)
    }

    /// Shown once the block's time is up and the app hasn't updated the card yet.
    @ViewBuilder
    private var staleView: some View {
        HStack(spacing: 12) {
            if !state.isUpcoming, let next = state.nextTitle, let at = state.nextStart {
                icon(state.nextSymbol ?? "arrow.right", color: .white)
                VStack(alignment: .leading, spacing: 1) {
                    Text("UP NEXT").font(.caption2.weight(.heavy)).foregroundStyle(.white.opacity(0.6))
                    Text(next).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(at.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                icon(state.symbol, color: color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(state.title).font(.headline).foregroundStyle(.white).lineLimit(1)
                    Text(state.isUpcoming ? "Starting now" : "Time's up")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Spacer(minLength: 4)
            pill("Update", symbol: "arrow.clockwise", intent: NowRefreshIntent())
        }
    }

    private func icon(_ symbol: String, color: Color) -> some View {
        ZStack {
            Circle().fill(Color.widgetCircle)
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 44, height: 44)
    }

    private func pill<I: AppIntent>(_ title: String, symbol: String, intent: I) -> some View {
        Button(intent: intent) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.widgetDark)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct NowLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NowAttributes.self) { context in
            NowLockScreenView(state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.widgetDark)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            let color = Color.category(state.category)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.symbol)
                        .font(.title2)
                        .foregroundStyle(color)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 0) {
                        Text(state.title).font(.headline).lineLimit(1)
                        Text((state.isUpcoming ? "Starts " : "Until ") + state.end.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: state.start...state.end, countsDown: true)
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !state.isUpcoming {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(timerInterval: state.start...state.end, countsDown: false) {
                                EmptyView()
                            } currentValueLabel: {
                                EmptyView()
                            }
                            .tint(color)
                            if let next = state.nextTitle, let at = state.nextStart {
                                Text("Then \(next) · \(at.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbol).foregroundStyle(color)
            } compactTrailing: {
                Text(timerInterval: state.start...state.end, countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 56)
                    .foregroundStyle(color)
            } minimal: {
                Image(systemName: state.symbol).foregroundStyle(color)
            }
        }
    }
}
