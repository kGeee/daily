import XCTest
@testable import Daily

final class SyncTests: XCTestCase {
    func testUsesICloudOnlyWhenWantedAndSignedIn() {
        XCTAssertEqual(DataStore.plan(syncWanted: true, signedIn: true, runningTests: false), .iCloud)
        XCTAssertEqual(DataStore.plan(syncWanted: false, signedIn: true, runningTests: false),
                       .local(reason: "iCloud sync is off"))
        XCTAssertEqual(DataStore.plan(syncWanted: true, signedIn: false, runningTests: false),
                       .local(reason: "Not signed in to iCloud"))
        XCTAssertEqual(DataStore.plan(syncWanted: true, signedIn: true, runningTests: true),
                       .local(reason: "Running tests"))
    }

    func testDedupeKeepsFirstOfEachKey() {
        let items = [("2026-10-04", "gym"), ("2026-10-05", "shuttle"), ("2026-10-04", "off"), ("2026-10-04", "gym")]
        let extras = Dedupe.extras(items, key: { $0.0 })
        XCTAssertEqual(extras.count, 2)
        XCTAssertEqual(extras.map { $0.1 }, ["off", "gym"])
    }

    func testDedupeNothingToRemove() {
        XCTAssertTrue(Dedupe.extras([1, 2, 3], key: { $0 }).isEmpty)
    }

    func testEveryModelIsInTheStore() {
        XCTAssertEqual(DataStore.modelTypes.count, 14)
    }
}
