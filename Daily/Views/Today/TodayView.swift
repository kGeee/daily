import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query private var overrides: [DayTypeOverride]
    @Query private var checks: [BlockCheck]
    @Query private var water: [WaterEntry]
    @Query private var food: [FoodEntry]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern
    @State private var selectedDay = Calendar.current.startOfDay(for: .now)

    private var planner: DayPlanner { DayPlanner(pattern: pattern, overrides: overrides) }
    private var dayKey: String { DayKey.of(selectedDay) }

    var body: some View {
        TimelineView(.everyMinute) { tl in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    WeekStrip(selected: $selectedDay, planner: planner)
                    statsRow
                    timeline(now: tl.date)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Palette.bg.ignoresSafeArea())
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
                 + Text(" oz").foregroundStyle(Palette.muted))
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
        return names.isEmpty ? nil : names.joined(separator: ", ")
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

    private func badge(for block: TimelineBlock, now: Date, isToday: Bool) -> String? {
        guard isToday, block.isDeparture, !isDone(block) else { return nil }
        let minutes = Int(block.start.timeIntervalSince(now) / 60)
        guard minutes >= 0, minutes <= 90 else { return nil }
        return minutes == 0 ? "Leaving now" : "Leave in \(minutes) min"
    }

    private func timeline(now: Date) -> some View {
        let blocks = planner.blocks(for: selectedDay, lunchNote: note(for: .lunch), dinnerNote: note(for: .dinner))
        let isToday = Calendar.current.isDateInToday(selectedDay)
        let nowIndex: Int? = isToday ? (blocks.firstIndex { $0.start > now } ?? blocks.count) : nil

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                if index == nowIndex {
                    NowLine(time: now)
                }
                TimelineRow(block: block,
                            done: isDone(block),
                            badge: badge(for: block, now: now, isToday: isToday)) {
                    toggle(block)
                }
            }
            if nowIndex == blocks.count {
                NowLine(time: now)
            }
        }
        .padding(.vertical, 14)
        .padding(.trailing, 4)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
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
