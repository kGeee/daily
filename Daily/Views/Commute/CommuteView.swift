import SwiftUI
import SwiftData

struct CommuteView: View {
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @AppStorage("remindersOn") private var remindersOn = false
    @AppStorage(Pref.revision) private var revision = 0
    @State private var showSettings = false

    private var planner: DayPlanner { DayPlanner(pattern: pattern, overrides: overrides) }

    var body: some View {
        let _ = revision
        TimelineView(.everyMinute) { tl in
            let today = Calendar.current.startOfDay(for: tl.date)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(now: tl.date)
                    if let type = planner.type(for: today) {
                        Picker("Day type", selection: Binding(
                            get: { type },
                            set: { setType($0, on: today) }
                        )) {
                            ForEach(DayType.allCases) { t in
                                Text(t.short).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    nextCard(now: tl.date)
                    LiveTrainsCard()
                    if let type = planner.type(for: today) {
                        dayPlanCard(type: type, day: today, now: tl.date)
                    }
                    trainsCard(now: tl.date)
                    remindersCard
                    thisWeekCard(today: today)
                    usualWeekCard
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    private func header(now: Date) -> some View {
        HStack(alignment: .bottom) {
            ScreenHeader(eyebrow: now.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                         title: "Commute")
            Spacer()
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.title3)
                    .foregroundStyle(Palette.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Schedule settings")
        }
    }

    private func setType(_ type: DayType, on day: Date) {
        let key = DayKey.of(day)
        if let existing = overrides.first(where: { $0.dayKey == key }) {
            existing.typeRaw = type.rawValue
        } else {
            context.insert(DayTypeOverride(dayKey: key, typeRaw: type.rawValue))
        }
    }

    // MARK: Next departure

    /// The next time you need to walk out the door, today or on a later day.
    private func nextDeparture(now: Date) -> TimelineBlock? {
        let cal = Calendar.current
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: cal.startOfDay(for: now)) else { continue }
            let next = planner.blocks(for: day, lunchNote: nil, dinnerNote: nil)
                .filter { $0.isDeparture }
                .first { ($0.leaveBy ?? $0.start) > now.addingTimeInterval(-2 * 60) }
            if let next { return next }
        }
        return nil
    }

    private func nextCard(now: Date) -> some View {
        let block = nextDeparture(now: now)
        let leaveAt = block.map { $0.leaveBy ?? $0.start }
        let minutes = leaveAt.map { Int($0.timeIntervalSince(now) / 60) } ?? 0
        let isToday = block.map { Calendar.current.isDateInToday($0.start) } ?? true

        return VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: isToday ? "Next up" : "Next up · " + (block?.start.formatted(.dateTime.weekday(.wide)) ?? ""),
                         color: Palette.onAccent.opacity(0.85))
            if let block, let leaveAt {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text((block.isEstimate ? "~" : "") + block.start.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 34, weight: .heavy))
                        Text(block.title)
                            .font(.subheadline.weight(.semibold))
                        Text(block.subtitle)
                            .font(.footnote)
                            .opacity(0.85)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(minutes <= 0 ? "Leave" : "Leave in").font(.caption).opacity(0.85)
                        Text(minutes <= 0 ? "now" : durationLabel(minutes))
                            .font(.system(size: 24, weight: .heavy))
                        Text("at " + leaveAt.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                            .opacity(0.85)
                    }
                }
                if block.isEstimate {
                    Text("Estimated. Add your Caltrain times in Settings for exact trains.")
                        .font(.caption)
                        .opacity(0.85)
                }
            } else {
                Text("Nothing scheduled this week.")
                    .font(.headline)
            }
        }
        .foregroundStyle(Palette.onAccent)
        .card(padding: 18, fill: Palette.commute)
    }

    private func durationLabel(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let days = minutes / 1440
        if days >= 1 { return "\(days)d \((minutes % 1440) / 60)h" }
        return "\(minutes / 60)h \(minutes % 60)m"
    }

    // MARK: Today's plan

    private func dayPlanCard(type: DayType, day: Date, now: Date) -> some View {
        let legs = planner.blocks(for: day, lunchNote: nil, dinnerNote: nil)
            .filter { $0.isDeparture || $0.id == "gym" }

        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Today · " + type.title)
            ForEach(legs) { leg in
                let past = (leg.end ?? leg.start) < now
                HStack(spacing: 12) {
                    Image(systemName: leg.symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(leg.category.color)
                        .frame(width: 32, height: 32)
                        .background(Palette.circle, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(leg.title)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(past ? Palette.faint : Palette.ink)
                        if !leg.subtitle.isEmpty {
                            Text(leg.subtitle)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                    }
                    Spacer()
                    Text((leg.isEstimate ? "~" : "") + leg.start.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.heavy).monospacedDigit())
                        .foregroundStyle(past ? Palette.faint : Palette.ink)
                }
            }
        }
        .card()
    }

    // MARK: Trains

    private func trainsCard(now: Date) -> some View {
        let morning = MySchedule.morningTrains
        let evening = MySchedule.eveningTrains
        let nowMinutes = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Your Caltrain times")
                Spacer()
                Button("Edit") { showSettings = true }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.commuteText)
            }
            if morning.isEmpty && evening.isEmpty {
                Text("Add the trains you usually take in Settings. Gym and Caltrain days will then use the real train instead of an estimate.")
                    .font(.footnote)
                    .foregroundStyle(Palette.muted)
            } else {
                trainRow(label: MySchedule.homeStation + " → Sunnyvale", trains: morning, nowMinutes: nowMinutes)
                trainRow(label: "Sunnyvale → " + MySchedule.homeStation, trains: evening, nowMinutes: nowMinutes)
            }
        }
        .card()
    }

    private func trainRow(label: String, trains: [Int], nowMinutes: Int) -> some View {
        let next = trains.first { $0 >= nowMinutes }
        return VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.muted)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if trains.isEmpty {
                        Text("None added")
                            .font(.caption)
                            .foregroundStyle(Palette.faint)
                    }
                    ForEach(trains, id: \.self) { minutes in
                        let isNext = minutes == next
                        let isPast = minutes < nowMinutes
                        Text(ClockTime(minutes: minutes).label)
                            .font(.caption.weight(.bold).monospacedDigit())
                            .foregroundStyle(isNext ? Palette.onAccent : (isPast ? Palette.faint : Palette.ink))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isNext ? Palette.commute : Palette.card2, in: Capsule())
                    }
                }
            }
        }
    }

    // MARK: Reminders

    private var remindersCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: Binding(
                get: { remindersOn },
                set: { newValue in
                    if newValue {
                        Task { remindersOn = await Reminders.requestPermission() }
                    } else {
                        remindersOn = false
                    }
                }
            )) {
                Text("Remind me \(MySchedule.reminderLeadMinutes) min before I need to leave")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
            }
            .tint(Palette.commute)
            Text("Also reminds you about Sunday meal prep, wind-down, packing your gym bag, and your own events.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
        }
        .card()
    }

    // MARK: Weeks

    private func thisWeekCard(today: Date) -> some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: today)?.start ?? today
        let weekdays: [Date] = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
            .filter { (2...6).contains(cal.component(.weekday, from: $0)) }

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "This week")
                Spacer()
                Text("Tap a day to change it")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 6) {
                ForEach(weekdays, id: \.self) { day in
                    let type = planner.type(for: day) ?? .shuttle
                    let isToday = cal.isDateInToday(day)
                    let isPast = day < today
                    Menu {
                        ForEach(DayType.allCases) { t in
                            Button(t.title) { setType(t, on: day) }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated)).uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Palette.muted)
                            Text(type.short)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isPast ? Palette.faint : Palette.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(type.tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isToday ? Palette.ink : Color.clear, lineWidth: 2)
                        )
                    }
                }
            }
        }
        .card()
    }

    private var usualWeekCard: some View {
        let days: [(String, Int)] = [("MON", 2), ("TUE", 3), ("WED", 4), ("THU", 5), ("FRI", 6)]

        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Your usual week")
            Text("The default for every week. Changes above only affect that one day.")
                .font(.caption)
                .foregroundStyle(Palette.muted)
            HStack(spacing: 6) {
                ForEach(days, id: \.1) { day in
                    let name = day.0
                    let weekday = day.1
                    let type = planner.usualType(forWeekday: weekday) ?? .shuttle
                    Menu {
                        ForEach(DayType.allCases) { t in
                            Button(t.title) {
                                pattern = DayPlanner.updating(pattern: pattern, weekday: weekday, to: t)
                            }
                        }
                    } label: {
                        VStack(spacing: 2) {
                            Text(name).font(.caption2.weight(.bold)).foregroundStyle(Palette.muted)
                            Text(type.short).font(.caption.weight(.bold)).foregroundStyle(Palette.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Palette.card2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(type.color, lineWidth: 1.5)
                        )
                    }
                }
            }
        }
        .card()
    }
}

