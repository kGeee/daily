import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// Widget colors mirror Palette in the app (the widget is a separate target).
extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
    static let dailyBlue = Color(hex: 0x2560C9)
    static let dailyGreen = Color(hex: 0x23744A)
    static let dailyTeal = Color(hex: 0x157A97)
}

@main
struct DailyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        NowWidget()
        TimelineWidget()
        NextUpWidget()
        WaterWidget()
        DepartureLiveActivity()
        NowLiveActivity()
    }
}

// MARK: - Timeline (your next few blocks, with check-offs)

struct TimelineWidgetEntry: TimelineEntry {
    let date: Date
    let items: [SharedStore.Item]
}

struct TimelineWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> TimelineWidgetEntry {
        let now = Date()
        let sample = [
            SharedStore.Item(blockID: "out", dayKey: "", title: "Shuttle to work", subtitle: "Leave by 7:35 AM",
                             start: now.addingTimeInterval(1800), end: nil, symbol: "bus.fill", category: "commute", done: false),
            SharedStore.Item(blockID: "lunch", dayKey: "", title: "Lunch", subtitle: "Planned: Turkey chili",
                             start: now.addingTimeInterval(16000), end: nil, symbol: "fork.knife", category: "food", done: false)
        ]
        return TimelineWidgetEntry(date: now, items: sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TimelineWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TimelineWidgetEntry>) -> Void) {
        let now = Date()
        let items = SharedStore.load().items ?? []
        // Move on as each item finishes.
        var dates = [now]
        dates += items.map { $0.end ?? $0.start.addingTimeInterval(30 * 60) }.filter { $0 > now }
        let entries = dates.prefix(15).map { entry(at: $0) }
        let refresh = Calendar.current.date(byAdding: .hour, value: 3, to: now) ?? now.addingTimeInterval(10800)
        completion(Timeline(entries: Array(entries), policy: .after(refresh)))
    }

    private func entry(at date: Date) -> TimelineWidgetEntry {
        let items = SharedStore.currentItems().filter { NowPlan.end(of: $0) > date }
        return TimelineWidgetEntry(date: date, items: items)
    }
}

extension Color {
    /// Category colors (dark-mode Palette values, since the widgets are dark).
    static func category(_ category: String) -> Color {
        switch category {
        case "commute": return Color(hex: 0x4C8DF0)
        case "gym": return Color(hex: 0xEE7A45)
        case "food": return Color(hex: 0x3FAE74)
        case "sleep": return Color(hex: 0x8C8CF0)
        case "work": return Color(hex: 0x9AA0AB)
        case "focus": return Color(hex: 0xF26B5B)
        case "break": return Color(hex: 0x5BC0DE)
        default: return Color(hex: 0xF07AA8)
        }
    }
    static let widgetDark = Color(hex: 0x1A1C21)
    static let widgetCircle = Color(hex: 0x2A2D34)
}

extension SharedStore.Item {
    var color: Color { Color.category(category) }

    /// How many days after the entry date this item is (for the "+1" mark).
    func daysAhead(from date: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: start)).day ?? 0
    }
}

