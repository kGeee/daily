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
    /// The invite it came from (Partiful, Luma…), if imported.
    var link: String = ""
    var location: String = ""

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
    @Query private var checks: [BlockCheck]

    let event: CustomEvent?
    private let day: Date

    @State private var title: String
    @State private var note: String
    @State private var start: Date
    @State private var duration: Int
    @State private var kind: EventKind
    @State private var repeats: EventRepeat
    @State private var remind: Bool
    @State private var showDate = false
    @State private var showTime = false
    @State private var link: String
    @State private var location: String
    @State private var importLink: ImportLink?
    @State private var savedFromImport = false
    @FocusState private var titleFocused: Bool
    @Environment(\.openURL) private var openURL
    private let isImport: Bool
    private let onSaved: (() -> Void)?

    struct ImportLink: Identifiable { let id = UUID(); let url: String }

    private let durations = [0, 15, 30, 45, 60, 90, 120, 180, 240]

    init(event: CustomEvent?, defaultDay: Date, imported: ImportedEvent? = nil, onSaved: (() -> Void)? = nil) {
        self.event = event
        self.day = imported?.start ?? defaultDay
        self.isImport = imported != nil
        self.onSaved = onSaved
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
        _link = State(initialValue: event?.link ?? "")
        _location = State(initialValue: event?.location ?? "")
        if let imported {
            _title = State(initialValue: imported.title)
            _note = State(initialValue: imported.note)
            if let start = imported.start { _start = State(initialValue: start) }
            _duration = State(initialValue: imported.durationMinutes)
            _link = State(initialValue: imported.link)
            _location = State(initialValue: imported.location)
        }
    }

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }

    private var timeText: String {
        let begin = start.formatted(date: .omitted, time: .shortened)
        guard duration > 0 else { return begin }
        return begin + " – " + start.addingTimeInterval(Double(duration) * 60).formatted(date: .omitted, time: .shortened)
    }

    private var relativeDay: String? {
        let cal = Calendar.current
        if cal.isDateInToday(start) { return "Today" }
        if cal.isDateInTomorrow(start) { return "Tomorrow" }
        return nil
    }

    // Check-off for this event on the day it was opened from.
    private var checkKey: (day: String, block: String)? {
        guard let event else { return nil }
        return (DayKey.of(day), "event-" + event.id.uuidString)
    }

    private var isDone: Bool {
        guard let key = checkKey else { return false }
        return checks.contains { $0.dayKey == key.day && $0.blockID == key.block }
    }

    private func toggleDone() {
        guard let key = checkKey else { return }
        if let existing = checks.first(where: { $0.dayKey == key.day && $0.blockID == key.block }) {
            context.delete(existing)
        } else {
            context.insert(BlockCheck(dayKey: key.day, blockID: key.block))
        }
    }

    var body: some View {
        DetailSheetLayout {
            DetailHero(background: kind.category.hero, symbol: kind.symbol, iconColor: kind.category.color,
                       timeText: timeText, badges: repeats == .none ? [] : ["arrow.triangle.2.circlepath"],
                       done: event == nil ? nil : isDone, onToggle: toggleDone,
                       onClose: { dismiss() },
                       trailing: {
                           roundButton("checkmark", label: "Save", action: save)
                               .disabled(trimmedTitle.isEmpty)
                               .opacity(trimmedTitle.isEmpty ? 0.5 : 1)
                       }, title: {
                           TextField("", text: $title, prompt: Text("New event").foregroundStyle(Palette.heroOn.opacity(0.5)))
                               .focused($titleFocused)
                               .submitLabel(.done)
                       })
        } content: {
            if event == nil && !isImport {
                importCard
            }

            DetailCard {
                DetailExpandableRow(symbol: "calendar", tint: kind.category.color,
                                    title: start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year()),
                                    value: relativeDay, expanded: $showDate) {
                    DatePicker("Date", selection: $start, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(kind.category.color)
                }
                DetailDivider()
                DetailExpandableRow(symbol: "clock.fill", tint: kind.category.color, title: timeText,
                                    expanded: $showTime) {
                    DatePicker("Time", selection: $start, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                }
                DetailDivider()
                Menu {
                    Picker("Length", selection: $duration) {
                        ForEach(durations, id: \.self) { minutes in
                            Text(label(for: minutes)).tag(minutes)
                        }
                    }
                } label: {
                    DetailRowLabel(symbol: "hourglass", tint: kind.category.color, title: "Length",
                                   value: label(for: duration))
                }
                DetailDivider()
                Menu {
                    Picker("Repeat", selection: $repeats) {
                        ForEach(EventRepeat.allCases) { r in Text(r.title).tag(r) }
                    }
                } label: {
                    DetailRowLabel(symbol: "arrow.triangle.2.circlepath", tint: kind.category.color,
                                   title: repeats == .none ? "Doesn't repeat" : repeats.title)
                }
                DetailDivider()
                Button {
                    remind.toggle()
                } label: {
                    DetailRowLabel(symbol: remind ? "bell.fill" : "bell.slash", tint: kind.category.color,
                                   title: remind ? "1 Alert" : "No alert",
                                   value: remind ? "10 min before" : "Off", chevron: false)
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: remind)
                inviteRows
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(EventKind.allCases) { k in
                        ChoiceChip(title: k.title, symbol: k.symbol, isOn: kind == k, tint: k.category.color) {
                            withAnimation(.snappy) { kind = k }
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            DetailNotesCard(text: $note)

            if let event {
                DetailDeleteButton(title: "Delete event") {
                    context.delete(event)
                    dismiss()
                }
            } else {
                DetailPrimaryButton(title: "Add to timeline", symbol: "plus", fill: kind.category.color, action: save)
                    .disabled(trimmedTitle.isEmpty)
                    .opacity(trimmedTitle.isEmpty ? 0.5 : 1)
            }
        }
        .onAppear {
            if event == nil && !isImport { titleFocused = true }
        }
        .sheet(item: $importLink, onDismiss: {
            if savedFromImport { dismiss() }
        }) { item in
            ImportEventSheet(link: item.url, onSaved: { savedFromImport = true })
        }
    }

    /// Where it is and the original invite, for imported events.
    @ViewBuilder private var inviteRows: some View {
        if !location.isEmpty {
            DetailDivider()
            Button {
                if let url = MapsApp.url(for: .current, name: location, address: "", latitude: nil, longitude: nil) {
                    openURL(url)
                }
            } label: {
                DetailRowLabel(symbol: "mappin.and.ellipse", tint: kind.category.color, title: location)
            }
            .buttonStyle(.plain)
        }
        if let url = URL(string: link), !link.isEmpty {
            DetailDivider()
            Button {
                openURL(url)
            } label: {
                DetailRowLabel(symbol: "ticket.fill", tint: kind.category.color,
                               title: "Open in " + EventImporter.sourceName(for: link))
            }
            .buttonStyle(.plain)
        }
    }

    /// "Got an invite?" Paste a Partiful or Luma link to fill everything in.
    private var importCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "ticket.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Palette.general)
                .frame(width: 38, height: 38)
                .background(Palette.circle, in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text("Got an invite?")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Palette.ink)
                Text("Paste a Partiful or Luma link")
                    .font(.caption)
                    .foregroundStyle(Palette.muted)
            }
            Spacer()
            PasteButton(payloadType: String.self) { strings in
                guard let text = strings.first, let url = EventImporter.firstLink(in: text) else { return }
                Task { @MainActor in importLink = ImportLink(url: url) }
            }
            .buttonBorderShape(.capsule)
            .labelStyle(.titleOnly)
            .tint(Palette.general)
        }
        .padding(14)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func label(for minutes: Int) -> String {
        if minutes == 0 { return "No end time" }
        if minutes < 60 { return "\(minutes) min" }
        return minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min"
    }

    private func save() {
        let trimmed = trimmedTitle
        guard !trimmed.isEmpty else { return }
        if let event {
            event.title = trimmed
            event.note = note
            event.start = start
            event.durationMinutes = duration
            event.kindRaw = kind.rawValue
            event.repeatRaw = repeats.rawValue
            event.remind = remind
            event.link = link
            event.location = location
        } else {
            let created = CustomEvent(title: trimmed, note: note, start: start, durationMinutes: duration,
                                      kind: kind, repeats: repeats, remind: remind)
            created.link = link
            created.location = location
            context.insert(created)
        }
        onSaved?()
        dismiss()
    }
}