/// Live departures from 511.org: your station toward Sunnyvale before noon,
/// Sunnyvale toward home after.
struct LiveTrainsCard: View {
    @AppStorage(Pref.liveStationName) private var stationName = ""
    @AppStorage(Pref.liveHomeStops) private var homeStops = ""
    @AppStorage(Pref.liveSunnyvaleStops) private var sunnyvaleStops = ""
    @AppStorage(Pref.directionToWork) private var directionToWork = Pref.directionToWorkDefault

    @State private var departures: [Caltrain511.Departure] = []
    @State private var errorText: String?
    @State private var loading = false
    @State private var updated: Date?

    private var isMorning: Bool { Calendar.current.component(.hour, from: Date()) < 12 }
    private var stops: [String] {
        (isMorning ? homeStops : sunnyvaleStops).split(separator: ",").map(String.init)
    }
    private var direction: String {
        isMorning ? directionToWork : (directionToWork == "S" ? "N" : "S")
    }
    private var routeLabel: String {
        isMorning ? "\(stationName) → Sunnyvale" : "Sunnyvale → \(stationName)"
    }

    var body: some View {
        if Keychain.read(Keychain.fiveOneOne)?.isEmpty == false && !stationName.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionLabel(text: "Live · " + routeLabel)
                    Spacer()
                    if loading {
                        ProgressView()
                    } else {
                        Button {
                            Task { await load() }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Palette.commuteText)
                                .frame(width: 32, height: 32)
                        }
                        .accessibilityLabel("Refresh live trains")
                    }
                }
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(Palette.gymText)
                } else if departures.isEmpty && !loading {
                    Text("No live departures right now.")
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                ForEach(departures.prefix(4)) { d in
                    HStack(spacing: 10) {
                        Text(d.time.formatted(date: .omitted, time: .shortened))
                            .font(.subheadline.weight(.heavy).monospacedDigit())
                            .foregroundStyle(Palette.ink)
                            .frame(width: 78, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(d.line.isEmpty ? "Caltrain" : d.line)
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Palette.ink)
                            Text("to " + d.destination)
                                .font(.caption)
                                .foregroundStyle(Palette.muted)
                        }
                        Spacer()
                        delayTag(d)
                    }
                }
                if let updated {
                    Text("Updated " + updated.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundStyle(Palette.faint)
                }
            }
            .card()
            .task { await load() }
        }
    }

    private func delayTag(_ d: Caltrain511.Departure) -> some View {
        let delay = d.delayMinutes
        let text: String
        let color: Color
        if let delay, delay >= 2 {
            text = "+\(delay) min"
            color = Palette.gymText
        } else if delay != nil {
            text = "On time"
            color = Palette.foodText
        } else {
            text = "Scheduled"
            color = Palette.muted
        }
        return Text(text).font(.caption.weight(.bold)).foregroundStyle(color)
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            departures = try await Caltrain511.departures(stopIDs: stops, direction: direction)
            updated = Date()
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}
