import XCTest
@testable import Daily

final class PomodoroTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let settings = Pomodoro.Settings(focusMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15, roundsPerSet: 4)

    func testStartRunsForPhaseLength() {
        let a = Pomodoro.start(.focus, label: "Write", round: 1, settings: settings, at: t0)
        XCTAssertEqual(a.end, t0.addingTimeInterval(25 * 60))
        XCTAssertEqual(Pomodoro.remaining(a, at: t0.addingTimeInterval(60)), 24 * 60)
        XCTAssertFalse(Pomodoro.isFinished(a, at: t0.addingTimeInterval(24 * 60)))
        XCTAssertTrue(Pomodoro.isFinished(a, at: t0.addingTimeInterval(25 * 60)))
    }

    func testPauseFreezesAndResumePushesEndBack() {
        let a = Pomodoro.start(.focus, label: "", round: 1, settings: settings, at: t0)
        let paused = Pomodoro.pause(a, at: t0.addingTimeInterval(10 * 60))
        XCTAssertEqual(Pomodoro.remaining(paused, at: t0.addingTimeInterval(40 * 60)), 15 * 60)
        XCTAssertFalse(Pomodoro.isFinished(paused, at: t0.addingTimeInterval(60 * 60)))

        let resumed = Pomodoro.resume(paused, at: t0.addingTimeInterval(20 * 60))
        XCTAssertEqual(resumed.end, t0.addingTimeInterval(35 * 60))
        XCTAssertEqual(resumed.virtualStart, t0.addingTimeInterval(10 * 60))
        XCTAssertEqual(Pomodoro.progress(resumed, at: t0.addingTimeInterval(20 * 60)), 0.4, accuracy: 0.0001)
        XCTAssertEqual(Pomodoro.elapsed(resumed, at: resumed.end), 25 * 60)
    }

    func testPhaseOrder() {
        func check(_ phase: Pomodoro.Phase, _ round: Int, _ wantPhase: Pomodoro.Phase, _ wantRound: Int,
                   line: UInt = #line) {
            let next = Pomodoro.next(after: phase, round: round, settings: settings)
            XCTAssertEqual(next.phase, wantPhase, line: line)
            XCTAssertEqual(next.round, wantRound, line: line)
        }
        check(.focus, 1, .shortBreak, 1)
        check(.shortBreak, 1, .focus, 2)
        check(.focus, 4, .longBreak, 4)
        check(.longBreak, 4, .focus, 1)
    }

    func testClock() {
        XCTAssertEqual(Pomodoro.clock(25 * 60), "25:00")
        XCTAssertEqual(Pomodoro.clock(65.2), "1:06")
        XCTAssertEqual(Pomodoro.clock(3725), "1:02:05")
    }

    func testLockScreenShowsRunningFocusOverTimeline() {
        let a = Pomodoro.start(.focus, label: "Taxes", round: 2, settings: settings, at: t0)
        let work = SharedStore.Item(blockID: "work", dayKey: "d", title: "Work", subtitle: "", start: t0,
                                    end: t0.addingTimeInterval(3600), symbol: "briefcase.fill", category: "work", done: false)
        let state = NowPlan.state(at: t0.addingTimeInterval(60), items: [work])
        let content = NowActivity.content(for: state, at: t0.addingTimeInterval(60), focus: a)
        XCTAssertEqual(content?.itemID, NowActivity.focusItemID)
        XCTAssertEqual(content?.title, "Taxes")
        XCTAssertEqual(content?.category, "focus")
        XCTAssertEqual(content?.end, a.end)

        // Once it has run out, the timeline shows again.
        let after = NowActivity.content(for: NowPlan.state(at: a.end, items: [work]), at: a.end, focus: a)
        XCTAssertEqual(after?.title, "Work")
    }
}

