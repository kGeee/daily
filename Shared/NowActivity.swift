import Foundation
#if os(iOS)
import ActivityKit
#endif
import AppIntents
import WidgetKit
import UserNotifications

/// The Lock Screen / Dynamic Island card for whatever you're doing right now.
/// (Live Activities are iPhone only; on the Mac the same content drives the menu bar.)
#if os(iOS)
struct NowAttributes: ActivityAttributes {
    typealias ContentState = NowContentState
}
#else
struct NowAttributes {
    typealias ContentState = NowContentState
}
#endif

struct NowContentState: Codable, Hashable {
    /// Timeline item id (dayKey|blockID), used by the Done button.
    var itemID: String
    var title: String
    var subtitle: String
    var symbol: String
    /// commute, gym, food, sleep, work, general
    var category: String
    var start: Date
    /// When it ends (or, when `isUpcoming`, when it starts).
    var end: Date
    /// Nothing is on right now; this is the next thing, counting down to its start.
    var isUpcoming: Bool
    var nextTitle: String?
    var nextSymbol: String?
    var nextStart: Date?
    /// Set while a pomodoro is paused: seconds left, shown instead of a running timer.
    var pausedRemaining: Double? = nil
}

/// Starts, updates and ends the "Now" Live Activity from the shared timeline.
enum NowActivity {
    /// The item id used for a running pomodoro.
    static let focusItemID = "focus"
    /// Notification id for "pomodoro finished".
    static let focusNotificationID = "daily.focus.end"

    /// What the Live Activity should show, or nil when there's nothing on or coming up soon.
    static func content(for state: NowPlan.State, at date: Date,
                        focus: Pomodoro.Active? = nil) -> NowAttributes.ContentState? {
        // A running pomodoro takes over the card.
        if let focus, focus.isPaused || focus.end > date {
            let label = focus.label.trimmingCharacters(in: .whitespaces)
            let next = Pomodoro.next(after: focus.phase, round: focus.round, settings: Pomodoro.Settings.load())
            return NowAttributes.ContentState(
                itemID: focusItemID,
                title: focus.phase == .focus ? (label.isEmpty ? "Focus" : label) : focus.phase.title,
                subtitle: focus.phase == .focus ? "Pomodoro · round \(focus.round)" : "Pomodoro break",
                symbol: focus.phase.symbol, category: focus.phase == .focus ? "focus" : "break",
                start: focus.virtualStart, end: focus.end, isUpcoming: false,
                nextTitle: next.phase.title, nextSymbol: next.phase.symbol, nextStart: focus.end,
                pausedRemaining: focus.pausedRemaining)
        }
        if let current = state.current {
            return NowAttributes.ContentState(
                itemID: current.id, title: current.title, subtitle: current.subtitle,
                symbol: current.symbol, category: current.category,
                start: current.start, end: NowPlan.end(of: current), isUpcoming: false,
                nextTitle: state.next?.title, nextSymbol: state.next?.symbol, nextStart: state.next?.start)
        }
        if let next = state.next, next.start.timeIntervalSince(date) <= NowPlan.upcomingWindow {
            return NowAttributes.ContentState(
                itemID: next.id, title: next.title, subtitle: next.subtitle,
                symbol: next.symbol, category: next.category,
                start: next.start.addingTimeInterval(-NowPlan.upcomingWindow), end: next.start, isUpcoming: true,
                nextTitle: nil, nextSymbol: nil, nextStart: nil)
        }
        return nil
    }

    #if os(iOS)
    static var isRunning: Bool { !Activity<NowAttributes>.activities.isEmpty }

    /// Brings the Live Activity in line with the timeline. Call whenever the timeline or check-offs change.
    static func sync(at date: Date = Date()) async {
        let activities = Activity<NowAttributes>.activities
        guard SharedStore.nowActivityEnabled,
              ActivityAuthorizationInfo().areActivitiesEnabled,
              let state = content(for: NowPlan.state(at: date, items: SharedStore.currentItems()), at: date,
                                  focus: SharedStore.activeFocus) else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }
        // Once it ends, the card switches to "up next" by itself (see the widget's stale view).
        let content = ActivityContent(state: state, staleDate: state.pausedRemaining == nil ? state.end : nil)
        if let first = activities.first {
            if first.content.state != state { await first.update(content) }
            for extra in activities.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
        } else {
            _ = try? Activity.request(attributes: NowAttributes(), content: content, pushType: nil)
        }
    }
    #else
    static var isRunning: Bool { false }
    static func sync(at date: Date = Date()) async {}
    #endif
}

#if os(iOS)

/// "Done" on the Lock Screen card: checks the item off and moves the card on to what's next.
struct NowDoneIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Done"
    static var isDiscoverable: Bool = false

    @Parameter(title: "Item")
    var itemID: String

    init() {}

    init(itemID: String) {
        self.itemID = itemID
    }

    func perform() async throws -> some IntentResult {
        if itemID == NowActivity.focusItemID {
            SharedStore.stopFocusFromLockScreen()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [NowActivity.focusNotificationID])
        } else if SharedStore.currentItems().first(where: { $0.id == itemID })?.done == false {
            SharedStore.togglePendingCheck(itemID)
        }
        await NowActivity.sync()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// "Refresh" on a finished Lock Screen card: moves it on to whatever is happening now.
struct NowRefreshIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update"
    static var isDiscoverable: Bool = false

    init() {}

    func perform() async throws -> some IntentResult {
        await NowActivity.sync()
        return .result()
    }
}
#endif
