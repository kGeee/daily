import SwiftUI
import SwiftData

enum EventRepeat: String, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, biweekly, monthly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "Never"
        case .daily: return "Every day"
        case .weekdays: return "Weekdays"
        case .weekly: return "Every week"
        case .biweekly: return "Every 2 weeks"
        case .monthly: return "Every month"
        }
    }
}

enum EventKind: String, CaseIterable, Identifiable {
    case general, food, gym, commute, sleep, work
    var id: String { rawValue }
    var title: String {
        switch self {
        case .general: return "Other"
        case .food: return "Food"
        case .gym: return "Gym"
        case .commute: return "Travel"
        case .sleep: return "Rest"
        case .work: return "Work"
        }
    }
    var category: BlockCategory {
        switch self {
        case .general: return .general
        case .food: return .food
        case .gym: return .gym
        case .commute: return .commute
        case .sleep: return .sleep
        case .work: return .work
        }
    }
    var symbol: String {
        switch self {
        case .general: return "star.fill"
        case .food: return "fork.knife"
        case .gym: return "dumbbell.fill"
        case .commute: return "car.fill"
        case .sleep: return "moon.fill"
        case .work: return "briefcase.fill"
        }
    }
}

/// Something you add to the timeline yourself (a dinner, an appointment, a call).
@Model
final class CustomEvent {
    var id: UUID
    var title: String
    var note: String
    var start: Date
    var durationMinutes: Int
    var kindRaw: String
    var repeatRaw: String
    var remind: Bool

    init(title: String, note: String = "", start: Date, durationMinutes: Int,
         kind: EventKind, repeats: EventRepeat, remind: Bool) {
        self.id = UUID()
        self.title = title
        self.note = note
        self.start = start
        self.durationMinutes = durationMinutes
        self.kindRaw = kind.rawValue
        self.repeatRaw = repeats.rawValue
        self.remind = remind
    }

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .general }
    var repeats: EventRepeat { EventRepeat(rawValue: repeatRaw) ?? .none }

    /// Whether this event happens on the given day.
    func occurs(on day: Date) -> Bool {
        let cal = Calendar.current
        let firstDay = cal.startOfDay(for: start)
        let target = cal.startOfDay(for: day)
        guard target >= firstDay else { return false }
        switch repeats {
        case .none:
            return target == firstDay
        case .daily:
            return true
        case .weekdays:
            let weekday = cal.component(.weekday, from: target)
            return (2...6).contains(weekday)
        case .weekly:
            return cal.component(.weekday, from: target) == cal.component(.weekday, from: firstDay)
        case .biweekly:
            let days = cal.dateComponents([.day], from: firstDay, to: target).day ?? 0
            return days % 14 == 0
        case .monthly:
            // Same date each month; on the 29th–31st it falls on the last day of shorter months.
            let wanted = cal.component(.day, from: firstDay)
            let day = cal.component(.day, from: target)
            let monthLength = cal.range(of: .day, in: .month, for: target)?.count ?? 31
            return day == min(wanted, monthLength)
        }
    }

    /// This event as a timeline block on the given day.
    func block(on day: Date) -> TimelineBlock {
        let cal = Calendar.current
        let parts = cal.dateComponents([.hour, .minute], from: start)
        let begin = cal.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? day
        let end = durationMinutes > 0 ? begin.addingTimeInterval(Double(durationMinutes) * 60) : nil
        return TimelineBlock(id: "event-" + id.uuidString, start: begin, end: end, title: title,
                             subtitle: note, category: kind.category, symbol: kind.symbol,
                             eventID: id)
    }
}

struct EventEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let event: CustomEvent?

    @State private var title: String
    @State private var note: String
    @State private var start: Date
    @State private var duration: Int
    @State private var kind: EventKind
    @State private var repeats: EventRepeat
    @State private var remind: Bool

    private let durations = [0, 15, 30, 45, 60, 90, 120, 180]

    init(event: CustomEvent?, defaultDay: Date) {
        self.event = event
        let cal = Calendar.current
        let suggested: Date = {
            if cal.isDateInToday(defaultDay) {
                // Next half hour from now.
                let now = Date()
                let minute = cal.component(.minute, from: now)
                let bump = minute < 30 ? 30 - minute : 60 - minute
                return cal.date(byAdding: .minute, value: bump, to: now) ?? now
            }
            return cal.date(bySettingHour: 18, minute: 0, second: 0, of: defaultDay) ?? defaultDay
        }()
        _title = State(initialValue: event?.title ?? "")
        _note = State(initialValue: event?.note ?? "")
        _start = State(initialValue: event?.start ?? suggested)
        _duration = State(initialValue: event?.durationMinutes ?? 60)
        _kind = State(initialValue: event?.kind ?? .general)
        _repeats = State(initialValue: event?.repeats ?? .none)
        _remind = State(initialValue: event?.remind ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What is it?", text: $title)
                    TextField("Note (optional)", text: $note)
                }
                Section {
                    DatePicker("Starts", selection: $start)
                    Picker("Length", selection: $duration) {
                        ForEach(durations, id: \.self) { minutes in
                            Text(label(for: minutes)).tag(minutes)
                        }
                    }
                    Picker("Repeat", selection: $repeats) {
                        ForEach(EventRepeat.allCases) { r in Text(r.title).tag(r) }
                    }
                }
                Section {
                    Picker("Type", selection: $kind) {
                        ForEach(EventKind.allCases) { k in
                            Label(k.title, systemImage: k.symbol).tag(k)
                        }
                    }
                    Toggle("Remind me 10 min before", isOn: $remind)
                }
                if let event {
                    Section {
                        Button("Delete event", role: .destructive) {
                            context.delete(event)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(event == nil ? "New event" : "Edit event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func label(for minutes: Int) -> String {
        if minutes == 0 { return "No end time" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if let event {
            event.title = trimmed
            event.note = note
            event.start = start
            event.durationMinutes = duration
            event.kindRaw = kind.rawValue
            event.repeatRaw = repeats.rawValue
            event.remind = remind
        } else {
            context.insert(CustomEvent(title: trimmed, note: note, start: start, durationMinutes: duration,
                                       kind: kind, repeats: repeats, remind: remind))
        }
        dismiss()
    }
}