struct TimelineWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TimelineWidgetEntry

    private var rowCount: Int { family == .systemLarge ? 5 : 2 }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if entry.items.isEmpty {
                Text("Nothing coming up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entry.items.prefix(rowCount).enumerated()), id: \.element.id) { index, item in
                        row(item, isLast: index == min(rowCount, entry.items.count) - 1)
                    }
                    Spacer(minLength: 0)
                }
            }
            Button(intent: AddEventIntent()) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color(hex: 0x4C8DF0), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .containerBackground(Color(hex: 0x1A1C21), for: .widget)
    }

    private func row(_ item: SharedStore.Item, isLast: Bool) -> some View {
        let ahead = item.daysAhead(from: entry.date)
        return HStack(alignment: .center, spacing: 12) {
            ZStack {
                if !isLast {
                    Rectangle()
                        .fill(Color(hex: 0x2A2D34))
                        .frame(width: 4)
                        .frame(maxHeight: .infinity)
                        .offset(y: 26)
                }
                Circle()
                    .fill(item.done ? item.color : Color(hex: 0x2A2D34))
                    .frame(width: 44, height: 44)
                Image(systemName: item.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(item.done ? Color(hex: 0x1A1C21) : item.color)
            }
            .frame(width: 44)

            VStack(alignment: .leading, spacing: 1) {
                (Text(item.start.formatted(date: .omitted, time: .shortened))
                 + Text(ahead > 0 ? "+\(ahead)" : "").font(.caption2).baselineOffset(5))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                Text(item.title)
                    .font(.headline)
                    .foregroundStyle(item.done ? Color.white.opacity(0.5) : Color.white)
                    .strikethrough(item.done)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(intent: ToggleBlockIntent(itemID: item.id)) {
                ZStack {
                    Circle()
                        .strokeBorder(item.color, lineWidth: 2.5)
                        .background(Circle().fill(item.done ? item.color : Color.clear))
                    if item.done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Color(hex: 0x1A1C21))
                    }
                }
                .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .padding(.trailing, isLast ? 52 : 0)
        }
        .frame(maxHeight: family == .systemLarge ? 60 : 56)
    }
}

struct TimelineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Timeline", provider: TimelineWidgetProvider()) { entry in
            TimelineWidgetView(entry: entry)
        }
        .configurationDisplayName("Timeline")
        .description("Your next few things across today and tomorrow. Tap a circle to check it off.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

// MARK: - Next up

struct NextUpEntry: TimelineEntry {
    let date: Date
    let next: SharedStore.Departure?
    let after: SharedStore.Departure?
    let snapshot: SharedStore.Snapshot
}

struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        let sample = SharedStore.Departure(title: "Shuttle to work", subtitle: "Leave by 7:35 AM",
                                           start: Date().addingTimeInterval(1800), leaveBy: Date().addingTimeInterval(1200),
                                           isEstimate: false, symbol: "bus.fill")
        return NextUpEntry(date: Date(), next: sample, after: nil, snapshot: SharedStore.Snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedStore.load()
        // A new entry each time a departure passes, so the widget moves on by itself.
        var dates = [now]
        dates += snapshot.departures.map { $0.start.addingTimeInterval(60) }.filter { $0 > now }
        let entries = dates.prefix(12).map { entry(at: $0, snapshot: snapshot) }
        let refresh = Calendar.current.date(byAdding: .hour, value: 2, to: now) ?? now.addingTimeInterval(7200)
        completion(Timeline(entries: Array(entries), policy: .after(refresh)))
    }

    private func entry(at date: Date, snapshot: SharedStore.Snapshot = SharedStore.load()) -> NextUpEntry {
        let upcoming = snapshot.departures.filter { $0.start > date }.sorted { $0.start < $1.start }
        return NextUpEntry(date: date, next: upcoming.first, after: upcoming.dropFirst().first, snapshot: snapshot)
    }
}

