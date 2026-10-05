import Foundation

/// Works out what's happening right now from the timeline items.
/// Shared by the app's Now card, the Now widget and the Lock Screen Live Activity.
enum NowPlan {
    /// Blocks without an end time (lunch, wake up, wind down) count as this long.
    static let defaultLength: TimeInterval = 30 * 60
    /// With nothing on right now, the next thing shows as "up next" if it starts within this window.
    static let upcomingWindow: TimeInterval = 2 * 60 * 60

    struct State: Equatable {
        /// What you're in the middle of (the most recently started block, so lunch shows over work).
        var current: SharedStore.Item?
        /// The next thing that hasn't started yet.
        var next: SharedStore.Item?
    }

    static func end(of item: SharedStore.Item) -> Date {
        if let end = item.end, end > item.start { return end }
        return item.start.addingTimeInterval(defaultLength)
    }

    static func state(at date: Date, items: [SharedStore.Item]) -> State {
        let open = items.filter { !$0.done }
        let current = open
            .filter { $0.start <= date && end(of: $0) > date }
            .max { a, b in
                // Later start wins; for the same start, the shorter block wins.
                a.start != b.start ? a.start < b.start : end(of: a) > end(of: b)
            }
        let next = open
            .filter { $0.start > date }
            .min { $0.start < $1.start }
        return State(current: current, next: next)
    }

    /// 0...1, how far through the item you are.
    static func progress(of item: SharedStore.Item, at date: Date) -> Double {
        let total = end(of: item).timeIntervalSince(item.start)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(item.start) / total, 0), 1)
    }

    /// Whole minutes left, rounded up (so it never says 0 while something is still on).
    static func minutesLeft(in item: SharedStore.Item, at date: Date) -> Int {
        let seconds = end(of: item).timeIntervalSince(date)
        return max(Int((seconds / 60).rounded(.up)), 0)
    }

    /// "1h 20m left", "12 min left".
    static func leftLabel(minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h)h left" : "\(h)h \(m)m left"
        }
        return "\(minutes) min left"
    }

    /// Every moment after `date` when what's "now" can change (starts and ends), sorted.
    static func changeDates(after date: Date, items: [SharedStore.Item]) -> [Date] {
        let all = items.filter { !$0.done }.flatMap { [$0.start, end(of: $0)] }.filter { $0 > date }
        return Array(Set(all)).sorted()
    }
}

extension NowPlan {
    /// "45m", "1h 20m".
    static func shortDuration(minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(max(minutes, 0))m"
    }

    /// Text for the Mac menu bar: "Groceries · 32m" while something's on, "Gym in 45m" when it's next
    /// within the upcoming window, or nil to show just the icon.
    static func menuBarTitle(for state: State, at date: Date, maxTitle: Int = 18) -> String? {
        func clip(_ s: String) -> String { s.count > maxTitle ? String(s.prefix(maxTitle - 1)) + "…" : s }
        if let current = state.current {
            return clip(current.title) + " · " + shortDuration(minutes: minutesLeft(in: current, at: date))
        }
        if let next = state.next, next.start.timeIntervalSince(date) <= upcomingWindow {
            let minutes = Int((next.start.timeIntervalSince(date) / 60).rounded(.up))
            return clip(next.title) + " in " + shortDuration(minutes: minutes)
        }
        return nil
    }
}
