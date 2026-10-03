import XCTest
import UIKit
@testable import Daily

final class MapsAndGoogleTests: XCTestCase {
    func testGoogleMapsLink() {
        let url = MapsApp.url(for: .google, name: "La Taqueria", address: "2889 Mission St", latitude: 37.75, longitude: -122.41,
                              googlePlaceID: "abc123")!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(url.host, "www.google.com")
        XCTAssertEqual(items.first { $0.name == "query" }?.value, "La Taqueria, 2889 Mission St")
        XCTAssertEqual(items.first { $0.name == "query_place_id" }?.value, "abc123")
    }

    func testAppleMapsLink() {
        let url = MapsApp.url(for: .apple, name: "Tartine", address: "", latitude: 37.76, longitude: -122.42)!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(url.host, "maps.apple.com")
        XCTAssertEqual(items.first { $0.name == "ll" }?.value, "37.76,-122.42")
    }

    func testParsesGooglePlaces() throws {
        let json = """
        {"places":[{"id":"ChIJ1","displayName":{"text":"Kunjip","languageCode":"en"},
          "formattedAddress":"220 Castro St, Mountain View, CA","location":{"latitude":37.39,"longitude":-122.08},
          "rating":4.3,"userRatingCount":1200,"priceLevel":"PRICE_LEVEL_MODERATE",
          "googleMapsUri":"https://maps.google.com/?cid=1","primaryTypeDisplayName":{"text":"Korean Restaurant"}}]}
        """
        let places = try PlaceSearch.parseGoogle(Data(json.utf8))
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].name, "Kunjip")
        XCTAssertEqual(places[0].price, "$$")
        XCTAssertEqual(places[0].cuisine, "Korean Restaurant")
        XCTAssertEqual(places[0].google?.rating, 4.3)
        XCTAssertEqual(places[0].google?.id, "ChIJ1")
        XCTAssertTrue(try PlaceSearch.parseGoogle(Data("{}".utf8)).isEmpty, "No results comes back as an empty object")
    }
}

final class JournalTests: XCTestCase {
    func testPhotosAreShrunk() {
        let big = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 3000)).image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4000, height: 3000))
        }
        let data = ImageTools.jpeg(from: big)!
        let back = UIImage(data: data)!
        XCTAssertEqual(max(back.size.width * back.scale, back.size.height * back.scale), 1600, accuracy: 1)
    }

    func testFeedGroupsByDayNewestFirst() {
        let morning = JournalEntry(date: day(1, hour: 9), photo: Data([1]))
        let noon = JournalEntry(date: day(1, hour: 12), photo: Data([2]))
        let earlier = JournalEntry(date: day(0, hour: 12), photo: nil, caption: "No photo, still a check-in")
        let meal = FoodEntry(date: day(1, hour: 19), slot: .dinner, name: "Ramen", source: .out)
        meal.photo = Data([3])
        let noPhotoMeal = FoodEntry(date: day(1, hour: 13), slot: .lunch, name: "Salad", source: .prepped)

        let days = JournalItem.days(entries: [morning, noon, earlier], meals: [meal, noPhotoMeal])
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].items.count, 3, "Meals without photos stay out of the journal")
        XCTAssertEqual(days[0].items.first?.date, day(1, hour: 19))
        XCTAssertEqual(days[1].items.count, 1)
    }

    func testCheckInPromptWindow() {
        UserDefaults.standard.set(12 * 60 + 30, forKey: CheckIn.timeKey)
        defer { UserDefaults.standard.removeObject(forKey: CheckIn.timeKey) }
        XCTAssertFalse(CheckIn.shouldPrompt(at: day(0, hour: 10), entries: []))
        XCTAssertTrue(CheckIn.shouldPrompt(at: day(0, hour: 12), entries: []))
        XCTAssertTrue(CheckIn.shouldPrompt(at: day(0, hour: 16), entries: []))
        XCTAssertFalse(CheckIn.shouldPrompt(at: day(0, hour: 18), entries: []))
        let done = JournalEntry(date: day(0, hour: 12, minute: 40), photo: nil)
        XCTAssertFalse(CheckIn.shouldPrompt(at: day(0, hour: 13), entries: [done]), "Once you've checked in it goes away")
    }
}
