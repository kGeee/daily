import SwiftUI
import SwiftData

struct CommuteView: View {
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @AppStorage(Pref.revision) private var revision = 0
    @State private var showSettings = false
    @State private var editingRoutine: DayType?
    @State private var stepEdit: StepDayEdit?

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
                    LiveTrainsCard(planner: planner)
                    if let type = planner.type(for: today) {
                        dayPlanCard(type: type, day: today, now: tl.date)
                    } else {
                        Text("No commute today. Enjoy the weekend.")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Palette.muted)
                            .card()
                    }
                }
                .padding(16)
            }
            .background(Palette.bg.ignoresSafeArea())
        }
        .sheet(isPresented: $showSettings) {
            CommuteSettingsView()
        }
        .sheet(item: $stepEdit) { edit in
            StepDayEditor(edit: edit)
        }
        .sheet(item: $editingRoutine) { type in
            NavigationStack {
                RoutineEditorView(type: type)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { editingRoutine = nil }
                        }
                    }
            }
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
            .accessibilityLabel("Commute settings")
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
                    Text("Estimated. Add times to this timetable in Commute settings for exact departures.")
                        .font(.caption)
                        .opacity(0.85)
                }
                if minutes > -5 && minutes < 180 && WidgetSync.canShowLiveActivities {
                    Button {
                        Task {
                            await WidgetSync.startCountdown(title: block.title, subtitle: block.subtitle,
                                                            departure: block.start, leaveBy: leaveAt, symbol: block.symbol)
                        }
                    } label: {
                        Label("Show countdown on Lock Screen", systemImage: "lock.iphone")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Palette.commute)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(Palette.onAccent, in: Capsule())
                    }
                    .buttonStyle(.plain)
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
            .filter { $0.routineType != nil }
        let changed = Routines.overrides(for: DayKey.of(day))

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Today · " + type.title)
                Spacer()
                Button("Edit routine") { editingRoutine = type }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.commuteText)
            }
            ForEach(legs) { leg in
                let past = (leg.end ?? leg.start) < now
                Button {
                    stepEdit = StepDayEdit(block: leg, day: day)
                } label: {
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
                                    .multilineTextAlignment(.leading)
                            }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text((leg.isEstimate ? "~" : "") + leg.start.formatted(date: .omitted, time: .shortened))
                                .font(.subheadline.weight(.heavy).monospacedDigit())
                                .foregroundStyle(past ? Palette.faint : Palette.ink)
                            if changed[leg.id] != nil {
                                Text("changed")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(Palette.gymText)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            ForEach(skippedSteps(type: type, day: day)) { step in
                Button {
                    Routines.setOverride(nil, step: step.id, dayKey: DayKey.of(day))
                    Pref.bump()
                } label: {
                    Label("Skipped: \(step.title) · bring it back", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.commuteText)
                }
                .buttonStyle(.plain)
            }
            Text("Tap a step to change it just for today.")
                .font(.caption)
                .foregroundStyle(Palette.faint)
        }
        .card()
    }

    private func skippedSteps(type: DayType, day: Date) -> [RoutineStep] {
        let changed = Routines.overrides(for: DayKey.of(day))
        return Routines.steps(for: type).filter { changed[$0.id]?.skipped == true }
    }
}

/// Live departures from 511.org for your next Caltrain step today: your station toward
/// Sunnyvale in the morning, or Sunnyvale / Mountain View toward home later.
struct LiveTrainsCard: View {
    let planner: DayPlanner

    @AppStorage(Pref.liveStationName) private var stationName = ""
    @AppStorage(Pref.liveHomeStops) private var homeStops = ""
    @AppStorage(Pref.liveSunnyvaleStops) private var sunnyvaleStops = ""
    @AppStorage(Pref.liveMountainViewStops) private var mountainViewStops = ""
    @AppStorage(Pref.directionToWork) private var directionToWork = Pref.directionToWorkDefault

    @State private var departures: [Caltrain511.Departure] = []
    @State private var errorText: String?
    @State private var loading = false
    @State private var updated: Date?

    /// Which live line to show: from today's routine if it has a Caltrain step coming up.
    private var line: Timetable.Live {
        let now = Date()
        let nowMinutes = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        if let type = planner.type(for: now) {
            let resolved = RoutineResolver.resolve(Routines.steps(for: type),
                                                   overrides: Routines.overrides(for: DayKey.of(now)))
            for r in resolved where r.start >= nowMinutes - 5 {
                if let id = r.step.timetableID, let live = Timetables.get(id)?.live, live != .none {
                    return live
                }
            }
        }
        return nowMinutes < 12 * 60 ? .homeToWork : .sunnyvaleToHome
    }

    private var stops: [String] {
        let raw: String
        switch line {
        case .homeToWork, .none: raw = homeStops
        case .sunnyvaleToHome: raw = sunnyvaleStops
        case .mountainViewToHome: raw = mountainViewStops
        }
        return raw.split(separator: ",").map(String.init)
    }

    private var direction: String {
        line == .homeToWork ? directionToWork : (directionToWork == "S" ? "N" : "S")
    }

    private var routeLabel: String {
        switch line {
        case .homeToWork, .none: return "\(stationName) → Sunnyvale"
        case .sunnyvaleToHome: return "Sunnyvale → \(stationName)"
        case .mountainViewToHome: return "Mountain View → \(stationName)"
        }
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
            .task(id: line) { await load() }
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
