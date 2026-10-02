import Foundation
import SwiftData
import UserNotifications
import WidgetKit

/// Starts, pauses and stops the pomodoro timer, and logs finished focus rounds.
@MainActor
enum FocusController {
    /// What to start next (saved so the Focus screen can offer it after a phase finishes).
    static let nextPhaseKey = "pomo.nextPhase"
    static let nextRoundKey = "pomo.nextRound"

    nonisolated static var nextUp: (phase: Pomodoro.Phase, round: Int) {
        let d = UserDefaults.standard
        let phase = Pomodoro.Phase(rawValue: d.string(forKey: nextPhaseKey) ?? "") ?? .focus
        let round = d.integer(forKey: nextRoundKey)
        return (phase, max(round, 1))
    }

    nonisolated static func setNextUp(_ phase: Pomodoro.Phase, round: Int) {
        UserDefaults.standard.set(phase.rawValue, forKey: nextPhaseKey)
        UserDefaults.standard.set(round, forKey: nextRoundKey)
    }

    static func start(_ phase: Pomodoro.Phase, label: String, round: Int, at now: Date = Date()) {
        let active = Pomodoro.start(phase, label: label, round: round, settings: .load(), at: now)
        SharedStore.activeFocus = active
        scheduleNotification(for: active, at: now)
        refresh()
    }

    static func pause(at now: Date = Date()) {
        guard let active = SharedStore.activeFocus else { return }
        SharedStore.activeFocus = Pomodoro.pause(active, at: now)
        cancelNotification()
        refresh()
    }

    static func resume(at now: Date = Date()) {
        guard let active = SharedStore.activeFocus else { return }
        let resumed = Pomodoro.resume(active, at: now)
        SharedStore.activeFocus = resumed
        scheduleNotification(for: resumed, at: now)
        refresh()
    }

    /// Ends the current phase early. Focus time already spent is still logged.
    static func stop(context: ModelContext, at now: Date = Date()) {
        guard let active = SharedStore.activeFocus else { return }
        log(active, until: now, context: context)
        SharedStore.activeFocus = nil
        let next = Pomodoro.next(after: active.phase, round: active.round, settings: .load())
        setNextUp(next.phase, round: next.round)
        cancelNotification()
        refresh()
    }

    /// Skips straight to what comes after the current phase (or the next-up one when idle).
    static func skip(context: ModelContext, at now: Date = Date()) {
        if let active = SharedStore.activeFocus {
            log(active, until: now, context: context)
            SharedStore.activeFocus = nil
            let next = Pomodoro.next(after: active.phase, round: active.round, settings: .load())
            setNextUp(next.phase, round: next.round)
        } else {
            let current = nextUp
            let next = Pomodoro.next(after: current.phase, round: current.round, settings: .load())
            setNextUp(next.phase, round: next.round)
        }
        cancelNotification()
        refresh()
    }

    /// Logs a timer that finished (or was stopped from the Lock Screen) while you weren't looking.
    /// Returns true if something changed.
    @discardableResult
    static func settle(context: ModelContext, at now: Date = Date()) -> Bool {
        var changed = false
        if let stopped = SharedStore.takeStoppedFocus() {
            log(stopped.active, until: stopped.stoppedAt, context: context)
            let next = Pomodoro.next(after: stopped.active.phase, round: stopped.active.round, settings: .load())
            setNextUp(next.phase, round: next.round)
            changed = true
        }
        if let active = SharedStore.activeFocus, Pomodoro.isFinished(active, at: now) {
            log(active, until: active.end, context: context)
            SharedStore.activeFocus = nil
            let next = Pomodoro.next(after: active.phase, round: active.round, settings: .load())
            setNextUp(next.phase, round: next.round)
            changed = true
        }
        if changed { refresh() }
        return changed
    }

    /// Only focus rounds of a minute or more go in the history.
    static func log(_ active: Pomodoro.Active, until end: Date, context: ModelContext) {
        guard active.phase == .focus else { return }
        let seconds = Int(Pomodoro.elapsed(active, at: end).rounded())
        guard seconds >= 60 else { return }
        context.insert(FocusSession(label: active.label.trimmingCharacters(in: .whitespaces),
                                    start: active.startedAt, end: end, seconds: seconds,
                                    completed: Double(seconds) >= active.planned - 1))
    }

    private static func refresh() {
        Task { await NowActivity.sync() }
        WidgetCenter.shared.reloadTimelines(ofKind: "Now")
    }

    // MARK: Notification when the phase ends

    private static func scheduleNotification(for active: Pomodoro.Active, at now: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [NowActivity.focusNotificationID])
        let seconds = Pomodoro.remaining(active, at: now)
        guard seconds >= 1 else { return }
        let settings = Pomodoro.Settings.load()
        let next = Pomodoro.next(after: active.phase, round: active.round, settings: settings)
        let content = UNMutableNotificationContent()
        if active.phase == .focus {
            content.title = "Focus round done"
            content.body = "Nice work. Time for a \(settings.minutes(for: next.phase))-minute \(next.phase == .longBreak ? "long " : "")break."
        } else {
            content.title = "Break's over"
            content.body = "Ready for focus round \(next.round)?"
        }
        content.sound = .default
        let request = UNNotificationRequest(identifier: NowActivity.focusNotificationID, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false))
        Task {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            try? await center.add(request)
        }
    }

    private static func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [NowActivity.focusNotificationID])
    }
}