struct NextUpView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextUpEntry

    var body: some View {
        accessoryOrMain
    }

    @ViewBuilder
    private var accessoryOrMain: some View {
        switch family {
        case .accessoryInline, .accessoryRectangular:
            accessory
                .containerBackground(.clear, for: .widget)
        default:
            mainView
        }
    }

    @ViewBuilder
    private var accessory: some View {
        switch family {
        case .accessoryInline:
            if let next = entry.next {
                Text("\(next.title) \(next.start.formatted(date: .omitted, time: .shortened))")
            } else {
                Text("No departures")
            }
        case .accessoryRectangular:
            if let next = entry.next {
                VStack(alignment: .leading, spacing: 1) {
                    Text(next.title).font(.headline).widgetAccentable()
                    Text((next.isEstimate ? "~" : "") + next.start.formatted(date: .omitted, time: .shortened))
                    Text("Leave by \(next.leaveBy.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                }
            } else {
                Text("Nothing scheduled")
            }
        default:
            EmptyView()
        }
    }

    private var mainView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NEXT UP")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
            if let next = entry.next {
                HStack(spacing: 6) {
                    Image(systemName: next.symbol)
                    Text(next.title).lineLimit(1)
                }
                .font(.subheadline.weight(.semibold))
                Text((next.isEstimate ? "~" : "") + next.start.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 28, weight: .heavy))
                    .minimumScaleFactor(0.7)
                if next.leaveBy > entry.date {
                    HStack(spacing: 4) {
                        Text("Leave in")
                        Text(next.leaveBy, style: .relative)
                    }
                    .font(.caption.weight(.semibold))
                } else {
                    Text("Leave now").font(.caption.weight(.semibold))
                }
                if family == .systemMedium, let after = entry.after {
                    Spacer(minLength: 0)
                    Text("Then: \(after.title) \(after.start.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
            } else {
                Text("No departures coming up")
                    .font(.subheadline.weight(.semibold))
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(Color.dailyBlue, for: .widget)
    }
}

struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NextUp", provider: NextUpProvider()) { entry in
            NextUpView(entry: entry)
        }
        .configurationDisplayName("Next up")
        .description("Your next shuttle or train and when to leave.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Water

struct WaterEntry: TimelineEntry {
    let date: Date
    let ounces: Int
    let goal: Int
}

struct WaterProvider: TimelineProvider {
    func placeholder(in context: Context) -> WaterEntry { WaterEntry(date: Date(), ounces: 48, goal: 100) }

    func getSnapshot(in context: Context, completion: @escaping (WaterEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WaterEntry>) -> Void) {
        let midnight = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400))
        completion(Timeline(entries: [current()], policy: .after(midnight)))
    }

    private func current() -> WaterEntry {
        WaterEntry(date: Date(), ounces: SharedStore.widgetWaterToday(), goal: max(SharedStore.load().waterGoal, 1))
    }
}

struct WaterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WaterEntry

    var body: some View {
        if family == .accessoryCircular {
            Gauge(value: Double(min(entry.ounces, entry.goal)), in: 0...Double(entry.goal)) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("\(entry.ounces)")
            }
            .gaugeStyle(.accessoryCircular)
            .containerBackground(.clear, for: .widget)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                Text("WATER")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.dailyTeal)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("\(entry.ounces)").font(.system(size: 30, weight: .heavy))
                    Text("/\(entry.goal) oz").font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: Double(min(entry.ounces, entry.goal)), total: Double(entry.goal))
                    .tint(Color.dailyTeal)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Button(intent: AddWaterIntent(ounces: 8)) {
                        Text("+8").font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                    }
                    Button(intent: AddWaterIntent(ounces: 16)) {
                        Text("+16").font(.subheadline.weight(.heavy)).frame(maxWidth: .infinity)
                    }
                }
                .tint(Color.dailyTeal)
            }
            .containerBackground(.background, for: .widget)
        }
    }
}

struct WaterWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Water", provider: WaterProvider()) { entry in
            WaterWidgetView(entry: entry)
        }
        .configurationDisplayName("Water")
        .description("Today's water, with +8 and +16 oz buttons.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

// MARK: - Live Activity

struct DepartureLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DepartureAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.dailyBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.title).font(.headline)
                    Text("Departs " + context.state.departure.formatted(date: .omitted, time: .shortened)
                         + " · " + context.state.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("Leave in").font(.caption2).foregroundStyle(.secondary)
                    Text(timerInterval: Date()...max(Date(), context.state.leaveBy), countsDown: true)
                        .font(.title2.weight(.heavy).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                }
            }
            .padding(16)
            .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.title, systemImage: context.state.symbol)
                        .font(.subheadline.weight(.semibold))
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: Date()...max(Date(), context.state.leaveBy), countsDown: true)
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .frame(width: 80)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Leave by " + context.state.leaveBy.formatted(date: .omitted, time: .shortened)
                         + " · departs " + context.state.departure.formatted(date: .omitted, time: .shortened))
                        .font(.caption)
                }
            } compactLeading: {
                Image(systemName: context.state.symbol).foregroundStyle(Color.dailyBlue)
            } compactTrailing: {
                Text(timerInterval: Date()...max(Date(), context.state.leaveBy), countsDown: true)
                    .monospacedDigit()
                    .frame(width: 44)
            } minimal: {
                Image(systemName: context.state.symbol).foregroundStyle(Color.dailyBlue)
            }
        }
    }
}
