import XCTest
@testable import Daily

final class RoutineResolverTests: XCTestCase {
    override func setUp() { resetPrefs() }
    override func tearDown() { resetPrefs() }

    /// VTA to Mountain View at 4:00, hang out 2 hours, then the next Caltrain home.
    private var mountainViewEvening: [RoutineStep] {
        [
            RoutineStep(id: "vta", title: "VTA to Mountain View", kind: .vta, timing: .fixed, time: 16 * 60, duration: 25),
            RoutineStep(id: "hang", title: "Hang out", kind: .hangout, timing: .afterPrevious, duration: 120, isDeparture: false),
            RoutineStep(id: "train", title: "Caltrain home", kind: .caltrain, timing: .firstAfter,
                        readyAfterPrevious: true, timetableID: "mv", duration: 30, walkMinutes: 5)
        ]
    }
    private let mvTimes: (String) -> [Int] = { $0 == "mv" ? [1100, 1110, 1130] : [] }

    func testStepsChain() {
        let r = RoutineResolver.resolve(mountainViewEvening, timesFor: mvTimes)
        XCTAssertEqual(r.map { $0.start }, [960, 985, 1110])
        XCTAssertEqual(r[1].end, 1105)
        XCTAssertEqual(r[2].nextAlternative, 1130, "Shows the train after as a backup")
        XCTAssertFalse(r[2].isEstimate)
    }

    func testChangingAnEarlierStepMovesLaterOnes() {
        let r = RoutineResolver.resolve(mountainViewEvening, overrides: ["vta": StepOverride(time: 1000)], timesFor: mvTimes)
        XCTAssertEqual(r[0].start, 1000)
        XCTAssertEqual(r[1].start, 1025)
        XCTAssertTrue(r[2].isEstimate, "No train after 7:10 PM in this timetable, so it's an estimate")
    }

    func testSkippingAStep() {
        let r = RoutineResolver.resolve(mountainViewEvening, overrides: ["hang": StepOverride(skipped: true)], timesFor: mvTimes)
        XCTAssertEqual(r.map { $0.step.id }, ["vta", "train"])
        XCTAssertEqual(r[1].start, 1100, "Ready at 4:30 (VTA end + 5 min walk), so the first train is 6:20")
    }

    func testLastBefore() {
        let step = RoutineStep(id: "am", title: "Caltrain", kind: .caltrain, timing: .lastBefore, time: 465, timetableID: "am")
        let r = RoutineResolver.resolve([step]) { _ in [420, 450, 470] }
        XCTAssertEqual(r[0].start, 450)
        XCTAssertEqual(r[0].nextAlternative, 420)
    }

    func testEndTimeWins() {
        let work = RoutineStep(id: "w", title: "Work", kind: .work, timing: .fixed, time: 510, duration: 30, endTime: 960)
        XCTAssertEqual(RoutineResolver.resolve([work])[0].end, 960)
    }
}

final class RoutineDefaultsTests: XCTestCase {
    override func setUp() { resetPrefs() }
    override func tearDown() { resetPrefs() }

    func testCaltrainDayTakesVTAFromSunnyvale() {
        Timetables.setTimes(Timetable.toWork, [420, 450, 470])
        let blocks = RoutineResolver.blocks(for: day(4), type: .caltrain, gymNote: nil)
        let train = blocks.first { $0.id == "out" }!
        let vta = blocks.first { $0.id == "vta-in" }!
        XCTAssertEqual(train.start, ClockTime(7, 30).on(day(4)))
        XCTAssertEqual(vta.start, ClockTime(8, 3).on(day(4)), "Arrives 8:00, VTA 3 min later")
        XCTAssertEqual(vta.symbol, "lightrail.fill")
    }

    func testMountainViewDayUsesItsOwnTimetable() {
        Timetables.setTimes(Timetable.fromMountainView, [19 * 60 + 2, 19 * 60 + 32])
        let blocks = RoutineResolver.blocks(for: day(3), type: .mountainView, gymNote: nil)
        XCTAssertTrue(blocks.contains { $0.title == "Hang out in Mountain View" })
        let home = blocks.first { $0.id == "home" }!
        // VTA 4:00 + 25 min + 2 h hang out = 6:25, + 5 min walk → first train at/after 6:30 is 7:02.
        XCTAssertEqual(home.start, ClockTime(19, 2).on(day(3)))
        XCTAssertFalse(home.isEstimate)
    }

    func testSavedRoutineReplacesDefaultAndResetRestoresIt() {
        var steps = Routines.steps(for: .shuttle)
        steps[0].time = 7 * 60 + 15
        Routines.save(steps, for: .shuttle)
        XCTAssertTrue(Routines.isCustomized(.shuttle))
        let planner = DayPlanner(pattern: MySchedule.defaultPattern, overrides: [])
        XCTAssertEqual(planner.blocks(for: day(0), lunchNote: nil, dinnerNote: nil).first { $0.id == "out" }?.start,
                       ClockTime(7, 15).on(day(0)))
        Routines.reset(.shuttle)
        XCTAssertFalse(Routines.isCustomized(.shuttle))
        XCTAssertEqual(Routines.steps(for: .shuttle).first?.time, 7 * 60 + 45)
    }

    func testOneDayOverrideOnlyAffectsThatDay() {
        Routines.setOverride(StepOverride(time: 8 * 60), step: "out", dayKey: DayKey.of(day(0)))
        let planner = DayPlanner(pattern: MySchedule.defaultPattern, overrides: [])
        XCTAssertEqual(planner.blocks(for: day(0), lunchNote: nil, dinnerNote: nil).first { $0.id == "out" }?.start,
                       ClockTime(8, 0).on(day(0)))
        XCTAssertEqual(planner.blocks(for: day(3), lunchNote: nil, dinnerNote: nil).first { $0.id == "out" }?.start,
                       ClockTime(7, 45).on(day(3)))
    }

    func testRoutineBlocksAreMarkedEditable() {
        let blocks = DayPlanner(pattern: MySchedule.defaultPattern, overrides: [])
            .blocks(for: day(1), lunchNote: nil, dinnerNote: nil)
        XCTAssertEqual(blocks.first { $0.id == "gym" }?.routineType, .gym)
        XCTAssertNil(blocks.first { $0.id == "lunch" }?.routineType)
    }

    func testLegacyTrainListsStillWork() {
        UserDefaults.standard.set("450,420", forKey: Pref.morningTrains)
        XCTAssertEqual(Timetables.times(Timetable.toWork), [420, 450])
    }
}
