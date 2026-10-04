import Foundation

/// What the AI sends back when you describe your day out loud.
struct VoicePlan: Decodable {
    struct Item: Decodable {
        var title: String
        var start: String
        var end: String?
        var kind: String?
        var note: String?
    }
    var events: [Item]
    var summary: String?
}

/// An event proposed from what you said, before you add it.
struct EventDraft: Identifiable, Equatable {
    var id = UUID()
    var title: String
    var start: Date
    var end: Date
    var kind: EventKind
    var note: String
    var include = true

    var minutes: Int { max(Int(end.timeIntervalSince(start) / 60), 0) }
}

enum VoicePlanner {
    /// "13:00", "9:30", "1:15 PM" → that time on `day`.
    static func time(_ text: String, on day: Date) -> Date? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).uppercased()
        let isPM = cleaned.hasSuffix("PM"), isAM = cleaned.hasSuffix("AM")
        let digits = cleaned.replacingOccurrences(of: "AM", with: "").replacingOccurrences(of: "PM", with: "")
            .trimmingCharacters(in: .whitespaces)
        let parts = digits.split(separator: ":").map { Int($0) }
        guard let hourPart = parts.first, var hour = hourPart else { return nil }
        let minute = parts.count > 1 ? (parts[1] ?? 0) : 0
        if isPM && hour < 12 { hour += 12 }
        if isAM && hour == 12 { hour = 0 }
        guard (0...24).contains(hour), (0...59).contains(minute) else { return nil }
        let start = Calendar.current.startOfDay(for: day)
        return start.addingTimeInterval(Double(hour * 60 + minute) * 60)
    }

    static func drafts(from plan: VoicePlan, on day: Date) -> [EventDraft] {
        plan.events.compactMap { item in
            let title = item.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty, let start = time(item.start, on: day) else { return nil }
            var end = item.end.flatMap { time($0, on: day) } ?? start.addingTimeInterval(3600)
            if end <= start { end = start.addingTimeInterval(3600) }
            return EventDraft(title: title, start: start, end: end,
                              kind: EventKind(rawValue: item.kind ?? "") ?? .general,
                              note: item.note ?? "")
        }
        .sorted { $0.start < $1.start }
    }

    /// The day's existing timeline, as lines the AI can plan around.
    static func busyLines(_ blocks: [TimelineBlock]) -> [String] {
        blocks.map { b in
            let start = b.start.formatted(date: .omitted, time: .shortened)
            let end = b.end.map { " – " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
            return "- " + start + end + ": " + b.title
        }
    }

    static func prompt(text: String, day: Date, now: Date, blocks: [TimelineBlock]) -> String {
        let cal = Calendar.current
        let dayLabel = day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        let isToday = cal.isDate(day, inSameDayAs: now)
        var lines = [
            "Turn what this person said into calendar events for \(dayLabel).",
            "Right now it's \(now.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))."
        ]
        if isToday {
            lines.append("It's today, so don't schedule anything before \(now.formatted(date: .omitted, time: .shortened)) unless they gave that time.")
        }
        lines.append("They usually wake at \(MySchedule.wake.label) and go to bed around \(MySchedule.bedtime.label).")
        let busy = busyLines(blocks)
        if !busy.isEmpty {
            lines.append("Already on their timeline that day (plan around these, don't repeat them):")
            lines += busy
        }
        lines += [
            "",
            "Rules:",
            "- Keep any times they said exactly. \"1-4\" for a game means 13:00–16:00; small hour numbers mean afternoon/evening unless that makes no sense.",
            "- Give everything else a realistic length and a sensible order (e.g. groceries before meal prep, leave travel time after an outing, gym not right after a big meal, work they want to do \"at night\" goes in the evening).",
            "- Don't overlap events, except quick background tasks like starting laundry.",
            "- Times are 24-hour HH:mm. kind is one of general, food, gym, commute, work, sleep.",
            "- Short titles in plain words; put useful detail in note.",
            "- summary is one or two sentences explaining the order you chose.",
            "",
            "What they said:",
            text
        ]
        return lines.joined(separator: "\n")
    }

    static func plan(text: String, day: Date, now: Date = Date(), blocks: [TimelineBlock]) async throws -> VoicePlan {
        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "events": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "title": ["type": "string"],
                            "start": ["type": "string", "description": "HH:mm, 24-hour"],
                            "end": ["type": "string", "description": "HH:mm, 24-hour"],
                            "kind": ["type": "string", "enum": EventKind.allCases.map(\.rawValue)],
                            "note": ["type": "string"]
                        ] as [String: Any],
                        "required": ["title", "start", "end", "kind"]
                    ] as [String: Any]
                ] as [String: Any],
                "summary": ["type": "string"]
            ] as [String: Any],
            "required": ["events", "summary"]
        ]
        return try await AIClient.structured(prompt: prompt(text: text, day: day, now: now, blocks: blocks),
                                             toolName: "plan_day",
                                             toolDescription: "The events to add to their day",
                                             schema: schema, as: VoicePlan.self, maxTokens: 2048)
    }
}
