import XCTest
@testable import Daily

final class SetupTests: XCTestCase {
    override func setUp() { resetPrefs() }
    override func tearDown() { resetPrefs() }

    private func answers(_ modes: [CommuteMode]) -> SetupAnswers {
        var a = SetupAnswers()
        a.modes = modes
        a.workStart = 9 * 60
        a.workEnd = 17 * 60
        return a
    }

    func testDrivingDay() {
        var a = answers([.drive])
        a.driveMinutes = 40
        a.parkMinutes = 5
        let plan = Setup.plan(a)
        XCTAssertEqual(plan.dayTypes.map(\.id), ["drive"])
        let steps = plan.routines["drive"] ?? []
        XCTAssertEqual(steps.map(\.id), ["out", "work", "home"])
        XCTAssertEqual(steps[0].kind, .drive)
        XCTAssertEqual(steps[0].time, 9 * 60 - 45, "Leave early enough to drive and park")
        XCTAssertEqual(steps[2].time, 17 * 60)
        XCTAssertTrue(plan.timetables.isEmpty)
    }

    func testTrainDayWithLastMile() {
        var a = answers([.train])
        a.trainLine = "BART"
        a.fromStation = "Daly City"
        a.toStation = "Embarcadero"
        a.trainRide = 25
        a.lastMile = .walk
        a.lastMileMinutes = 8
        let plan = Setup.plan(a)
        XCTAssertEqual(plan.dayTypes.first?.name, "BART day")
        let steps = plan.routines["train"] ?? []
        XCTAssertEqual(steps.map(\.id), ["out", "last-in", "work", "last-out", "home"])
        XCTAssertEqual(steps[0].timing, .lastBefore)
        XCTAssertEqual(steps[0].time, 9 * 60 - 25 - 8, "Last train that still makes the start time")
        XCTAssertEqual(steps[0].timetableID, Setup.trainOut)
        XCTAssertTrue(steps[4].readyAfterPrevious)
        XCTAssertEqual(plan.timetables.map(\.name), ["BART: Daly City → Embarcadero", "BART: Embarcadero → Daly City"])
        XCTAssertEqual(plan.timetables.first?.live, Timetable.Live.none, "Live times are Caltrain only")

        // Resolves into a sensible day even before any train times are added.
        let resolved = RoutineResolver.resolve(steps, timesFor: { _ in [] })
        XCTAssertEqual(resolved.first?.start, 9 * 60 - 33)
        XCTAssertEqual(resolved[1].start, 9 * 60 - 8)
    }

    func testGymAndAfterWorkSpot() {
        var a = answers([.shuttle, .train])
        a.trainLine = "Caltrain"
        a.fromStation = "San Francisco"
        a.toStation = "Sunnyvale"
        a.gym = true
        a.gymMode = .shuttle
        a.gymHome = .train
        a.gymLeave = 15 * 60
        a.outing = true
        a.outingPlace = "Mountain View"
        a.outingMode = .shuttle
        a.outingHome = .train
        let plan = Setup.plan(a)

        XCTAssertEqual(plan.dayTypes.map(\.id), ["shuttle", "train", "gym", "outing"])
        XCTAssertEqual(plan.dayTypes.last?.name, "Mountain View day")
        XCTAssertEqual(plan.routines["gym"]?.map(\.id), ["out", "work", "go", "gym", "home"])
        XCTAssertEqual(plan.routines["gym"]?[1].endTime, 15 * 60, "Work ends when you leave for the gym")
        XCTAssertEqual(plan.routines["gym"]?.last?.timetableID, Setup.trainHome)
        XCTAssertEqual(plan.routines["outing"]?.map(\.id), ["out", "work", "go-out", "hangout", "home"])
        XCTAssertEqual(plan.routines["outing"]?.last?.timetableID, Setup.outingHome)

        let live = Dictionary(uniqueKeysWithValues: plan.timetables.map { ($0.id, $0.live) })
        XCTAssertEqual(live[Setup.trainOut], .homeToWork)
        XCTAssertEqual(live[Setup.trainHome], .sunnyvaleToHome)
        XCTAssertEqual(live[Setup.outingHome], .mountainViewToHome)
    }

    func testWeekDropsKindsThatDontExist() {
        var a = answers([.bike, .remote])
        a.week = ["bike", "remote", "gym", "bike", "remote", "off", "nope"]
        XCTAssertEqual(Setup.plan(a).pattern, "bike,remote,off,bike,remote,off,off")
    }

    func testSuggestedWeek() {
        var a = answers([.drive, .remote])
        a.suggestWeek()
        XCTAssertEqual(a.week, ["drive", "drive", "drive", "drive", "drive", "off", "off"])
    }

    func testApplyMakesCustomDaysUsable() {
        var a = answers([.drive, .bike])
        a.week = ["drive", "bike", "drive", "bike", "drive", "bike", "off"]
        Setup.apply(a)

        XCTAssertEqual(DayType.allCases.map(\.rawValue), ["drive", "bike"])
        XCTAssertNil(DayType(rawValue: "shuttle"), "The original kinds of day are replaced")
        let planner = DayPlanner(pattern: UserDefaults.standard.string(forKey: "weekPattern") ?? "", overrides: [])
        XCTAssertEqual(planner.type(for: day(0))?.rawValue, "drive")
        XCTAssertEqual(planner.type(for: day(5))?.rawValue, "bike", "Weekends can have a kind of day too")
        XCTAssertNil(planner.type(for: day(6)))
        XCTAssertEqual(Routines.steps(for: DayType(rawValue: "bike")!).first?.kind, .bike)
        XCTAssertEqual(DayType(rawValue: "drive")?.title, "Driving day")
    }

    func testDayOffOverride() {
        let off = DayTypeOverride(dayKey: DayKey.of(day(0)), typeRaw: DayPlanner.off)
        let planner = DayPlanner(pattern: MySchedule.defaultPattern, overrides: [off])
        XCTAssertNil(planner.type(for: day(0)))
        XCTAssertEqual(planner.type(for: day(1)), .gym)
    }

    func testNeedsSetupOnlyOnFreshInstalls() {
        let suite = "daily.setup.test"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        XCTAssertTrue(Setup.needsSetup(defaults: d))
        d.set(3, forKey: Pref.revision)
        XCTAssertFalse(Setup.needsSetup(defaults: d), "Someone already using the app isn't sent through setup")
        XCTAssertTrue(d.bool(forKey: Setup.doneKey))
        d.removePersistentDomain(forName: suite)
    }
}
