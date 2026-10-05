import Foundation
import SwiftData

/// One pomodoro focus round you worked (finished or stopped early, at least a minute long).
@Model
final class FocusSession {
    var id: UUID = UUID()
    var label: String = ""
    var start: Date = Date()
    var end: Date = Date()
    var seconds: Int = 0
    var completed: Bool = false

    init(label: String, start: Date, end: Date, seconds: Int, completed: Bool) {
        self.id = UUID()
        self.label = label
        self.start = start
        self.end = end
        self.seconds = seconds
        self.completed = completed
    }

    var minutes: Int { seconds / 60 }
}

/// Focus minutes on one day (for the week chart).
struct DayMinutes: Identifiable, Equatable {
    let day: Date
    let minutes: Int
    var id: Date { day }
}

/// Numbers for the Focus screen.
enum FocusStats {
    static func sessions(on day: Date, in sessions: [FocusSession]) -> [FocusSession] {
        let cal = Calendar.current
        return sessions.filter { cal.isDate($0.start, inSameDayAs: day) }
    }

    static func minutes(on day: Date, in sessions: [FocusSession]) -> Int {
        self.sessions(on: day, in: sessions).reduce(0) { $0 + $1.seconds } / 60
    }

    /// Finished rounds on a day (stopped-early ones don't count).
    static func rounds(on day: Date, in sessions: [FocusSession]) -> Int {
        self.sessions(on: day, in: sessions).filter(\.completed).count
    }

    /// Minutes per day for the last `days` days, oldest first, ending today.
    static func daily(days: Int, endingOn today: Date, in sessions: [FocusSession]) -> [DayMinutes] {
        let cal = Calendar.current
        let end = cal.startOfDay(for: today)
        return (0..<days).reversed().compactMap { back -> DayMinutes? in
            guard let day = cal.date(byAdding: .day, value: -back, to: end) else { return nil }
            return DayMinutes(day: day, minutes: FocusStats.minutes(on: day, in: sessions))
        }
    }

    /// Days in a row with at least one focus session, counting back from today
    /// (today not having one yet doesn't break the streak).
    static func streak(endingOn today: Date, in sessions: [FocusSession]) -> Int {
        let cal = Calendar.current
        let days = Set(sessions.map { cal.startOfDay(for: $0.start) })
        var day = cal.startOfDay(for: today)
        if !days.contains(day) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var count = 0
        while days.contains(day) {
            count += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return count
    }
}
