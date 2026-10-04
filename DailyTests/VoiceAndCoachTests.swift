import XCTest
@testable import Daily

final class VoicePlannerTests: XCTestCase {
    func testParsesTimes() {
        let d = day(6)
        let cal = Calendar.current
        XCTAssertEqual(cal.component(.hour, from: VoicePlanner.time("13:00", on: d)!), 13)
        XCTAssertEqual(cal.component(.minute, from: VoicePlanner.time("9:30", on: d)!), 30)
        XCTAssertEqual(cal.component(.hour, from: VoicePlanner.time("1:15 PM", on: d)!), 13)
        XCTAssertEqual(cal.component(.hour, from: VoicePlanner.time("12:00 AM", on: d)!), 0)
        XCTAssertNil(VoicePlanner.time("later", on: d))
    }

    func testDraftsAreSortedAndFixed() {
        let plan = VoicePlan(events: [
            .init(title: "Gym", start: "19:30", end: "20:45", kind: "gym", note: nil),
            .init(title: "Niners game", start: "13:00", end: "16:00", kind: "general", note: "Levi's"),
            .init(title: "Laundry", start: "21:00", end: "20:00", kind: "chores", note: nil),
            .init(title: " ", start: "10:00", end: nil, kind: nil, note: nil),
            .init(title: "Groceries", start: "soon", end: nil, kind: "food", note: nil)
        ], summary: nil)
        let drafts = VoicePlanner.drafts(from: plan, on: day(6))
        XCTAssertEqual(drafts.map(\.title), ["Niners game", "Gym", "Laundry"], "Blank titles and bad times are dropped")
        XCTAssertEqual(drafts[0].minutes, 180)
        XCTAssertEqual(drafts[1].kind, .gym)
        XCTAssertEqual(drafts[2].minutes, 60, "An end before the start becomes an hour")
        XCTAssertEqual(drafts[2].kind, .general, "Unknown kinds fall back to Other")
    }

    func testPromptIncludesExistingDayAndWhatTheySaid() {
        let block = TimelineBlock(id: "wake", start: day(6, hour: 8), title: "Rise and shine", category: .sleep, symbol: "alarm")
        let text = VoicePlanner.prompt(text: "niners game 1-4", day: day(6), now: day(6, hour: 10), blocks: [block])
        XCTAssertTrue(text.contains("Rise and shine"))
        XCTAssertTrue(text.contains("niners game 1-4"))
        XCTAssertTrue(text.contains("don't schedule anything before"))
    }
}

final class CoachTests: XCTestCase {
    private func sets(_ weight: Double, _ reps: [Int]) -> [SetLog] {
        reps.enumerated().map { i, r in
            let s = SetLog(exercise: "Squat", index: i, weight: weight, reps: r)
            s.isDone = true
            return s
        }
    }

    func testAddsWeightAfterHittingTheTopOfTheRange() {
        let t = Coach.target(lastSets: sets(185, [10, 10, 10]))
        XCTAssertEqual(t?.weight, 190)
        XCTAssertEqual(t?.reps, 8)
    }

    func testAddsARepInTheMiddle() {
        let t = Coach.target(lastSets: sets(155, [10, 9, 8]))
        XCTAssertEqual(t?.weight, 155)
        XCTAssertEqual(t?.reps, 9)
    }

    func testHoldsWeightBelowTheRange() {
        let t = Coach.target(lastSets: sets(225, [6, 5]))
        XCTAssertEqual(t?.weight, 225)
        XCTAssertEqual(t?.reps, 8)
    }

    func testSmallJumpsForLightWeightsAndBodyweight() {
        XCTAssertEqual(Coach.target(lastSets: sets(20, [10, 10]))?.weight, 22.5)
        XCTAssertEqual(Coach.target(lastSets: sets(0, [12, 15]))?.reps, 13)
        XCTAssertNil(Coach.target(lastSets: []))
    }

    func testCaloriesUseWeightAndCardio() {
        // 60 min lifting at 170 lb ≈ 5 × 3.5 × 77.1 / 200 × 60 ≈ 405
        XCTAssertEqual(Burn.estimate(totalMinutes: 60, cardioMinutes: 0, cardio: nil, weightLb: 170), 405)
        let withRun = Burn.estimate(totalMinutes: 60, cardioMinutes: 20, cardio: .run, weightLb: 170)
        XCTAssertGreaterThan(withRun, 405, "Running burns more than lifting")
        XCTAssertGreaterThan(Burn.estimate(totalMinutes: 60, cardioMinutes: 0, cardio: nil, weightLb: 220), 405)
    }

    func testVolumeCountsFinishedSetsOnly() {
        var all = sets(100, [10, 10])
        let notDone = SetLog(exercise: "Squat", index: 2, weight: 100, reps: 10)
        all.append(notDone)
        XCTAssertEqual(Coach.volume(all), 2000)
    }
}
