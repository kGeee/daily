import XCTest
@testable import Daily

final class DayScoreTests: XCTestCase {
    func testEmptyDayScoresOnlyEmptyRing() {
        let score = DayScore(ScoreInputs())
        XCTAssertEqual(score.value(.move), 0)
        XCTAssertEqual(score.value(.fuel), 0)
        XCTAssertEqual(score.value(.day), 1, "A ring with nothing in it counts as full")
        XCTAssertEqual(score.score, 33)
        XCTAssertFalse(score.isClosed)
        XCTAssertEqual(score.hint, "Drink 100 oz of water to close Move")
    }

    func testPlannedWorkoutCountsHalfOfMove() {
        var i = ScoreInputs()
        i.waterOz = 120
        i.gymPlanned = true
        let score = DayScore(i)
        XCTAssertEqual(score.items(in: .move).count, 2)
        XCTAssertEqual(score.value(.move), 0.5, accuracy: 0.001)
    }

    func testFullDayCloses() {
        var i = ScoreInputs()
        i.waterOz = 100
        i.workoutDone = true
        i.mainMealsLogged = 3
        i.protein = 150
        i.timelineTotal = 4
        i.timelineDone = 4
        i.checkInExpected = true
        i.checkedIn = true
        let score = DayScore(i)
        XCTAssertTrue(score.isClosed)
        XCTAssertEqual(score.score, 100)
        XCTAssertNil(score.hint)
    }

    func testPartialProgressCounts() {
        var i = ScoreInputs()
        i.waterOz = 100
        i.mainMealsLogged = 2
        i.protein = 70
        i.proteinGoal = 140
        let score = DayScore(i)
        // Fuel = (2/3 + 1/2) / 2
        XCTAssertEqual(score.value(.fuel), (2.0 / 3 + 0.5) / 2, accuracy: 0.001)
        XCTAssertEqual(score.hint, "Reach 140g protein to close Fuel")
    }
}

final class StreakTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        c.firstWeekday = 2 // Monday
        return c
    }()

    private func day(_ s: String) -> Date {
        let parts = s.split(separator: "-").map { Int($0)! }
        return cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    private func range(_ from: String, _ to: String) -> Set<Date> {
        var out = Set<Date>()
        var d = day(from)
        while d <= day(to) {
            out.insert(d)
            d = cal.date(byAdding: .day, value: 1, to: d)!
        }
        return out
    }

    func testTodayNotDoneYetDoesNotBreak() {
        let r = Streaks.daily(active: range("2026-09-10", "2026-09-12"), today: day("2026-09-13"),
                              since: day("2026-09-01"), calendar: cal)
        XCTAssertEqual(r.current, 3)
        XCTAssertEqual(r.best, 3)
    }

    func testMissedDayWithoutFreezeBreaks() {
        var active = range("2026-09-08", "2026-09-10")
        active.insert(day("2026-09-12"))
        let r = Streaks.daily(active: active, today: day("2026-09-12"), since: day("2026-09-08"), calendar: cal)
        XCTAssertEqual(r.current, 1)
        XCTAssertEqual(r.best, 3)
        XCTAssertTrue(r.frozen.isEmpty)
    }

    func testFullWeekEarnsFreezeThatCoversAMiss() {
        var active = range("2026-09-07", "2026-09-13") // Mon–Sun
        active.insert(day("2026-09-15"))               // skip Mon 14th
        let r = Streaks.daily(active: active, today: day("2026-09-15"), since: day("2026-09-07"), calendar: cal)
        XCTAssertEqual(r.current, 8)
        XCTAssertEqual(r.freezes, 0)
        XCTAssertEqual(r.frozen, [day("2026-09-14")])
    }

    func testFreezesCapAtTwo() {
        let r = Streaks.daily(active: range("2026-08-03", "2026-09-06"), today: day("2026-09-07"),
                              since: day("2026-08-03"), calendar: cal)
        XCTAssertEqual(r.freezes, Streaks.maxFreezes)
    }

    func testWeeklyStreakIgnoresUnfinishedWeek() {
        let dates = [day("2026-08-31"), day("2026-09-01"), day("2026-09-02"),
                     day("2026-09-07"), day("2026-09-09"), day("2026-09-11"),
                     day("2026-09-14")]
        let r = Streaks.weekly(dates: dates, perWeek: 3, today: day("2026-09-16"), calendar: cal)
        XCTAssertEqual(r.current, 2)
        XCTAssertEqual(r.best, 2)
    }

    func testWeeklyStreakBreaksOnShortWeek() {
        let dates = [day("2026-08-31"), day("2026-09-01"), day("2026-09-02"), day("2026-09-08")]
        let r = Streaks.weekly(dates: dates, perWeek: 3, today: day("2026-09-16"), calendar: cal)
        XCTAssertEqual(r.current, 0)
        XCTAssertEqual(r.best, 1)
    }

    func testRecapPeriodEndsOnSunday() {
        let midweek = WeekRecap.period(endingNear: day("2026-09-30"), calendar: cal)
        XCTAssertEqual(midweek.count, 7)
        XCTAssertEqual(midweek.last, day("2026-09-27"))
        XCTAssertEqual(midweek.first, day("2026-09-21"))
        let sunday = WeekRecap.period(endingNear: day("2026-10-04"), calendar: cal)
        XCTAssertEqual(sunday.last, day("2026-10-04"))
    }

    func testGoalOptionsNudgePastThisWeek() {
        let recap = WeekRecap(days: [], scores: [], closedDays: 2, bestDay: nil, homeMeals: 10, outMeals: 4,
                              place: nil, photos: [], workouts: 3, calories: 0, volume: 0, bestLift: nil,
                              focusMinutes: 0, focusRounds: 0, checkIns: 0, averageWater: 80)
        let options = recap.goalOptions(waterGoal: 100, eatOutGoal: 5)
        XCTAssertEqual(options.map { $0.goal }, WeekGoal.allCases)
        XCTAssertEqual(options[0].title, "Eat out 3× or less")
        XCTAssertEqual(options[1].title, "4 workouts")
        XCTAssertEqual(options[3].title, "Close 3 days")
    }
}
