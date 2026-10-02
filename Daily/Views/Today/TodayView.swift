import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @Query private var checks: [BlockCheck]
    @Query private var water: [WaterEntry]
    @Query private var food: [FoodEntry]
    @Query private var events: [CustomEvent]
    @Query(sort: \WorkoutTemplate.order) private var templates: [WorkoutTemplate]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)
    @State private var editingEvent: CustomEvent?
    @State private var showNewEvent = false
    @State private var showWeekPlan = false
    @State private var showMonth = false
    @State private var showReview = false
    @State private var showSettings = false
    @State private var stepEdit: StepDayEdit?
    @Query private var plans: [MealPlan]
    @AppStorage(Pref.revision) private var revision = 0

    private var planner: DayPlanner { DayPlanner(pattern: pattern, overrides: overrides) }
    private var dayKey: String { DayKey.of(selectedDay) }

    var body: some View {
        let _ = revision
        TimelineView(.everyMinute) { tl in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    WeekStrip(selected: $selectedDay, planner: planner)
                    if Calendar.current.isDateInToday(selectedDay) {
                        NowCard(items: WidgetSync.timelineItems(planner: planner, plans: plans, checks: checks,
                                                                events: events, now: tl.date, days: 2),
                                now: tl.date) { item in
                            markDone(item)
                        }
                    }
                    statsRow
                    goalsRow
                    if Calendar.current.isDateInToday(selectedDay),
                       Calendar.current.component(.weekday, from: tl.date) == 1 {
                        Button {
                            showReview = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "chart.bar.xaxis")
                                Text("Your week in review is ready")
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption.weight(.bold))
                            }
                            .foregroundStyle(Palette.foodText)
                            .padding(14)
                            .background(Palette.foodTint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    if Calendar.current.isDateInToday(selectedDay),
                       Calendar.current.component(.hour, from: tl.date) >= 17 {
                        tomorrowCard(now: tl.date)
                    }
                    timeline(now: tl.date)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 90)
            }
            .background(Palette.bg.ignoresSafeArea())
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showNewEvent = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: 60, height: 60)
                        .background(Palette.commute, in: Circle())
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .padding(20)
                .accessibilityLabel("Add event")
            }
        }
        .sheet(isPresented: $showWeekPlan) {
            WeekPlanView()
        }
        .sheet(isPresented: $showMonth) {
            MonthView { day in selectedDay = day }
        }
        .sheet(isPresented: $showReview) {
            WeekReviewView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(item: $stepEdit) { edit in
            StepDayEditor(edit: edit)
        }
        .sheet(isPresented: $showNewEvent) {
            EventEditor(event: nil, defaultDay: selectedDay)
        }
        .sheet(item: $editingEvent) { event in
            EventEditor(event: event, defaultDay: selectedDay)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: selectedDay.formatted(.dateTime.weekday(.wide)))
                Text(selectedDay.formatted(.dateTime.month(.abbreviated).day()))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
            Button {
                showMonth = true
            } label: {
                Image(systemName: "calendar")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(Palette.card, in: Circle())
            }
            .accessibilityLabel("Month")
            Button {
                showWeekPlan = true
            } label: {
                Image(systemName: "list.bullet.clipboard")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(Palette.card, in: Circle())
            }
            .accessibilityLabel("Plan the week")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.headline)
                    .foregroundStyle(Palette.ink)
                    .frame(width: 36, height: 36)
                    .background(Palette.card, in: Circle())
            }
            .accessibilityLabel("Settings")
            if let type = planner.type(for: selectedDay) {
                Menu {
                    ForEach(DayType.allCases) { t in
                        Button(t.title) { setType(t) }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Circle().fill(type.color).frame(width: 8, height: 8)
                        Text(type.title).font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.down").font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(Palette.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .overlay(Capsule().stroke(type.color, lineWidth: 1.5))
                }
            } else {
                Text("Weekend")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.muted)
            }
        }
        .padding(.top, 8)
    }

    private func setType(_ type: DayType) {
        if let existing = overrides.first(where: { $0.dayKey == dayKey }) {
            existing.typeRaw = type.rawValue
        } else {
            context.insert(DayTypeOverride(dayKey: dayKey, typeRaw: type.rawValue))
        }
    }

    // MARK: Stats

    private var waterToday: Int {
        water.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
            .reduce(0) { $0 + $1.ounces }
    }

    private var ateOutThisWeek: Int {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: selectedDay) else { return 0 }
        return food.filter { week.contains($0.date) && $0.source == .out }.count
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Water").font(.caption.weight(.bold)).foregroundStyle(Palette.waterText)
                (Text("\(waterToday)").foregroundStyle(Palette.ink)
                 + Text("/\(MySchedule.waterGoalOz) oz").foregroundStyle(Palette.muted))
                    .font(.footnote.weight(.bold))
                Spacer(minLength: 0)
                Button {
                    addWater(8)
                } label: {
                    Text("+8")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(Palette.waterText)
                        .frame(width: 44, height: 32)
                        .background(Palette.waterTint, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Add 16 oz") { addWater(16) }
                    Button("Add 24 oz") { addWater(24) }
                    Button("Undo last", role: .destructive) { undoWater() }
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(height: 40)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            statPill(label: "Ate out", value: "\(ateOutThisWeek)×", color: Palette.gymText)
            statPill(label: "Slept", value: "—", color: Palette.sleepText)
        }
    }

    private var goalsRow: some View {
        let todays = food.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
        let calories = todays.compactMap { $0.calories }.reduce(0, +)
        let protein = todays.compactMap { $0.protein }.reduce(0, +)
        return HStack(spacing: 8) {
            goalPill(label: "Cal", value: "\(calories.formatted())/\(MySchedule.calorieGoal.formatted())",
                     progress: Double(calories) / Double(max(MySchedule.calorieGoal, 1)), color: Palette.food)
            goalPill(label: "Protein", value: "\(protein)/\(MySchedule.proteinGoal)g",
                     progress: Double(protein) / Double(max(MySchedule.proteinGoal, 1)), color: Palette.food)
        }
    }

    private func goalPill(label: String, value: String, progress: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(label).font(.caption2.weight(.bold)).foregroundStyle(Palette.muted)
                Spacer(minLength: 0)
                Text(value).font(.caption.weight(.bold)).foregroundStyle(Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            GoalBar(progress: progress, color: color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func statPill(label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.caption.weight(.bold)).foregroundStyle(color)
            Text(value).font(.footnote.weight(.bold)).foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func addWater(_ oz: Int) {
        let date = Calendar.current.isDateInToday(selectedDay)
            ? Date()
            : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDay) ?? selectedDay
        context.insert(WaterEntry(date: date, ounces: oz))
    }

    private func undoWater() {
        let todays = water.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
        if let last = todays.max(by: { $0.date < $1.date }) {
            context.delete(last)
        }
    }

    // MARK: Timeline

    private func note(for slot: MealSlot) -> String? {
        let names = food
            .filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) && $0.slot == slot }
            .map { $0.source == .out ? "\($0.name) (out)" : $0.name }
        if !names.isEmpty { return names.joined(separator: ", ") }
        return plannedTitle(for: slot, on: selectedDay).map { "Planned: " + $0 }
    }

    private func plannedTitle(for slot: MealSlot, on day: Date) -> String? {
        let key = DayKey.of(day)
        return plans.first { $0.dayKey == key && $0.slot == slot }?.title
    }

    // MARK: Tomorrow

    private func tomorrowCard(now: Date) -> some View {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let type = planner.type(for: tomorrow)
        let firstOut = planner.blocks(for: tomorrow, lunchNote: nil, dinnerNote: nil).first { $0.isDeparture }
        let lunch = plannedTitle(for: .lunch, on: tomorrow)
        let nextWorkout = WorkoutTemplate.nextName(templates: templates, sessions: sessions)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Tomorrow · " + (type?.title ?? tomorrow.formatted(.dateTime.weekday(.wide))))
                Spacer()
                Button("Plan week") { showWeekPlan = true }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Palette.commuteText)
            }
            if let firstOut {
                checklistLine(symbol: firstOut.symbol, color: Palette.commute,
                              text: firstOut.title + " " + (firstOut.isEstimate ? "~" : "")
                                + firstOut.start.formatted(date: .omitted, time: .shortened)
                                + " · leave by " + (firstOut.leaveBy ?? firstOut.start).formatted(date: .omitted, time: .shortened))
                checklistLine(symbol: "alarm", color: Palette.sleep,
                              text: "Up at " + MySchedule.wake.label + ", so bed by " + MySchedule.bedtime.label)
            }
            if type == .gym {
                checklistLine(symbol: "bag", color: Palette.gym,
                              text: "Pack your gym bag" + (nextWorkout.map { " · \($0) day" } ?? ""))
            }
            if type != nil {
                checklistLine(symbol: "takeoutbag.and.cup.and.straw", color: Palette.food,
                              text: lunch.map { "Lunch: " + $0 + (($0 == MealPlan.eatOut) ? "" : ". Pack it tonight") }
                                ?? "No lunch planned yet")
            }
            let tomorrowEvents = events.filter { $0.occurs(on: tomorrow) }.map { $0.block(on: tomorrow) }.sorted { $0.start < $1.start }
            ForEach(tomorrowEvents) { event in
                checklistLine(symbol: event.symbol, color: event.category.color,
                              text: event.start.formatted(date: .omitted, time: .shortened) + " · " + event.title)
            }
        }
        .card()
    }

    private func checklistLine(symbol: String, color: Color, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
        }
    }

    private func isDone(_ block: TimelineBlock) -> Bool {
        checks.contains { $0.dayKey == dayKey && $0.blockID == block.id }
    }

    private func toggle(_ block: TimelineBlock) {
        if let existing = checks.first(where: { $0.dayKey == dayKey && $0.blockID == block.id }) {
            context.delete(existing)
        } else {
            context.insert(BlockCheck(dayKey: dayKey, blockID: block.id))
        }
    }

    private func markDone(_ item: SharedStore.Item) {
        guard !checks.contains(where: { $0.dayKey == item.dayKey && $0.blockID == item.blockID }) else { return }
        context.insert(BlockCheck(dayKey: item.dayKey, blockID: item.blockID))
    }

    private func badge(for block: TimelineBlock, now: Date, isToday: Bool) -> String? {
        guard isToday, block.isDeparture, !isDone(block) else { return nil }
        let minutes = Int((block.leaveBy ?? block.start).timeIntervalSince(now) / 60)
        guard minutes >= 0, minutes <= 90 else { return nil }
        return minutes == 0 ? "Leaving now" : "Leave in \(minutes) min"
    }

    /// What to show on the gym block: today's workout if started, else the next one in rotation.
    private var gymNote: String? {
        if let today = sessions.first(where: { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }) {
            return today.finishedAt == nil ? "\(today.templateName) day · in progress" : "\(today.templateName) day · done"
        }
        return WorkoutTemplate.nextName(templates: templates, sessions: sessions).map { "\($0) day" }
    }

    private func items(now: Date) -> [TimelineItem] {
        let blocks = planner.blocks(for: selectedDay, lunchNote: note(for: .lunch), dinnerNote: note(for: .dinner),
                                    gymNote: gymNote, events: events)
        var result: [TimelineItem] = []
        var latestEnd: Date?
        var nowPlaced = !Calendar.current.isDateInToday(selectedDay)

        for block in blocks {
            if let latestEnd {
                let gap = block.start.timeIntervalSince(latestEnd)
                if gap >= 90 * 60 {
                    result.append(.free(id: "free-" + block.id, minutes: Int(gap / 60)))
                }
            }
            if !nowPlaced && block.start > now {
                result.append(.now)
                nowPlaced = true
            }
            result.append(.block(block))
            let end = block.end ?? block.start.addingTimeInterval(30 * 60)
            latestEnd = max(latestEnd ?? end, end)
        }
        if !nowPlaced { result.append(.now) }
        return result
    }

    private func timeline(now: Date) -> some View {
        let isToday = Calendar.current.isDateInToday(selectedDay)

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(items(now: now)) { item in
                switch item {
                case .now:
                    NowLine(time: now)
                case .free(_, let minutes):
                    FreeRow(minutes: minutes)
                case .block(let block):
                    TimelineRow(block: block,
                                done: isDone(block),
                                badge: badge(for: block, now: now, isToday: isToday)) {
                        toggle(block)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let id = block.eventID {
                            editingEvent = events.first { $0.id == id }
                        } else if block.routineType != nil {
                            stepEdit = StepDayEdit(block: block, day: selectedDay)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.trailing, 4)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }
}

enum TimelineItem: Identifiable {
    case block(TimelineBlock)
    case now
    case free(id: String, minutes: Int)

    var id: String {
        switch self {
        case .block(let block): return block.id
        case .now: return "now"
        case .free(let id, _): return id
        }
    }
}

struct FreeRow: View {
    let minutes: Int

    private var label: String {
        let h = minutes / 60
        let m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 50, height: 1)
            VLine()
                .stroke(Palette.idle, style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                .frame(width: 44)
            (Text(label).font(.footnote.weight(.bold)).foregroundStyle(Palette.commuteText)
             + Text(" free").font(.footnote).foregroundStyle(Palette.muted))
            Spacer()
        }
        .frame(height: 36)
        .padding(.leading, 4)
    }
}

// MARK: - Pieces

struct WeekStrip: View {
    @Binding var selected: Date
    let planner: DayPlanner

    private var days: [Date] {
        let cal = Calendar.current
        guard let start = cal.dateInterval(of: .weekOfYear, for: selected)?.start else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.self) { day in
                let cal = Calendar.current
                let isSelected = cal.isDate(day, inSameDayAs: selected)
                let isToday = cal.isDateInToday(day)
                Button {
                    selected = cal.startOfDay(for: day)
                } label: {
                    VStack(spacing: 4) {
                        Text(day.formatted(.dateTime.weekday(.abbreviated)))
                            .font(.caption)
                            .foregroundStyle(Palette.muted)
                        Text(day.formatted(.dateTime.day()))
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(isSelected ? Palette.onAccent : (isToday ? Palette.commuteText : Palette.ink))
                            .frame(width: 38, height: 38)
                            .background(Circle().fill(isSelected ? Palette.commute : Color.clear))
                        Circle()
                            .fill(dotColor(for: day))
                            .frame(width: 7, height: 7)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func dotColor(for day: Date) -> Color {
        if let type = planner.type(for: day) { return type.color }
        return Calendar.current.component(.weekday, from: day) == 1 ? Palette.food : Palette.idle
    }
}

struct NowLine: View {
    let time: Date

    var body: some View {
        HStack(spacing: 10) {
            Text(time.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.caption.weight(.heavy))
                .foregroundStyle(Palette.ink)
                .frame(width: 50, alignment: .trailing)
            Capsule()
                .fill(Palette.commute)
                .frame(height: 2)
        }
        .frame(height: 20)
        .padding(.leading, 4)
        .padding(.trailing, 12)
    }
}

struct TimelineRow: View {
    let block: TimelineBlock
    let done: Bool
    let badge: String?
    let onToggle: () -> Void

    private var timeLabel: String {
        var s = block.start.formatted(date: .omitted, time: .shortened)
        if let end = block.end {
            s += " – " + end.formatted(date: .omitted, time: .shortened)
        }
        if block.isEstimate { s += " · est." }
        return s
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(block.start.formatted(.dateTime.hour(.defaultDigits(amPM: .omitted)).minute()))
                .font(.caption)
                .foregroundStyle(Palette.muted)
                .frame(width: 50, alignment: .trailing)
                .padding(.top, 14)

            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(done ? block.category.color : Palette.circle)
                    Image(systemName: block.symbol)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(done ? Palette.onAccent : block.category.color)
                }
                .frame(width: 44, height: 44)
                VLine()
                    .stroke(block.category.color.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    .frame(width: 2)
                    .frame(minHeight: 12, maxHeight: .infinity)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(timeLabel)
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
                Text(block.title)
                    .font(.body.weight(.bold))
                    .foregroundStyle(done ? Palette.faint : Palette.ink)
                    .strikethrough(done)
                if !block.subtitle.isEmpty {
                    Text(block.subtitle)
                        .font(.footnote)
                        .foregroundStyle(Palette.muted)
                }
                if let badge {
                    Text(badge)
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(Palette.onAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Palette.commute, in: Capsule())
                        .padding(.top, 4)
                }
            }
            .padding(.top, 2)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(block.category.color, lineWidth: 2)
                        .background(Circle().fill(done ? block.category.color : Color.clear))
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(Palette.onAccent)
                    }
                }
                .frame(width: 26, height: 26)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark \(block.title) not done" : "Mark \(block.title) done")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.leading, 4)
    }
}
