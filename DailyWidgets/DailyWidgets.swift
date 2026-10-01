import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents

// Widget colors mirror Palette in the app (the widget is a separate target).
private extension Color {
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
        NextUpWidget()
        WaterWidget()
        DepartureLiveActivity()
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
            mainView
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
