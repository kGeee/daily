import XCTest
@testable import Daily

final class MenuBarTitleTests: XCTestCase {
    private func item(_ title: String, start: Date, minutes: Int) -> SharedStore.Item {
        SharedStore.Item(blockID: title, dayKey: "2026-10-04", title: title, subtitle: "", start: start,
                         end: start.addingTimeInterval(Double(minutes) * 60), symbol: "clock", category: "general", done: false)
    }

    func testShowsCurrentWithTimeLeft() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let groceries = item("Groceries", start: now.addingTimeInterval(-15 * 60), minutes: 45)
        let state = NowPlan.state(at: now, items: [groceries])
        XCTAssertEqual(NowPlan.menuBarTitle(for: state, at: now), "Groceries · 30m")
    }

    func testShowsNextWhenNothingIsOn() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let gym = item("Gym", start: now.addingTimeInterval(80 * 60), minutes: 60)
        let state = NowPlan.state(at: now, items: [gym])
        XCTAssertEqual(NowPlan.menuBarTitle(for: state, at: now), "Gym in 1h 20m")
    }

    func testIconOnlyWhenNothingSoon() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let later = item("Dinner", start: now.addingTimeInterval(5 * 3600), minutes: 60)
        XCTAssertNil(NowPlan.menuBarTitle(for: NowPlan.state(at: now, items: [later]), at: now))
    }

    func testLongTitlesAreClipped() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let long = item("Work on the side project before Monday", start: now, minutes: 90)
        let title = NowPlan.menuBarTitle(for: NowPlan.state(at: now, items: [long]), at: now)
        XCTAssertEqual(title, "Work on the side …" + " · 1h 30m")
    }

    func testShortDuration() {
        XCTAssertEqual(NowPlan.shortDuration(minutes: 45), "45m")
        XCTAssertEqual(NowPlan.shortDuration(minutes: 120), "2h")
        XCTAssertEqual(NowPlan.shortDuration(minutes: 61), "1h 1m")
    }
}

final class ImageToolsTests: XCTestCase {
    /// A tiny 40×20 JPEG made in code.
    private func sampleJPEG(width: Int, height: Int) -> Data {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ImageTools.jpeg(ctx.makeImage()!, quality: 0.9)!
    }

    func testShrinksToMaxDimension() {
        let big = sampleJPEG(width: 3000, height: 1500)
        let small = ImageTools.cgImage(from: ImageTools.jpeg(fromData: big)!)!
        XCTAssertEqual(max(small.width, small.height), 1600)
    }

    func testDoesNotEnlargeSmallImages() {
        let tiny = sampleJPEG(width: 40, height: 20)
        let out = ImageTools.cgImage(from: ImageTools.forAI(tiny)!)!
        XCTAssertEqual(out.width, 40)
    }
}
