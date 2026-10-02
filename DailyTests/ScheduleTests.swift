import XCTest
@testable import Daily

/// Resets every schedule setting so tests start from the defaults.
func resetPrefs() {
    let keys = Backup.intKeys + Backup.stringKeys + Backup.boolKeys + Backup.dataKeys + Backup.timetableKeys
    for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    for table in Timetable.defaults { UserDefaults.standard.removeObject(forKey: Timetables.timesKey(table.id)) }
}

/// A date in the week of Mon Oct 5, 2026. weekdayOffset 0 = Monday … 6 = Sunday.
func day(_ weekdayOffset: Int, hour: Int = 0, minute: Int = 0) -> Date {
    var parts = DateComponents()
    parts.year = 2026; parts.month = 10; parts.day = 5 + weekdayOffset
    parts.hour = hour; parts.minute = minute
    return Calendar.current.date(from: parts)!
}

final class ClockTimeTests: XCTestCase {
    func testMinutesWrapAroundMidnight() {
        XCTAssertEqual(ClockTime(minutes: 465), ClockTime(7, 45))
        XCTAssertEqual(ClockTime(minutes: 1440 + 30), ClockTime(0, 30))
        XCTAssertEqual(ClockTime(minutes: -30), ClockTime(23, 30))
    }

    func testAdding() {
        XCTAssertEqual(ClockTime(15, 0).adding(30), ClockTime(15, 30))
        XCTAssertEqual(ClockTime(23, 50).adding(20), ClockTime(0, 10))
        XCTAssertEqual(ClockTime(7, 45).totalMinutes, 465)
    }

    func testOnDayKeepsTheDate() {
        let date = ClockTime(7, 45).on(day(0))
        let parts = Calendar.current.dateComponents([.day, .hour, .minute], from: date)
        XCTAssertEqual(parts.day, 5)
        XCTAssertEqual(parts.hour, 7)
        XCTAssertEqual(parts.minute, 45)
    }
}

final class DayPlannerTests: XCTestCase {
    override func setUp() { resetPrefs() }

    private let planner = DayPlanner(pattern: "shuttle,gym,gym,shuttle,caltrain", overrides: [])

    func testUsualWeek() {
        XCTAssertEqual(planner.type(for: day(0)), .shuttle)   // Mon
        XCTAssertEqual(planner.type(for: day(1)), .gym)       // Tue
        XCTAssertEqual(planner.type(for: day(4)), .caltrain)  // Fri
        XCTAssertNil(planner.type(for: day(5)))               // Sat
        XCTAssertNil(planner.type(for: day(6)))               // Sun
    }

    func testOverrideWinsForThatDayOnly() {
        let override = DayTypeOverride(dayKey: DayKey.of(day(0)), typeRaw: DayType.gym.rawValue)
        let p = DayPlanner(pattern: planner.pattern, overrides: [override])
        XCTAssertEqual(p.type(for: day(0)), .gym)
        XCTAssertEqual(p.type(for: day(3)), .shuttle)
    }

    func testUpdatingPattern() {
        let updated = DayPlanner.updating(pattern: "shuttle,gym,gym,shuttle,caltrain", weekday: 6, to: .shuttle)
        XCTAssertEqual(updated, "shuttle,gym,gym,shuttle,shuttle")
        XCTAssertEqual(DayPlanner.updating(pattern: "", weekday: 2, to: .gym), "gym,shuttle,shuttle,shuttle,shuttle")
    }

    func testShuttleDay() {
        let blocks = planner.blocks(for: day(0), lunchNote: nil, dinnerNote: nil)
        let ids = blocks.map { $0.id }
        XCTAssertEqual(ids.first, "wake")
        XCTAssertTrue(ids.contains("out"))
        XCTAssertTrue(ids.contains("home"))
        XCTAssertFalse(ids.contains("gym"))
        XCTAssertEqual(blocks.map { $0.start }, blocks.map { $0.start }.sorted(), "Timeline should be in time order")

        let out = blocks.first { $0.id == "out" }!
        XCTAssertEqual(out.start, ClockTime(7, 45).on(day(0)))
        XCTAssertEqual(out.leaveBy, ClockTime(7, 35).on(day(0)), "Default 10 min walk to the stop")
        let home = blocks.first { $0.id == "home" }!
        XCTAssertEqual(home.start, ClockTime(16, 0).on(day(0)))
    }

