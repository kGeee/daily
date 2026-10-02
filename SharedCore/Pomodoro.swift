import Foundation

/// Pomodoro timer rules. The running timer lives in the App Group (`SharedStore.activeFocus`)
/// so the Lock Screen card and widgets can show it too.
enum Pomodoro {
    enum Phase: String, Codable, CaseIterable {
        case focus, shortBreak, longBreak

        var title: String {
            switch self {
            case .focus: return "Focus"
            case .shortBreak: return "Short break"
            case .longBreak: return "Long break"
            }
        }

        var symbol: String {
            switch self {
            case .focus: return "timer"
            case .shortBreak: return "cup.and.saucer.fill"
            case .longBreak: return "figure.walk"
            }
        }

        var isBreak: Bool { self != .focus }
    }

    struct Settings: Equatable {
        var focusMinutes = 25
        var shortBreakMinutes = 5
        var longBreakMinutes = 15
        /// A long break after this many focus rounds.
        var roundsPerSet = 4

        static let focusKey = "pomo.focusMinutes"
        static let shortKey = "pomo.shortBreakMinutes"
        static let longKey = "pomo.longBreakMinutes"
        static let roundsKey = "pomo.roundsPerSet"

        /// The user's settings (kept in the App Group so the Lock Screen card agrees with the app).
        static func load() -> Settings {
            let d = SharedStore.defaults
            func value(_ key: String, _ fallback: Int) -> Int {
                let v = d.integer(forKey: key)
                return v > 0 ? v : fallback
            }
            return Settings(focusMinutes: value(focusKey, 25), shortBreakMinutes: value(shortKey, 5),
                            longBreakMinutes: value(longKey, 15), roundsPerSet: value(roundsKey, 4))
        }

        func minutes(for phase: Phase) -> Int {
            switch phase {
            case .focus: return focusMinutes
            case .shortBreak: return shortBreakMinutes
            case .longBreak: return longBreakMinutes
            }
        }
    }

    /// A timer that's running or paused.
    struct Active: Codable, Equatable {
        var phase: Phase
        var label: String
        /// Which focus round of the set this is (1...roundsPerSet).
        var round: Int
        /// When this phase was first started (for the history).
        var startedAt: Date
        /// When it will finish if it keeps running.
        var end: Date
        /// Full length of the phase, in seconds.
        var planned: TimeInterval
        /// Seconds left when paused; nil while running.
        var pausedRemaining: TimeInterval?

        var isPaused: Bool { pausedRemaining != nil }
        /// The start that makes progress bars line up after a pause (end minus full length).
        var virtualStart: Date { end.addingTimeInterval(-planned) }
    }

    static func start(_ phase: Phase, label: String, round: Int, settings: Settings, at now: Date) -> Active {
        let planned = TimeInterval(max(settings.minutes(for: phase), 1) * 60)
        return Active(phase: phase, label: label, round: round, startedAt: now,
                      end: now.addingTimeInterval(planned), planned: planned, pausedRemaining: nil)
    }

    static func remaining(_ active: Active, at now: Date) -> TimeInterval {
        active.pausedRemaining ?? max(active.end.timeIntervalSince(now), 0)
    }

    static func isFinished(_ active: Active, at now: Date) -> Bool {
        !active.isPaused && active.end <= now
    }

    static func progress(_ active: Active, at now: Date) -> Double {
        guard active.planned > 0 else { return 1 }
        return min(max(1 - remaining(active, at: now) / active.planned, 0), 1)
    }

    /// Seconds actually spent so far.
    static func elapsed(_ active: Active, at now: Date) -> TimeInterval {
        active.planned - remaining(active, at: now)
    }

    static func pause(_ active: Active, at now: Date) -> Active {
        guard !active.isPaused else { return active }
        var copy = active
        copy.pausedRemaining = max(active.end.timeIntervalSince(now), 0)
        return copy
    }

    static func resume(_ active: Active, at now: Date) -> Active {
        guard let left = active.pausedRemaining else { return active }
        var copy = active
        copy.end = now.addingTimeInterval(left)
        copy.pausedRemaining = nil
        return copy
    }

    /// What comes after a phase: focus → short break (long break after the last round) → next focus round.
    static func next(after phase: Phase, round: Int, settings: Settings) -> (phase: Phase, round: Int) {
        switch phase {
        case .focus:
            return round >= max(settings.roundsPerSet, 1) ? (.longBreak, round) : (.shortBreak, round)
        case .shortBreak:
            return (.focus, round + 1)
        case .longBreak:
            return (.focus, 1)
        }
    }

    /// "12:05" or "1:02:05".
    static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

extension SharedStore {
    private static let activeFocusKey = "activeFocus"
    private static let stoppedFocusKey = "stoppedFocus"

    static var activeFocus: Pomodoro.Active? {
        get {
            guard let data = defaults.data(forKey: activeFocusKey) else { return nil }
            return try? JSONDecoder().decode(Pomodoro.Active.self, from: data)
        }
        set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: activeFocusKey)
            } else {
                defaults.removeObject(forKey: activeFocusKey)
            }
        }
    }

    /// A timer stopped from the Lock Screen, waiting for the app to log it.
    struct StoppedFocus: Codable {
        var active: Pomodoro.Active
        var stoppedAt: Date
    }

    static func stopFocusFromLockScreen(at date: Date = Date()) {
        guard let active = activeFocus else { return }
        if let data = try? JSONEncoder().encode(StoppedFocus(active: active, stoppedAt: date)) {
            defaults.set(data, forKey: stoppedFocusKey)
        }
        activeFocus = nil
    }

    static func takeStoppedFocus() -> StoppedFocus? {
        guard let data = defaults.data(forKey: stoppedFocusKey) else { return nil }
        defaults.removeObject(forKey: stoppedFocusKey)
        return try? JSONDecoder().decode(StoppedFocus.self, from: data)
    }
}
