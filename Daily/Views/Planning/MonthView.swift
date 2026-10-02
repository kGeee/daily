import SwiftUI
import SwiftData

/// The days to draw for a month grid: `nil` for the blank cells before the 1st.
enum MonthGrid {
    static func cells(for month: Date, calendar cal: Calendar = .current) -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: month),
              let length = cal.range(of: .day, in: .month, for: month)?.count else { return [] }
        let first = interval.start
        let weekday = cal.component(.weekday, from: first)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for offset in 0..<length {
            cells.append(cal.date(byAdding: .day, value: offset, to: first))
        }
        return cells
    }

    /// Short weekday names in the calendar's order (S M T W T F S, or starting Monday).
    static func weekdaySymbols(calendar cal: Calendar = .current) -> [String] {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let start = cal.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    /// Events on a day, earliest first.
    static func events(on day: Date, from events: [CustomEvent]) -> [CustomEvent] {
        let cal = Calendar.current
        func minutes(_ e: CustomEvent) -> Int {
            let parts = cal.dateComponents([.hour, .minute], from: e.start)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }
        return events.filter { $0.occurs(on: day) }.sorted { minutes($0) < minutes($1) }
    }
}

/// Plan the month: see what's on each day and add things ahead of time.
struct MonthView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var events: [CustomEvent]
    @Query private var overrides: [DayTypeOverride]
    @AppStorage("weekPattern") private var pattern = MySchedule.defaultPattern

    /// Set to jump Today to the chosen day.
    var openDay: ((Date) -> Void)? = nil

    @State private var month = Calendar.current.startOfDay(for: .now)
    @State private var selected = Calendar.current.startOfDay(for: .now)
    @State private var newEventDay: DayRef?
    @State private var editingEvent: CustomEvent?

    init(openDay: ((Date) -> Void)? = nil) {
        self.openDay = openDay
    }

    private var planner: DayPlanner { DayPlanner(pattern: pattern, overrides: overrides) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    monthHeader
                    grid.card(padding: 12)
                    dayCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 30)
            }
            .background(Palette.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $newEventDay) { day in
            EventEditor(event: nil, defaultDay: day.date)
        }
        .sheet(item: $editingEvent) { event in
            EventEditor(event: event, defaultDay: selected)
        }
    }

    private var monthHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                SectionLabel(text: month.formatted(.dateTime.year()))
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(.system(size: 30, weight: .heavy))
                    .foregroundStyle(Palette.ink)
            }
            Spacer()
            circleButton("chevron.left") { shift(-1) }
                .accessibilityLabel("Previous month")
            circleButton("chevron.right") { shift(1) }
                .accessibilityLabel("Next month")
        }
        .padding(.top, 8)
    }

    private func circleButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .frame(width: 36, height: 36)
                .background(Palette.card, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private var grid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let cells = MonthGrid.cells(for: month)
        return VStack(spacing: 6) {
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(MonthGrid.weekdaySymbols().enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Palette.faint)
                }
            }
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 52)
                    }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let cal = Calendar.current
        let isSelected = cal.isDate(day, inSameDayAs: selected)
        let isToday = cal.isDateInToday(day)
        let dayEvents = MonthGrid.events(on: day, from: events)
        let type = planner.type(for: day)
        return Button {
            selected = cal.startOfDay(for: day)
        } label: {
            VStack(spacing: 3) {
                Text(day.formatted(.dateTime.day()))
                    .font(.system(size: 15, weight: isToday || isSelected ? .heavy : .semibold))
                    .foregroundStyle(isSelected ? Palette.onAccent : (isToday ? Palette.commuteText : Palette.ink))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(isSelected ? Palette.commute : Color.clear))
                HStack(spacing: 2) {
                    ForEach(Array(dayEvents.prefix(3).enumerated()), id: \.offset) { _, event in
                        Circle().fill(event.kind.category.color).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
                Capsule()
                    .fill(type?.color.opacity(0.55) ?? Color.clear)
                    .frame(width: 18, height: 3)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted)
                            + (dayEvents.isEmpty ? "" : ", \(dayEvents.count) events"))
    }

    private var dayCard: some View {
        let dayEvents = MonthGrid.events(on: selected, from: events)
        let type = planner.type(for: selected)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.system(size: 20, weight: .heavy))
                        .foregroundStyle(Palette.ink)
                    Text(type?.title ?? "Day off")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(type?.color ?? Palette.muted)
                }
                Spacer()
                if let openDay {
                    Button("Open day") {
                        openDay(selected)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.commuteText)
                }
            }
            if dayEvents.isEmpty {
                Text("Nothing scheduled yet")
                    .font(.subheadline)
                    .foregroundStyle(Palette.muted)
            } else {
                ForEach(dayEvents) { event in
                    Button {
                        editingEvent = event
                    } label: {
                        eventRow(event)
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                newEventDay = DayRef(date: selected)
            } label: {
                Label("Add to " + selected.formatted(.dateTime.month(.abbreviated).day()), systemImage: "plus")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Palette.commute, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func eventRow(_ event: CustomEvent) -> some View {
        let block = event.block(on: selected)
        return HStack(spacing: 12) {
            Image(systemName: event.kind.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(event.kind.category.color)
                .frame(width: 36, height: 36)
                .background(Palette.circle, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Text(timeLabel(block) + (event.repeats == .none ? "" : " · " + event.repeats.title))
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(Palette.faint)
        }
        .contentShape(Rectangle())
    }

    private func timeLabel(_ block: TimelineBlock) -> String {
        let start = block.start.formatted(date: .omitted, time: .shortened)
        guard let end = block.end else { return start }
        return start + " – " + end.formatted(date: .omitted, time: .shortened)
    }

    private func shift(_ months: Int) {
        let cal = Calendar.current
        guard let moved = cal.date(byAdding: .month, value: months, to: month) else { return }
        month = moved
        // Keep the selection inside the month you're looking at.
        if !cal.isDate(selected, equalTo: moved, toGranularity: .month) {
            selected = cal.isDate(moved, equalTo: .now, toGranularity: .month)
                ? cal.startOfDay(for: .now)
                : (cal.dateInterval(of: .month, for: moved)?.start ?? moved)
        }
    }
}

/// A day to open the event editor on (sheet(item:) needs something Identifiable).
struct DayRef: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSinceReferenceDate }
}