    func testGymDay() {
        let blocks = planner.blocks(for: day(1), lunchNote: nil, dinnerNote: nil, gymNote: "Back day")
        let go = blocks.first { $0.id == "go" }
        let gym = blocks.first { $0.id == "gym" }
        let home = blocks.first { $0.id == "home" }
        XCTAssertEqual(go?.start, ClockTime(15, 0).on(day(1)))
        XCTAssertEqual(gym?.start, ClockTime(15, 30).on(day(1)))
        XCTAssertEqual(gym?.end, ClockTime(16, 55).on(day(1)))
        XCTAssertEqual(gym?.subtitle, "Back day")
        XCTAssertEqual(home?.title, "Caltrain home")
        XCTAssertEqual(home?.isEstimate, true, "No trains saved yet, so the train time is an estimate")
    }

    func testSundayHasMealPrepAndNoCommute() {
        let blocks = planner.blocks(for: day(6), lunchNote: nil, dinnerNote: nil)
        XCTAssertTrue(blocks.contains { $0.id == "prep" })
        XCTAssertFalse(blocks.contains { $0.isDeparture })
    }

    func testMealNotesShowOnTimeline() {
        let blocks = planner.blocks(for: day(0), lunchNote: "Planned: Turkey chili", dinnerNote: nil)
        XCTAssertEqual(blocks.first { $0.id == "lunch" }?.subtitle, "Planned: Turkey chili")
        XCTAssertEqual(blocks.first { $0.id == "dinner" }?.subtitle, "Nothing planned")
    }

    func testSettingsChangeTheTimeline() {
        UserDefaults.standard.set(8 * 60, forKey: Pref.shuttleOut)
        UserDefaults.standard.set(5, forKey: Pref.walkToStop)
        let out = planner.blocks(for: day(0), lunchNote: nil, dinnerNote: nil).first { $0.id == "out" }!
        XCTAssertEqual(out.start, ClockTime(8, 0).on(day(0)))
        XCTAssertEqual(out.leaveBy, ClockTime(7, 55).on(day(0)))
    }
}

final class CaltrainPickTests: XCTestCase {
    override func setUp() { resetPrefs() }

    func testParseAndJoinTrains() {
        XCTAssertEqual(Pref.parseTrains("450,420,abc,"), [420, 450])
        XCTAssertEqual(Pref.joinTrains([450, 420, 450]), "420,450")
    }

    func testMorningPicksLatestTrainThatStillMakesWork() {
        // Work 8:30, 30 min ride, 15 min to the office → must leave by 7:45.
        UserDefaults.standard.set("420,450,470,500", forKey: Pref.morningTrains)
        let pick = MySchedule.caltrainOut
        XCTAssertEqual(pick.time, ClockTime(7, 30))
        XCTAssertFalse(pick.isEstimate)
    }

    func testMorningEstimateWithoutTrains() {
        let pick = MySchedule.caltrainOut
        XCTAssertEqual(pick.time, ClockTime(7, 45))
        XCTAssertTrue(pick.isEstimate)
    }

    func testEveningPicksFirstTrainAfterGym() {
        // Gym 3:30–4:55, 20 min to Sunnyvale → ready at 5:15.
        UserDefaults.standard.set("1012,1032,1062", forKey: Pref.eveningTrains)
        let pick = MySchedule.caltrainAfterGym
        XCTAssertEqual(pick.time, ClockTime(17, 42))
        XCTAssertFalse(pick.isEstimate)
        XCTAssertEqual(MySchedule.trains(after: 1032, count: 2), [ClockTime(17, 42)])
    }
}
