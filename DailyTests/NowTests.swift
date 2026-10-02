import XCTest
@testable import Daily

final class NowPlanTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func at(_ minutes: Double) -> Date { base.addingTimeInterval(minutes * 60) }

    private func item(_ id: String, from start: Double, to end: Double? = nil, done: Bool = false,
                      category: String = "general") -> SharedStore.Item {
        SharedStore.Item(blockID: id, dayKey: "d", title: id.capitalized, subtitle: "", start: at(start),
                         end: end.map { at($0) }, symbol: "circle", category: category, done: done)
    }

    func testCurrentAndNext() {
        let items = [item("work", from: 0, to: 300), item("gym", from: 330, to: 420)]
        let state = NowPlan.state(at: at(60), items: items)
        XCTAssertEqual(state.current?.blockID, "work")
        XCTAssertEqual(state.next?.blockID, "gym")
    }

    func testShorterBlockInsideLongerOneWins() {
        let items = [item("work", from: 0, to: 300), item("lunch", from: 180)]
        XCTAssertEqual(NowPlan.state(at: at(190), items: items).current?.blockID, "lunch")
        // Lunch has no end, so it lasts the default 30 minutes, then work shows again.
        XCTAssertEqual(NowPlan.state(at: at(215), items: items).current?.blockID, "work")
    }

    func testDoneItemsAreSkipped() {
        let items = [item("work", from: 0, to: 300), item("lunch", from: 180, done: true)]
        XCTAssertEqual(NowPlan.state(at: at(190), items: items).current?.blockID, "work")
    }

    func testFreeTimeHasNoCurrent() {
        let items = [item("work", from: 0, to: 60), item("dinner", from: 120)]
        let state = NowPlan.state(at: at(90), items: items)
        XCTAssertNil(state.current)
        XCTAssertEqual(state.next?.blockID, "dinner")
    }

    func testProgressAndMinutesLeft() {
        let work = item("work", from: 0, to: 100)
        XCTAssertEqual(NowPlan.progress(of: work, at: at(25)), 0.25, accuracy: 0.0001)
        XCTAssertEqual(NowPlan.minutesLeft(in: work, at: at(25)), 75)
        XCTAssertEqual(NowPlan.minutesLeft(in: work, at: at(99.5)), 1)
        XCTAssertEqual(NowPlan.leftLabel(minutes: 75), "1h 15m left")
        XCTAssertEqual(NowPlan.leftLabel(minutes: 120), "2h left")
        XCTAssertEqual(NowPlan.leftLabel(minutes: 12), "12 min left")
    }

    func testChangeDatesAreSortedAndUnique() {
        let items = [item("a", from: 0, to: 60), item("b", from: 60, to: 90)]
        XCTAssertEqual(NowPlan.changeDates(after: at(10), items: items), [at(60), at(90)])
    }

    func testLiveActivityContentForCurrentBlock() {
        let items = [item("work", from: 0, to: 300, category: "work"), item("gym", from: 330, to: 420)]
        let content = NowActivity.content(for: NowPlan.state(at: at(60), items: items), at: at(60))
        XCTAssertEqual(content?.title, "Work")
        XCTAssertEqual(content?.itemID, "d|work")
        XCTAssertEqual(content?.end, at(300))
        XCTAssertEqual(content?.isUpcoming, false)
        XCTAssertEqual(content?.nextTitle, "Gym")
    }

    func testLiveActivityShowsUpNextOnlyWhenSoon() {
        let items = [item("dinner", from: 90)]
        let soon = NowActivity.content(for: NowPlan.state(at: at(0), items: items), at: at(0))
        XCTAssertEqual(soon?.isUpcoming, true)
        XCTAssertEqual(soon?.end, at(90))

        let later = [item("dinner", from: 600)]
        XCTAssertNil(NowActivity.content(for: NowPlan.state(at: at(0), items: later), at: at(0)))
    }
}