final class FocusStatsTests: XCTestCase {
    private func session(daysAgo: Int, minutes: Int, completed: Bool = true) -> FocusSession {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: day(0, hour: 10))!
        return FocusSession(label: "", start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                            seconds: minutes * 60, completed: completed)
    }

    func testTodayTotals() {
        let sessions = [session(daysAgo: 0, minutes: 25), session(daysAgo: 0, minutes: 12, completed: false),
                        session(daysAgo: 1, minutes: 25)]
        XCTAssertEqual(FocusStats.minutes(on: day(0), in: sessions), 37)
        XCTAssertEqual(FocusStats.rounds(on: day(0), in: sessions), 1)
    }

    func testDailyIsOldestFirstEndingToday() {
        let sessions = [session(daysAgo: 0, minutes: 25), session(daysAgo: 2, minutes: 50)]
        let week = FocusStats.daily(days: 7, endingOn: day(0), in: sessions)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last?.minutes, 25)
        XCTAssertEqual(week[4].minutes, 50)
    }

    func testStreak() {
        let sessions = [session(daysAgo: 1, minutes: 25), session(daysAgo: 2, minutes: 25), session(daysAgo: 4, minutes: 25)]
        // Nothing yet today doesn't break it.
        XCTAssertEqual(FocusStats.streak(endingOn: day(0), in: sessions), 2)
        XCTAssertEqual(FocusStats.streak(endingOn: day(0), in: sessions + [session(daysAgo: 0, minutes: 5)]), 3)
        XCTAssertEqual(FocusStats.streak(endingOn: day(0), in: [session(daysAgo: 3, minutes: 25)]), 0)
    }
}

final class MonthTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int, hour: Int = 9) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    func testGridStartsOnTheRightWeekday() {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday
        // October 1, 2026 is a Thursday.
        let cells = MonthGrid.cells(for: date(2026, 10, 15), calendar: cal)
        XCTAssertEqual(cells.prefix(4).filter { $0 == nil }.count, 4)
        XCTAssertNotNil(cells[4])
        XCTAssertEqual(cells.compactMap { $0 }.count, 31)

        cal.firstWeekday = 2 // Monday
        XCTAssertEqual(MonthGrid.cells(for: date(2026, 10, 15), calendar: cal).prefix(while: { $0 == nil }).count, 3)
        XCTAssertEqual(MonthGrid.weekdaySymbols(calendar: cal).count, 7)
    }

    func testMonthlyRepeat() {
        let e = CustomEvent(title: "Rent", start: date(2026, 10, 1), durationMinutes: 0, kind: .general,
                            repeats: .monthly, remind: false)
        XCTAssertTrue(e.occurs(on: date(2026, 11, 1)))
        XCTAssertFalse(e.occurs(on: date(2026, 11, 2)))
        XCTAssertFalse(e.occurs(on: date(2026, 9, 1)))
    }

    func testMonthlyOn31stFallsOnLastDay() {
        let e = CustomEvent(title: "Review", start: date(2026, 10, 31), durationMinutes: 0, kind: .general,
                            repeats: .monthly, remind: false)
        XCTAssertTrue(e.occurs(on: date(2026, 11, 30)))
        XCTAssertTrue(e.occurs(on: date(2027, 2, 28)))
        XCTAssertTrue(e.occurs(on: date(2026, 12, 31)))
        XCTAssertFalse(e.occurs(on: date(2026, 12, 30)))
    }

    func testEveryTwoWeeks() {
        let e = CustomEvent(title: "Haircut", start: date(2026, 10, 3), durationMinutes: 30, kind: .general,
                            repeats: .biweekly, remind: false)
        XCTAssertTrue(e.occurs(on: date(2026, 10, 17)))
        XCTAssertFalse(e.occurs(on: date(2026, 10, 10)))
    }

    func testEventsOnDaySortedByTime() {
        let late = CustomEvent(title: "Late", start: date(2026, 10, 5, hour: 20), durationMinutes: 30, kind: .general,
                               repeats: .none, remind: false)
        let early = CustomEvent(title: "Early", start: date(2026, 10, 5, hour: 8), durationMinutes: 30, kind: .general,
                                repeats: .none, remind: false)
        XCTAssertEqual(MonthGrid.events(on: date(2026, 10, 5), from: [late, early]).map(\.title), ["Early", "Late"])
    }
}
