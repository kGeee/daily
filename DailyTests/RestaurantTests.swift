import XCTest
import SwiftData
@testable import Daily

final class RestaurantRankingTests: XCTestCase {
    func testScoresSpreadAcrossEachGroup() {
        XCTAssertEqual(RestaurantRanking.score(position: 0, count: 1, feeling: .loved), 10)
        XCTAssertEqual(RestaurantRanking.score(position: 0, count: 4, feeling: .loved), 10)
        XCTAssertEqual(RestaurantRanking.score(position: 3, count: 4, feeling: .loved), 7.5)
        XCTAssertEqual(RestaurantRanking.score(position: 0, count: 2, feeling: .fine), 6.7)
        XCTAssertEqual(RestaurantRanking.score(position: 0, count: 1, feeling: .disliked), 3.3)
        XCTAssertGreaterThan(RestaurantRanking.score(position: 9, count: 10, feeling: .loved),
                             RestaurantRanking.score(position: 0, count: 10, feeling: .fine))
    }

    func testInsertionFindsTheSpotInFewQuestions() {
        // Existing list (best first) has 7 places; the new one belongs at index 5.
        var ins = RestaurantRanking.Insertion(count: 7)
        var questions = 0
        while !ins.isDone {
            ins.answer(newIsBetter: 5 <= ins.middle)
            questions += 1
        }
        XCTAssertEqual(ins.position, 5)
        XCTAssertLessThanOrEqual(questions, 3)
    }

    func testBestAndWorstEnds() {
        var best = RestaurantRanking.Insertion(count: 4)
        while !best.isDone { best.answer(newIsBetter: true) }
        XCTAssertEqual(best.position, 0)
        var worst = RestaurantRanking.Insertion(count: 4)
        while !worst.isDone { worst.answer(newIsBetter: false) }
        XCTAssertEqual(worst.position, 4)
        XCTAssertTrue(RestaurantRanking.Insertion(count: 0).isDone, "First place in a group needs no questions")
    }

    func testTiePlacesItAboveTheOneCompared() {
        var ins = RestaurantRanking.Insertion(count: 5)
        ins.tie()
        XCTAssertTrue(ins.isDone)
        XCTAssertEqual(ins.position, 2)
    }

    @MainActor
    func testInsertAndRemoveRenumberTheGroup() throws {
        let container = try ModelContainer(for: Restaurant.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let a = Restaurant(name: "A"), b = Restaurant(name: "B"), c = Restaurant(name: "C")
        for r in [a, b, c] { context.insert(r) }
        RestaurantRanking.insert(a, feeling: .loved, at: 0, among: [a, b, c])
        RestaurantRanking.insert(b, feeling: .loved, at: 0, among: [a, b, c])
        RestaurantRanking.insert(c, feeling: .loved, at: 1, among: [a, b, c])
        XCTAssertEqual(RestaurantRanking.list([a, b, c]).map(\.name), ["B", "C", "A"])
        XCTAssertEqual(RestaurantRanking.scores([a, b, c])[b.id], 10)

        RestaurantRanking.remove(c, among: [a, b, c])
        XCTAssertNil(c.feeling)
        XCTAssertEqual(RestaurantRanking.list([a, b, c]).map(\.name), ["B", "A"])
        XCTAssertEqual(a.rank, 1)
        _ = container
    }

    func testMealGuessByTime() {
        XCTAssertEqual(MealSlot.guess(for: day(0, hour: 8)), .breakfast)
        XCTAssertEqual(MealSlot.guess(for: day(0, hour: 12, minute: 30)), .lunch)
        XCTAssertEqual(MealSlot.guess(for: day(0, hour: 19)), .dinner)
        XCTAssertEqual(MealSlot.guess(for: day(0, hour: 23)), .snack)
    }

    func testParsesYelpSearch() throws {
        let json = """
        {"businesses":[{"id":"tacos-1","name":"La Taqueria","rating":4.5,"review_count":5321,"price":"$$",
          "url":"https://www.yelp.com/biz/la-taqueria","display_phone":"(415) 285-7117",
          "categories":[{"alias":"mexican","title":"Mexican"}],
          "coordinates":{"latitude":37.7509,"longitude":-122.4181},
          "location":{"display_address":["2889 Mission St","San Francisco, CA 94110"]}}],"total":1}
        """
        let places = try PlaceSearch.parseYelp(Data(json.utf8))
        XCTAssertEqual(places.count, 1)
        XCTAssertEqual(places[0].name, "La Taqueria")
        XCTAssertEqual(places[0].cuisine, "Mexican")
        XCTAssertEqual(places[0].price, "$$")
        XCTAssertEqual(places[0].address, "2889 Mission St, San Francisco, CA 94110")
        XCTAssertEqual(places[0].yelp?.rating, 4.5)
        XCTAssertEqual(places[0].yelp?.reviews, 5321)
    }

    func testMatchesSavedPlaceByNameAndLocation() {
        let saved = Restaurant(name: "Tartine Bakery", latitude: 37.7614, longitude: -122.4241)
        let same = PlaceResult(name: "Tartine bakery", latitude: 37.7615, longitude: -122.4240)
        let elsewhere = PlaceResult(name: "Tartine Bakery", latitude: 37.80, longitude: -122.27)
        XCTAssertTrue(RestaurantStore.match(same, in: [saved]) === saved)
        XCTAssertNil(RestaurantStore.match(elsewhere, in: [saved]))
    }
}
